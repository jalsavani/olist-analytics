"""Predict whether an Olist order will be delivered late.

Input : analytics.late_delivery_features (built by sql/14_ml_late_delivery_features.sql)
Output: ml/results/ (metrics, comparison table, error analysis, plots)

Design decisions (each one is something to defend in an interview):

1. TIME-BASED SPLIT. Orders are sorted by purchase time. The first 80 percent train the
   model and the last 20 percent test it. A random split would let the model learn from
   orders placed AFTER the ones it is tested on, which flatters the score and does not
   match how the model would be used (predicting new orders from past ones).

2. BASELINES FIRST. A model only means something relative to what it has to beat.
   - prior: always predict the training late rate (no skill, ROC AUC 0.5).
   - estimated_days only: a one-feature logistic regression. If the full model cannot beat
     this, the extra features are not earning their place.

3. PR AUC (average precision) AS THE MAIN METRIC. Late orders are a small minority, so
   accuracy would be misleading (always predicting "on time" is already highly accurate).
   Precision and recall are also reported for the riskiest 10 percent of orders, which is
   how an operations team would use the model: review the highest-risk orders first.

4. CROSS-VALIDATION THAT RESPECTS TIME. TimeSeriesSplit trains on the past and validates
   on the next block, inside the training period only. The test period is never touched
   until the final evaluation.

5. NO LEAKAGE. Features come from sql/14 and are all known at purchase time.

6. MODEL CHOICE USES VALIDATION, NOT THE TEST SET. The "selected" model is the one with the best
   cross-validated PR AUC inside the training period. The test period is only used to report
   how that choice (and every other model) performs on later data. Choosing the winner by test
   score would quietly turn the test set into a second validation set.

Run:  python ml/train_late_delivery.py            (builds the feature table, then trains)
      python ml/train_late_delivery.py --skip-build   (reuse the existing feature table)
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display needed
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.inspection import permutation_importance
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, precision_recall_curve, roc_auc_score
from sklearn.model_selection import TimeSeriesSplit, cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

PROJECT = "olist-analytics-510317"
RESULTS_DIR = Path(__file__).resolve().parent / "results"

TARGET = "is_late"
TIME_COL = "order_purchase_timestamp"
TEST_FRACTION = 0.2
TOP_FRACTION = 0.10  # "review the riskiest 10 percent of orders"
RANDOM_STATE = 42

NUMERIC = [
    "purchase_hour",
    "purchase_dow",
    "purchase_month_num",
    "estimated_days",
    "max_distance_km",
    "n_items",
    "n_sellers",
    "n_distinct_products",
    "total_weight_g",
    "max_item_volume_cm3",
    "items_revenue",
    "freight_total",
    "freight_ratio",
    "max_installments",
]
BOOLEAN = ["all_sellers_same_state", "paid_with_credit_card"]
CATEGORICAL = ["customer_state"]
FEATURES = NUMERIC + BOOLEAN + CATEGORICAL


# ---------------------------------------------------------------- data


def build_feature_table(client) -> None:
    """(Re)create analytics.late_delivery_features by running sql/14. Safe to repeat."""
    sql_file = Path(__file__).resolve().parent.parent / "sql" / "14_ml_late_delivery_features.sql"
    client.query(sql_file.read_text()).result()


def load_features(build: bool = True) -> pd.DataFrame:
    """Read the feature table from BigQuery (needs the gcloud login from the README)."""
    from google.cloud import bigquery

    client = bigquery.Client(project=PROJECT)
    if build:
        print("Building analytics.late_delivery_features ...")
        build_feature_table(client)
    sql = f"SELECT * FROM `{PROJECT}.analytics.late_delivery_features`"
    return client.query(sql).to_dataframe()


def _to_float(series: pd.Series) -> pd.Series:
    """Turn BigQuery's nullable dtypes (Int64, boolean, ...) into plain floats with NaN."""
    return series.astype("object").map(lambda v: np.nan if pd.isna(v) else float(v)).astype(float)


def prepare(df: pd.DataFrame) -> pd.DataFrame:
    """Sort by time and coerce column types. Returns a new frame."""
    missing = [c for c in FEATURES + [TARGET, TIME_COL] if c not in df.columns]
    if missing:
        raise ValueError(f"Feature table is missing columns: {missing}")

    out = df.copy()
    out[TIME_COL] = pd.to_datetime(out[TIME_COL], utc=True)
    for col in NUMERIC + BOOLEAN + [TARGET]:
        out[col] = _to_float(out[col])
    out[CATEGORICAL[0]] = out[CATEGORICAL[0]].astype("object").where(out[CATEGORICAL[0]].notna(), "unknown")
    out = out.dropna(subset=[TARGET]).sort_values(TIME_COL).reset_index(drop=True)
    out[TARGET] = out[TARGET].astype(int)
    return out


def time_split(df: pd.DataFrame, test_fraction: float = TEST_FRACTION):
    """First (1 - test_fraction) of orders by time for training, the rest for testing."""
    cut = int(len(df) * (1 - test_fraction))
    return df.iloc[:cut].copy(), df.iloc[cut:].copy()


# ---------------------------------------------------------------- models


def _preprocessor(columns: list[str], scale: bool) -> ColumnTransformer:
    numeric_cols = [c for c in columns if c in NUMERIC + BOOLEAN]
    categorical_cols = [c for c in columns if c in CATEGORICAL]

    steps = [("impute", SimpleImputer(strategy="median", add_indicator=True))]
    if scale:
        steps.append(("scale", StandardScaler()))

    transformers = []
    if numeric_cols:
        transformers.append(("num", Pipeline(steps), numeric_cols))
    if categorical_cols:
        transformers.append(
            ("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=False), categorical_cols)
        )
    return ColumnTransformer(transformers)


def build_models() -> dict[str, tuple[Pipeline, list[str]]]:
    """name -> (pipeline, feature columns it uses)."""
    return {
        "baseline_prior": (
            Pipeline([("prep", _preprocessor(["estimated_days"], False)), ("clf", DummyClassifier(strategy="prior"))]),
            ["estimated_days"],
        ),
        "logistic_estimated_days_only": (
            Pipeline(
                [
                    ("prep", _preprocessor(["estimated_days"], True)),
                    ("clf", LogisticRegression(max_iter=1000)),
                ]
            ),
            ["estimated_days"],
        ),
        "logistic_regression": (
            Pipeline(
                [
                    ("prep", _preprocessor(FEATURES, True)),
                    ("clf", LogisticRegression(max_iter=2000)),
                ]
            ),
            FEATURES,
        ),
        "hist_gradient_boosting": (
            Pipeline(
                [
                    ("prep", _preprocessor(FEATURES, False)),
                    (
                        "clf",
                        HistGradientBoostingClassifier(
                            learning_rate=0.05,
                            max_iter=200,
                            max_depth=4,
                            l2_regularization=1.0,
                            random_state=RANDOM_STATE,
                        ),
                    ),
                ]
            ),
            FEATURES,
        ),
    }


# ---------------------------------------------------------------- evaluation


def top_fraction_metrics(y_true: np.ndarray, score: np.ndarray, fraction: float = TOP_FRACTION) -> dict:
    """Precision, recall and lift when only the highest-scored `fraction` of orders are flagged."""
    n_flag = max(1, int(round(len(score) * fraction)))
    order = np.argsort(-score, kind="stable")[:n_flag]
    flagged_late = y_true[order].sum()
    total_late = y_true.sum()
    prevalence = y_true.mean()
    precision = flagged_late / n_flag
    return {
        "flagged_orders": int(n_flag),
        "precision": float(precision),
        "recall": float(flagged_late / total_late) if total_late else float("nan"),
        "lift": float(precision / prevalence) if prevalence else float("nan"),
    }


def evaluate(pipe: Pipeline, cols: list[str], test: pd.DataFrame) -> tuple[dict, np.ndarray]:
    y = test[TARGET].to_numpy()
    score = pipe.predict_proba(test[cols])[:, 1]
    result = {
        "roc_auc": float(roc_auc_score(y, score)),
        "pr_auc": float(average_precision_score(y, score)),
        "late_rate_test": float(y.mean()),
    }
    top = top_fraction_metrics(y, score)
    result.update({f"top10_{k}": v for k, v in top.items()})
    return result, score


def decile_table(y: np.ndarray, score: np.ndarray) -> pd.DataFrame:
    """Orders ranked by predicted risk and cut into 10 equal groups (1 = riskiest)."""
    frame = pd.DataFrame({"y": y, "score": score})
    frame["rank"] = frame["score"].rank(method="first", ascending=False)
    frame["risk_decile"] = pd.qcut(frame["rank"], 10, labels=range(1, 11)).astype(int)
    return (
        frame.groupby("risk_decile")
        .agg(orders=("y", "size"), predicted_late_rate=("score", "mean"), actual_late_rate=("y", "mean"))
        .round(4)
        .reset_index()
    )


def state_error_analysis(test: pd.DataFrame, score: np.ndarray, min_orders: int = 50) -> pd.DataFrame:
    """Where does the model do well or badly? Grouped by customer state."""
    frame = test[["customer_state", TARGET]].copy()
    frame["score"] = score
    n_flag = max(1, int(round(len(frame) * TOP_FRACTION)))
    flagged = np.zeros(len(frame), dtype=bool)
    flagged[np.argsort(-score, kind="stable")[:n_flag]] = True
    frame["flagged"] = flagged
    frame["late_and_flagged"] = frame["flagged"] & (frame[TARGET] == 1)

    grouped = frame.groupby("customer_state").agg(
        orders=(TARGET, "size"),
        actual_late_rate=(TARGET, "mean"),
        predicted_late_rate=("score", "mean"),
        flagged_share=("flagged", "mean"),
        late_orders=(TARGET, "sum"),
        late_caught=("late_and_flagged", "sum"),
    )
    grouped["recall_in_top10"] = grouped["late_caught"] / grouped["late_orders"].replace(0, np.nan)
    grouped["calibration_gap"] = grouped["predicted_late_rate"] - grouped["actual_late_rate"]
    grouped = grouped[grouped["orders"] >= min_orders].drop(columns=["late_caught"])
    return grouped.round(4).sort_values("calibration_gap").reset_index()


def run_experiment(df: pd.DataFrame, out_dir: Path = RESULTS_DIR, n_cv_splits: int = 5) -> dict:
    """Full experiment on a feature table. Writes results to out_dir and returns the metrics."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    data = prepare(df)
    train, test = time_split(data)
    if train[TARGET].nunique() < 2 or test[TARGET].nunique() < 2:
        raise ValueError("Train or test period contains only one class, so the metrics are undefined.")

    models = build_models()
    rows = []
    scores = {}
    for name, (pipe, cols) in models.items():
        cv_scores = cross_val_score(
            pipe,
            train[cols],
            train[TARGET],
            cv=TimeSeriesSplit(n_splits=n_cv_splits),
            scoring="average_precision",
        )
        pipe.fit(train[cols], train[TARGET])
        metrics, score = evaluate(pipe, cols, test)
        scores[name] = score
        rows.append(
            {
                "model": name,
                "cv_pr_auc_mean": float(cv_scores.mean()),
                "cv_pr_auc_std": float(cv_scores.std()),
                **metrics,
            }
        )
        print(f"  {name:32s} test PR AUC {metrics['pr_auc']:.4f}  ROC AUC {metrics['roc_auc']:.4f}")

    comparison = pd.DataFrame(rows).round(4)
    comparison.to_csv(out_dir / "model_comparison.csv", index=False)

    # Selected model: best cross-validated PR AUC (training period only) among the real candidates.
    # The prior baseline is excluded because it is a reference point, not a candidate.
    candidates = comparison[comparison["model"] != "baseline_prior"]
    best_name = candidates.sort_values("cv_pr_auc_mean", ascending=False).iloc[0]["model"]
    comparison["selected_by_cv"] = comparison["model"] == best_name
    comparison.to_csv(out_dir / "model_comparison.csv", index=False)
    best_pipe, best_cols = models[best_name]
    best_score = scores[best_name]
    y_test = test[TARGET].to_numpy()

    decile_table(y_test, best_score).to_csv(out_dir / "decile_table.csv", index=False)
    state_error_analysis(test, best_score).to_csv(out_dir / "state_error_analysis.csv", index=False)

    # Permutation importance: how much does shuffling each feature hurt PR AUC on the test set?
    sample = test.sample(n=min(5000, len(test)), random_state=RANDOM_STATE)
    perm = permutation_importance(
        best_pipe,
        sample[best_cols],
        sample[TARGET],
        scoring="average_precision",
        n_repeats=3,
        random_state=RANDOM_STATE,
    )
    importance = (
        pd.DataFrame({"feature": best_cols, "importance_mean": perm.importances_mean, "importance_std": perm.importances_std})
        .sort_values("importance_mean", ascending=False)
        .round(5)
    )
    importance.to_csv(out_dir / "permutation_importance.csv", index=False)

    # Precision-recall curves for every model on the test period.
    fig, ax = plt.subplots(figsize=(6.5, 5))
    for name, score in scores.items():
        if name == "baseline_prior":
            continue  # a constant score draws a misleading straight line, the dotted line below is its level
        prec, rec, _ = precision_recall_curve(y_test, score)
        ax.plot(rec, prec, label=name)
    ax.axhline(y_test.mean(), color="grey", linestyle=":", linewidth=1, label="no skill (test late rate)")
    ax.set_xlabel("Recall")
    ax.set_ylabel("Precision")
    ax.set_title("Late-delivery prediction: precision-recall on the held-out period")
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(out_dir / "pr_curves.png", dpi=150)
    plt.close(fig)

    summary = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "rows": int(len(data)),
        "train_rows": int(len(train)),
        "test_rows": int(len(test)),
        "train_period": [str(train[TIME_COL].min()), str(train[TIME_COL].max())],
        "test_period": [str(test[TIME_COL].min()), str(test[TIME_COL].max())],
        "late_rate_train": float(train[TARGET].mean()),
        "late_rate_test": float(test[TARGET].mean()),
        "selected_model": best_name,
        "selection_rule": "highest cross-validated PR AUC within the training period",
        "models": comparison.to_dict(orient="records"),
    }
    (out_dir / "metrics.json").write_text(json.dumps(summary, indent=2))
    return summary


def main(argv: list[str] | None = None) -> int:
    skip_build = "--skip-build" in (argv if argv is not None else sys.argv[1:])
    df = load_features(build=not skip_build)
    print(f"  {len(df):,} rows")
    print("Training and evaluating ...")
    summary = run_experiment(df)
    print(f"Selected model (best cross-validated PR AUC): {summary['selected_model']}")
    print(f"Test late rate {summary['late_rate_test']:.4f} vs train {summary['late_rate_train']:.4f}")
    print(f"Results written to {RESULTS_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
