#!/usr/bin/env python3
"""
Add_COMPUSTAT_vars.py

Purpose:
--------
Adds industry-level financial variables from Compustat to the GHGRP dataset.
Aggregates firm-level financial metrics (ROA, leverage, R&D intensity, capital intensity)
to 3-digit NAICS industry-year means, then merges with facility-level data.

Input:
------
- SAS file: Compustat North America Fundamentals Annual database (SAS format)
- GHGRP CSV: Facility-level dataset with NAICS codes

Output:
-------
- Model-ready CSV with industry financial covariates (Z-score normalized)

Key Variables Created:
----------------------
- ind_ROA_z: Industry return on assets (Z-score)
- ind_Leverage_z: Industry leverage ratio (Z-score)
- ind_RD_intensity_z: Industry R&D intensity (Z-score)
- ind_at_z: Industry capital intensity (log total assets, Z-score)

Usage:
------
1. Update paths at top of script (SAS_PATH, GHGRP_CSV, OUT_CSV)
2. Run: python Add_COMPUSTAT_vars.py

Note: Handles missing data via mean imputation and creates Z-score normalized
variables for use in hierarchical linear models.
"""

import pandas as pd
import numpy as np
import os

# ====== Paths ======
SAS_PATH  = "/Users/felixkania/Desktop/Publication project/alzta3tvdvdfo1oe.sas7bdat"
GHGRP_CSV = "/Users/felixkania/Desktop/Publication project/ghgrp_ct_50m_with_naics.csv"
OUT_CSV   = "/Users/felixkania/Desktop/Publication project/ghgrp_with_industry_vars_MODEL.csv"

YEARS_MIN, YEARS_MAX = 2015, 2023

# ====== Load SAS firm file ======
df = pd.read_sas(SAS_PATH, format="sas7bdat", encoding="latin1")
print(f"[SAS] Loaded {len(df):,} rows, {df.shape[1]} columns")

# ----- Key SAS columns -----
col_year   = "fyear"   # fiscal year (int)
col_naics  = "naics"   # NAICS (2-6 digits)
col_assets = "at"      # total assets
col_equity = "ceq"     # common equity
col_sales  = "sale"    # net sales
col_revt   = "revt"    # revenue (fallback for sales)
col_income = "ni"      # net income

# ----- Clean keys & restrict to 2015–2023 & valid 3-digit NAICS -----
df[col_year] = pd.to_numeric(df[col_year], errors="coerce").astype("Int64")
naics_digits = df[col_naics].astype(str).str.extract(r"(\d{2,6})")[0]
df["NAICS3"] = naics_digits.str.slice(0, 3)
df = df[(df[col_year] >= YEARS_MIN) & (df[col_year] <= YEARS_MAX)]
df = df[df["NAICS3"].str.len() == 3].copy()
print(f"[SAS] After filtering: {len(df):,} rows")

# ----- Helpers -----
def safe_div(a, b):
    a = pd.to_numeric(a, errors="coerce")
    b = pd.to_numeric(b, errors="coerce")
    return np.where((b == 0) | pd.isna(b), np.nan, a / b)

# ----- Compute firm-level ratios -----
df["ROA"] = safe_div(df[col_income], df[col_assets])
df["ROS"] = safe_div(df[col_income], df[col_sales]) if col_sales in df.columns else safe_div(df[col_income], df.get(col_revt, np.nan))
df["ROE"] = safe_div(df[col_income], df[col_equity])
if "xrd" in df.columns:
    sales_for_rd = df[col_sales] if col_sales in df.columns else df.get(col_revt, np.nan)
    df["RD_intensity"] = safe_div(df["xrd"], sales_for_rd)
if "lt" in df.columns:
    df["Leverage"] = safe_div(df["lt"], df[col_assets])

# ----- Select numeric columns to average (exclude IDs / grouping cols) -----
numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
drop_cols = {"gvkey", "sic", col_year}  # don't average year or firm IDs
numeric_cols = [c for c in numeric_cols if c not in drop_cols]

# ----- Aggregate to industry-year means -----
agg = (
    df.dropna(subset=["NAICS3", col_year])
      .groupby(["NAICS3", col_year], observed=True)[numeric_cols]
      .mean()
      .reset_index()
      .rename(columns={col_year: "year"})
)
feature_map = {c: f"ind_{c}" for c in numeric_cols if c not in ["NAICS3", "year"]}
agg = agg.rename(columns=feature_map)

# ====== Load GHGRP CSV ======
ghgrp_path = GHGRP_CSV if os.path.exists(GHGRP_CSV) else (GHGRP_CSV + ".csv" if os.path.exists(GHGRP_CSV + ".csv") else GHGRP_CSV)
ghgrp = pd.read_csv(ghgrp_path)
print(f"[GHGRP] Loaded {len(ghgrp):,} rows")

# Keep only 2015–2023 (defensive)
ghgrp = ghgrp[(ghgrp["ghgrp_year"] >= YEARS_MIN) & (ghgrp["ghgrp_year"] <= YEARS_MAX)].copy()

# Derive NAICS3 and enforce 3-digit length
ghgrp["NAICS3"] = ghgrp["NAICS Code"].astype(str).str.extract(r"(\d{2,6})")[0].str.slice(0, 3)
ghgrp = ghgrp[ghgrp["NAICS3"].str.len() == 3].copy()

# ====== Merge industry-year features ======
merged = ghgrp.merge(agg, how="left", left_on=["NAICS3", "ghgrp_year"], right_on=["NAICS3", "year"])
if "year" in merged.columns:
    merged.drop(columns=["year"], inplace=True)

# ----- Handle missing values in industry features (mean impute) -----
ind_cols = [c for c in merged.columns if c.startswith("ind_")]
for c in ind_cols:
    m = merged[c].mean(skipna=True)
    merged[c] = merged[c].fillna(m)

# ----- Z-score scaling for model-ready features -----
z_cols = []
for c in ind_cols:
    mu = merged[c].mean()
    sd = merged[c].std(ddof=0)
    zc = c + "_z"
    merged[zc] = (merged[c] - mu) / (sd if (sd and np.isfinite(sd) and sd > 0) else 1.0)
    z_cols.append(zc)

# ====== QUALITY CHECKS on z-features ======
def find_bad_columns(frame, cols):
    all_nan = [c for c in cols if frame[c].isna().all()]
    # "all zero" = all non-nan values equal to 0
    all_zero = [c for c in cols if frame[c].dropna().eq(0).all() and not frame[c].isna().all()]
    # "constant" = std == 0
    const = [c for c in cols if np.isfinite(frame[c].std(ddof=0)) and frame[c].std(ddof=0) == 0]
    # union, keeping categories separate for logging
    return all_nan, all_zero, const

all_nan, all_zero, const = find_bad_columns(merged, z_cols)
bad_any = sorted(set(all_nan) | set(all_zero) | set(const))
if all_nan: print(f"[WARN] All-NaN z-features: {all_nan}")
if all_zero: print(f"[WARN] All-zero z-features: {all_zero}")
if const: print(f"[WARN] Constant z-features: {const}")

# Drop bad columns from consideration
z_cols = [c for c in z_cols if c not in bad_any]

# ----- Collinearity filter (among CANDIDATE features, priority order) -----
# Choose a parsimonious, interpretable set (priority order left→right)
CANDIDATES = [
    "ind_ROA_z",
    "ind_Leverage_z",
    "ind_RD_intensity_z",
    "ind_at_z",
    # optional extras (commented out by default):
    "ind_act_z", "ind_xrd_z", "ind_irent_z"
]

# Keep only candidates that exist AND survived quality checks
cand_present = [c for c in CANDIDATES if c in z_cols]
if not cand_present:
    print("[WARN] None of the candidate features are available after checks. Falling back to any remaining z-cols.")
    cand_present = z_cols[:]  # fallback: use whatever good features remain

# Correlation-based pruning with priority:
keep = []
drop_due_corr = []
if len(cand_present) > 1:
    corr = merged[cand_present].corr().abs()
    for c in cand_present:
        if any((c in corr.columns and k in corr.columns and corr.loc[c, k] >= 0.95) for k in keep):
            drop_due_corr.append(c)
        else:
            keep.append(c)
else:
    keep = cand_present[:]

if drop_due_corr:
    print(f"[INFO] Dropping (corr ≥ 0.95 among candidates): {drop_due_corr}")

FINAL_FEATS = keep
print(f"[MODEL] Final features: {FINAL_FEATS}")

# ====== Build compact, model-ready CSV ======
# Keep only GHGRP keys needed downstream + selected z-features
GHGRP_KEEP = [
    "ghgrp_year",
    "ghgrp_id",
    "ghgrp_county_name",
    "ghgrp_parent_companies",
    "ghgrp_emissions_tons",
    "emissions_discrepancy",
    "NAICS Code",
    "NAICS3",
]
present_keys = [c for c in GHGRP_KEEP if c in merged.columns]
model_df = merged[present_keys + FINAL_FEATS].copy()

# Final safety checks: drop any residual all-NaN columns
nan_only = [c for c in model_df.columns if model_df[c].isna().all()]
if nan_only:
    print(f"[WARN] Dropping columns that are entirely NaN in final output: {nan_only}")
    model_df.drop(columns=nan_only, inplace=True)

# ====== Save final CSV (only model-needed columns) ======
model_df.to_csv(OUT_CSV, index=False)
print(f"[OK] Wrote model-ready CSV → {OUT_CSV}")
print(f"[SHAPE] {model_df.shape[0]:,} rows × {model_df.shape[1]} cols")
