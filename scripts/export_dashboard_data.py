"""Run every query marked `-- @export: name` in sql/1x_analysis_*.sql and save it as a CSV.

The CSVs go to dashboard/data/ and feed the Streamlit dashboard (and Power BI or Looker
Studio, if you prefer those). The SQL files stay the single source of truth: the dashboard
never contains its own copy of a query.

A query starts at its marker line and ends at the first semicolon, which is why comments
inside exported queries must not contain semicolons.

Run:  python scripts/export_dashboard_data.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
OUT_DIR = ROOT / "dashboard" / "data"
PROJECT = "olist-analytics-510317"

MARKER = re.compile(r"^--\s*@export:\s*(\w+)\s*$\n(.*?);", re.DOTALL | re.MULTILINE)


def find_exports(sql_dir: Path = SQL_DIR) -> list[tuple[str, str, str]]:
    """Return (file name, export name, query text) for every marked query."""
    found = []
    for path in sorted(sql_dir.glob("*_analysis_*.sql")):
        for match in MARKER.finditer(path.read_text()):
            found.append((path.name, match.group(1), match.group(2).strip()))
    names = [name for _, name, _ in found]
    duplicates = {n for n in names if names.count(n) > 1}
    if duplicates:
        raise ValueError(f"Duplicate export names: {sorted(duplicates)}")
    return found


def main() -> int:
    from google.cloud import bigquery

    exports = find_exports()
    if not exports:
        print("No '-- @export:' queries found.")
        return 1

    client = bigquery.Client(project=PROJECT)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for file_name, name, query in exports:
        print(f"{file_name} -> {name}.csv ...", end=" ", flush=True)
        df = client.query(query).to_dataframe()
        df.to_csv(OUT_DIR / f"{name}.csv", index=False)
        print(f"{len(df):,} rows")

    print(f"Wrote {len(exports)} files to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
