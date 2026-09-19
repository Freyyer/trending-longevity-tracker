"""
Builds the three-layer metrics stack (clean -> video_life -> channel) by
running the SQL scripts in sql/ in order, then exports each table to
data/exports/*.csv for downstream use (pandas reconciliation, dashboard,
hypothesis testing).

Usage:
    uv run python src/build_tables.py
"""
import re
from pathlib import Path

import duckdb

SQL_DIR = Path(__file__).parent.parent / "sql"
EXPORT_DIR = Path(__file__).parent.parent / "data" / "exports"


def strip_comments(sql_text: str) -> str:
    lines = []
    for line in sql_text.split("\n"):
        if line.strip().startswith("--"):
            continue
        idx = line.find("--")
        if idx >= 0:
            line = line[:idx]
        lines.append(line)
    return "\n".join(lines)


def run_sql_file(con: duckdb.DuckDBPyConnection, path: Path) -> None:
    print(f"--- Running {path.name} ---")
    sql_text = strip_comments(path.read_text())
    statements = [s.strip() for s in sql_text.split(";") if s.strip()]
    for stmt in statements:
        result = con.execute(stmt)
        if stmt.upper().lstrip().startswith("SELECT"):
            print(result.fetchdf())


def load_clean(con: duckdb.DuckDBPyConnection) -> None:
    """sql/01-clean.sql reads from ../data/youtube.csv (relative to sql/),
    but this script runs from the repo root, so we substitute the path."""
    sql_text = strip_comments((SQL_DIR / "01-clean.sql").read_text())
    sql_text = sql_text.replace("../data/youtube.csv", "data/youtube.csv")
    statements = [s.strip() for s in sql_text.split(";") if s.strip()]
    print("--- Running 01-clean.sql ---")
    for stmt in statements:
        result = con.execute(stmt)
        if stmt.upper().lstrip().startswith("SELECT"):
            print(result.fetchdf())


def main() -> None:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()

    load_clean(con)
    run_sql_file(con, SQL_DIR / "02-video-life.sql")
    run_sql_file(con, SQL_DIR / "03-channel.sql")

    for table, filename in [
        ("clean", "clean.csv"),
        ("video_life", "video_life.csv"),
        ("channel", "channel.csv"),
    ]:
        out_path = EXPORT_DIR / filename
        con.execute(f"COPY {table} TO '{out_path}' (HEADER, DELIMITER ',')")
        n_rows = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"Exported {table} -> {out_path} ({n_rows} rows)")


if __name__ == "__main__":
    main()
