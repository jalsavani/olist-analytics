"""Smoke test for the ML pipeline using SYNTHETIC data (no BigQuery needed).

This checks that the code runs and behaves sensibly, for example that the split is
time-ordered and that a model beats the baselines when the data really contains signal.
It says nothing about performance on the real Olist data.

Run:  python tests/test_ml_smoke.py     (or: pytest tests)
"""

import sys
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "ml"))
import train_late_delivery as ml  # noqa: E402


def make_synthetic(n: int = 6000, seed: int = 0) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    start = pd.Timestamp("2017-01-01", tz="UTC")
    ts = start + pd.to_timedelta(rng.integers(0, 600 * 24 * 3600, n), unit="s")
    distance = rng.gamma(2.0, 500.0, n)
    estimated_days = rng.integers(8, 40, n)
    weight = rng.gamma(2.0, 800.0, n)
    # Late probability rises with distance and falls with the delivery estimate: a real, learnable signal.
    logit = -2.6 + distance / 900 - (estimated_days - 20) / 8
    late = rng.random(n) < 1 / (1 + np.exp(-logit))
    df = pd.DataFrame(
        {
            "order_id": [f"o{i}" for i in range(n)],
            "order_purchase_timestamp": ts,
            "is_late": late.astype(int),
            "purchase_hour": rng.integers(0, 24, n),
            "purchase_dow": rng.integers(1, 8, n),
            "purchase_month_num": ts.month,
            "estimated_days": estimated_days,
            "customer_state": rng.choice(["SP", "RJ", "MG", "BA", "RS"], n),
            "max_distance_km": distance,
            "all_sellers_same_state": rng.random(n) < 0.3,
            "n_items": rng.integers(1, 4, n),
            "n_sellers": rng.integers(1, 3, n),
            "n_distinct_products": rng.integers(1, 4, n),
            "total_weight_g": weight,
            "max_item_volume_cm3": rng.gamma(2.0, 3000.0, n),
            "items_revenue": rng.gamma(2.0, 60.0, n),
            "freight_total": rng.gamma(2.0, 10.0, n),
            "max_installments": rng.integers(1, 10, n),
            "paid_with_credit_card": rng.random(n) < 0.75,
        }
    )
    df["freight_ratio"] = df["freight_total"] / df["items_revenue"]
    # Realistic messiness: some missing values and BigQuery-style nullable dtypes.
    df.loc[rng.random(n) < 0.02, "max_distance_km"] = np.nan
    df["all_sellers_same_state"] = df["all_sellers_same_state"].astype("boolean")
    df.loc[rng.random(n) < 0.01, "all_sellers_same_state"] = pd.NA
    df["n_items"] = df["n_items"].astype("Int64")
    return df


def test_time_split_has_no_overlap():
    data = ml.prepare(make_synthetic())
    train, test = ml.time_split(data)
    assert train[ml.TIME_COL].max() <= test[ml.TIME_COL].min(), "test period must come after training"
    assert len(train) + len(test) == len(data)
    assert abs(len(test) / len(data) - ml.TEST_FRACTION) < 0.01


def test_top_fraction_metrics_on_perfect_scores():
    y = np.array([1, 1, 0, 0, 0, 0, 0, 0, 0, 0])
    score = np.array([0.9, 0.8, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1])
    m = ml.top_fraction_metrics(y, score, fraction=0.2)
    assert m["precision"] == 1.0 and m["recall"] == 1.0
    assert abs(m["lift"] - 5.0) < 1e-9  # 100% precision / 20% base rate


def test_full_experiment_runs_and_model_beats_baselines():
    df = make_synthetic()
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        summary = ml.run_experiment(df, out_dir=out, n_cv_splits=3)

        for name in [
            "metrics.json",
            "model_comparison.csv",
            "decile_table.csv",
            "state_error_analysis.csv",
            "permutation_importance.csv",
            "pr_curves.png",
        ]:
            assert (out / name).exists(), f"missing output {name}"

        table = pd.DataFrame(summary["models"]).set_index("model")
        base = table.loc["baseline_prior"]
        assert abs(base["roc_auc"] - 0.5) < 1e-6, "prior baseline should have no ranking skill"
        assert table.loc["hist_gradient_boosting", "pr_auc"] > base["pr_auc"] + 0.05
        assert table.loc["logistic_regression", "roc_auc"] > 0.65

        # The synthetic signal comes from distance and estimated_days, so they should rank on top.
        importance = pd.read_csv(out / "permutation_importance.csv")
        assert set(importance["feature"].head(3)) & {"max_distance_km", "estimated_days"}

        deciles = pd.read_csv(out / "decile_table.csv")
        assert len(deciles) == 10
        assert deciles["actual_late_rate"].iloc[0] > deciles["actual_late_rate"].iloc[-1]


def test_missing_column_is_reported():
    df = make_synthetic().drop(columns=["max_distance_km"])
    try:
        ml.prepare(df)
    except ValueError as err:
        assert "max_distance_km" in str(err)
    else:
        raise AssertionError("expected a ValueError for the missing column")


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"PASS {name}")
