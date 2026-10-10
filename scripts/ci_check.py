"""
CI check script. Two modes, chosen automatically based on whether Kaggle
credentials are configured:

1. Full mode (KAGGLE_USERNAME + KAGGLE_KEY env vars present): downloads the
   real dataset via the Kaggle API, runs the full pipeline
   (src/build_tables.py), and asserts the three-layer table row counts
   match the known-correct values.

2. Degraded mode (no credentials): the 80MB raw CSV can't be fetched, so
   this can't run the real pipeline. It instead does what's actually
   possible without the data: verify every dependency imports cleanly,
   and verify every .py file in src/ is readable, non-empty UTF-8 text.
   This is weaker than a full run, but it still catches a broken
   environment or a corrupted file, which is worth having even without
   the dataset.

Usage: uv run python scripts/ci_check.py
"""
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent


def full_mode() -> None:
    import subprocess

    print("Kaggle credentials found -- running full mode.")
    subprocess.run(
        [
            "kaggle", "datasets", "download",
            "-d", "thedevastator/youtube-trending-videos-dataset",
            "-p", str(REPO_ROOT / "data"), "--unzip",
        ],
        check=True,
    )
    # The Kaggle download may name the file differently; normalize it.
    downloaded = list((REPO_ROOT / "data").glob("*.csv"))
    target = REPO_ROOT / "data" / "youtube.csv"
    if downloaded and not target.exists():
        downloaded[0].rename(target)

    result = subprocess.run(
        [sys.executable, str(REPO_ROOT / "src" / "build_tables.py")],
        cwd=REPO_ROOT, capture_output=True, text=True,
    )
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    import pandas as pd
    expected = {"clean.csv": 159_377, "video_life.csv": 63_783, "channel.csv": 12_253}
    for filename, expected_rows in expected.items():
        actual = len(pd.read_csv(REPO_ROOT / "data" / "exports" / filename))
        assert actual == expected_rows, f"{filename}: expected {expected_rows}, got {actual}"
        print(f"OK: {filename} has {actual} rows")
    print("Full mode PASSED.")


def degraded_mode() -> None:
    print("No Kaggle credentials found -- running degraded mode "
          "(dependency + file checks only, no data-dependent assertions).")

    required_modules = ["duckdb", "pandas", "numpy", "scipy", "statsmodels", "matplotlib", "seaborn"]
    for mod in required_modules:
        __import__(mod)
        print(f"OK: import {mod}")

    py_files = sorted((REPO_ROOT / "src").glob("*.py"))
    assert len(py_files) > 0, "No .py files found in src/"
    for f in py_files:
        text = f.read_text(encoding="utf-8")
        assert len(text.strip()) > 0, f"{f.name} is empty"
        print(f"OK: {f.name} is valid non-empty UTF-8 ({len(text)} chars)")

    print("Degraded mode PASSED (data-dependent assertions were skipped -- "
          "set KAGGLE_USERNAME and KAGGLE_KEY secrets to enable full mode).")


def main() -> None:
    if os.environ.get("KAGGLE_USERNAME") and os.environ.get("KAGGLE_KEY"):
        full_mode()
    else:
        degraded_mode()


if __name__ == "__main__":
    main()
