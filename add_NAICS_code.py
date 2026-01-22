#!/usr/bin/env python3
"""add_naics_code.py – *deep‑sweep edition*

Step‑by‑step logic
==================
1. **Targeted lookup** Direct Emitters → five fallback groups (Onshore, G&B,
   Transmission, LDC, SF₆) – newest workbook first, first hit wins.
2. **Deep sweep** For any facility still lacking a NAICS, scan **every
   remaining worksheet** in every workbook (newest→oldest) until a code is
   found.
3. **Propagation** Copy each facility’s newest code back into earlier blank
   years.
4. **Validation** Ensure every `ghgrp_id` ends with ≤ 1 NAICS code; warn if any
   blanks remain.

Usage
~~~~~
Edit the three path constants and run:

```bash
python add_naics_code.py
```
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set

import pandas as pd

# ─────────────────────────────────────────────────────────────────────────────
CSV_PATH    = Path("~/Downloads/50m_matches_selected (1).csv").expanduser()
EXCEL_DIR   = Path("~/Downloads/2023_data_summary_spreadsheets").expanduser()
OUTPUT_PATH = Path("~/Downloads/50m_matches_selected_with_naics.csv").expanduser()
# ─────────────────────────────────────────────────────────────────────────────

PRIMARY_SHEET = "Direct Emitters"
HEADER_ROW    = 3

FALLBACK_KEYWORDS = [
    ["onshore"],
    ["gather", "boost"],
    ["transmission", "pipeline"],
    ["ldc"],
    ["sf6"],
]

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

def _clean(fid: str) -> str:
    return fid.strip() if isinstance(fid, str) else str(fid).strip()


def _try_parse(xl: pd.ExcelFile, sheet: str, header_row: int) -> Optional[pd.DataFrame]:
    """Try reading the two columns from *sheet* with a given header row."""
    try:
        df = xl.parse(
            sheet,
            header=header_row,
            usecols=["Facility Id", "Primary NAICS Code"],
            dtype={"Facility Id": str, "Primary NAICS Code": str},
        )
        return df
    except ValueError:
        return None


def _read_sheet(xl: pd.ExcelFile, sheet: str) -> Optional[pd.DataFrame]:
    """Return DF if sheet has the columns (header row 3 then 0), else None."""
    for hdr in (HEADER_ROW, 0):
        df = _try_parse(xl, sheet, hdr)
        if df is not None:
            df["Facility Id"] = df["Facility Id"].map(_clean)
            return (
                df.dropna(subset=["Facility Id"])
                  .drop_duplicates(subset=["Facility Id"])
                  .loc[:, ["Facility Id", "Primary NAICS Code"]]
            )
    return None


def _extract_targeted(workbook: Path) -> pd.DataFrame:
    """Direct Emitters + 5 fallback groups (deterministic priority)."""
    with pd.ExcelFile(workbook) as xl:
        seen: Set[str] = set()
        frames: List[pd.DataFrame] = []

        # primary
        if PRIMARY_SHEET in xl.sheet_names:
            df = _read_sheet(xl, PRIMARY_SHEET)
            if df is not None:
                frames.append(df)
                seen.update(df["Facility Id"].unique())

        # fallbacks
        for kw in FALLBACK_KEYWORDS:
            regex = re.compile("|".join(kw), re.I)
            sheet = next((s for s in xl.sheet_names if regex.search(s)), None)
            if sheet is None:
                continue
            fb = _read_sheet(xl, sheet)
            if fb is None:
                continue
            fb = fb[~fb["Facility Id"].isin(seen)]
            if not fb.empty:
                frames.append(fb)
                seen.update(fb["Facility Id"].unique())

        if not frames:
            return pd.DataFrame(columns=["Facility Id", "Primary NAICS Code"])
        return pd.concat(frames, ignore_index=True)


def _deep_sweep(workbook: Path, missing_ids: Set[str]) -> Dict[str, str]:
    """Scan ALL worksheets for Facility Ids in *missing_ids*."""
    found: Dict[str, str] = {}
    with pd.ExcelFile(workbook) as xl:
        for sheet in xl.sheet_names:
            if not missing_ids:  # everything found
                break
            df = _read_sheet(xl, sheet)
            if df is None or df.empty:
                continue
            df = df[df["Facility Id"].isin(missing_ids)]
            for fid, code in df.itertuples(index=False):
                if pd.notna(code):
                    found[fid] = code.strip()
                    missing_ids.discard(fid)
    return found

# ----------------------------------------------------------------------------
# Main routine
# ----------------------------------------------------------------------------

def extend_matches_with_naics(csv_path: Path, excel_dir: Path, output_path: Path) -> None:
    matches = pd.read_csv(csv_path, dtype={"ghgrp_id": str, "ghgrp_year": int})
    matches["ghgrp_id"] = matches["ghgrp_id"].map(_clean)

    if "NAICS Code" not in matches.columns:
        matches["NAICS Code"] = pd.NA

    naics_map: Dict[str, str] = {}
    missing_books: List[int] = []

    # ---------- targeted pass ------------------------------------------
    for year in sorted(matches["ghgrp_year"].unique(), reverse=True):
        wb = excel_dir / f"ghgp_data_{year}.xlsx"
        if not wb.exists():
            missing_books.append(year)
            continue
        df_lookup = _extract_targeted(wb)
        for fid, code in df_lookup.itertuples(index=False):
            if fid not in naics_map and pd.notna(code):
                naics_map[fid] = code.strip()

    # Identify missing IDs after targeted pass
    all_ids = set(matches["ghgrp_id"].unique())
    still_missing: Set[str] = {fid for fid in all_ids if fid not in naics_map}

    # ---------- deep sweep pass ----------------------------------------
    if still_missing:
        for year in sorted(matches["ghgrp_year"].unique(), reverse=True):
            wb = excel_dir / f"ghgp_data_{year}.xlsx"
            if not wb.exists() or not still_missing:
                continue
            deep_found = _deep_sweep(wb, still_missing)
            naics_map.update({fid: code for fid, code in deep_found.items() if fid not in naics_map})

    # ---------- assign + propagate -------------------------------------
    matches["NAICS Code"] = matches["ghgrp_id"].map(naics_map)

    matches = matches.sort_values(["ghgrp_id", "ghgrp_year"])  # ascending year
    latest_code = (
        matches.groupby("ghgrp_id")["NAICS Code"]
               .transform(lambda s: s.dropna().iloc[-1] if not s.dropna().empty else pd.NA)
    )
    matches["NAICS Code"] = matches["NAICS Code"].fillna(latest_code)

    # ---------- validation --------------------------------------------
    dup = matches.groupby("ghgrp_id")["NAICS Code"].nunique(dropna=True) > 1
    inconsistencies = dup[dup].index.tolist()
    if inconsistencies:
        print(f"❌  {len(inconsistencies)} facilities still show conflicting NAICS codes!", file=sys.stderr)
        matches[matches["ghgrp_id"].isin(inconsistencies)].to_csv(output_path.with_suffix("_naics_conflicts.csv"), index=False)
    else:
        print("✅  Consistency check passed – one NAICS per facility (after deep sweep).")

    n_missing = matches["NAICS Code"].isna().sum()
    if n_missing:
        print(f"⚠️  {n_missing} rows still lack a NAICS code even after deep sweep.", file=sys.stderr)

    if missing_books:
        print("⚠️  Workbooks missing for years:", ", ".join(map(str, missing_books)), file=sys.stderr)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    matches.to_csv(output_path, index=False)
    print(f"✅  Extended CSV saved → {output_path}")


if __name__ == "__main__":
    extend_matches_with_naics(CSV_PATH, EXCEL_DIR, OUTPUT_PATH)
