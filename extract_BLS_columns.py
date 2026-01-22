import pandas as pd
import glob
import os

# --- FIX: Set Working Directory to Script's Location ---
try:
    # This forces the script to look in the folder where you saved it
    script_path = os.path.abspath(__file__)
    script_dir = os.path.dirname(script_path)
    os.chdir(script_dir)
except NameError:
    # Fallback if running inside a notebook/interactive shell
    script_dir = os.getcwd()

print(f"📂 Looking for files in: {script_dir}")

# --- 1. Find Files ---
# Pattern matches "2023.annual.singlefile.csv", "2015.annual.singlefile.csv", etc.
file_pattern = "*annual.singlefile.csv"
files = glob.glob(file_pattern)

if not files:
    print("\n❌ NO FILES FOUND.")
    print(f"   I searched for: {file_pattern}")
    print("   Files currently in this folder:")
    # Print first 5 CSVs found to help debug
    csvs = glob.glob("*.csv")
    for f in csvs[:5]:
        print(f"    - {f}")
    if not csvs:
        print("    (No .csv files found at all)")
    exit()

print(f"\n✅ Found {len(files)} files. Starting processing...\n")

# --- 2. Define Columns to Keep ---
cols_to_keep = [
    'area_fips',          # Filter for 'US000'
    'own_code',           # Filter for '5'
    'industry_code',      # Match NAICS
    'year',               # Match Year
    'annual_avg_emplvl',  # Variable: Total Jobs
    'avg_annual_pay'      # Variable: Avg Wage
]

# --- 3. Process Files ---
for filename in files:
    try:
        print(f"Processing {filename}...", end=" ", flush=True)
        
        # Read only necessary columns (Force strings for codes to keep leading zeros)
        df = pd.read_csv(filename, usecols=cols_to_keep, 
                         dtype={'area_fips': str, 'own_code': str, 'industry_code': str})
        
        # Filter: National (US000) + Private (5) + NAICS-3 (Length 3)
        df_lean = df[
            (df['area_fips'] == 'US000') & 
            (df['own_code'] == '5') & 
            (df['industry_code'].str.len() == 3)
        ]
        
        if df_lean.empty:
            print("⚠️ Result empty (Check filters). Skipping save.")
            continue

        # Save "Lean" version
        new_filename = filename.replace(".csv", "_lean.csv")
        df_lean.to_csv(new_filename, index=False)
        
        print(f"✅ Saved ({len(df_lean)} rows)")

    except Exception as e:
        print(f"\n   ❌ Error: {e}")

print("\n🎉 Done!")