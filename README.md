# Industrial Architecture, Not Corporate Governance, Drives the Divergence Between Compliance and Surveillance Carbon Accounting

**Authors:** Felix Kania, Siddharth Vedula, Markus Fitza, Kevin Gurney

**Institution:** Technical University of Munich, Miami University, Frankfurt School of Finance and Management, Northern Arizona University

**Status:** Working Paper (January 2026)

---

## Abstract



---

## Repository Structure

```
GHGRP_vs_ClimateTRACE_Analysis/
│
├── README.md                          # This file
├── LICENSE                            # License information
│
├── scripts/
│   ├── data_preparation/              # Data cleaning and integration scripts
│   │   ├── add_NAICS_code.py         # Adds NAICS codes from EPA spreadsheets
│   │   ├── extract_BLS_columns.py    # Extracts BLS labor data
│   │   ├── Add_COMPUSTAT_vars.py      # Adds Compustat financial variables
│   │   ├── integrating_BLS_and_CB.ipynb # Merges BLS and Census Bureau data
│   │   └── GHGRP_CT data matching.ipynb # Matches GHGRP and Climate TRACE data
│   │
│   └── analysis/                      # Main statistical analysis
│       ├── GHGRP_CT_HLM_main_analysis.r  # Primary HLM analysis (magnitude & signed models)
│       └── robustness_analysis_public_firms.ipynb # Robustness check: public firms only
│
├── notebooks/                         # Visualization and exploratory analysis
│   └── Create visual for paper.ipynb # Generates Figure 1 (Hierarchy of Uncertainty)
│
├── data/                             # Data files (not included in repository)
│   └── [Data files should be placed here]
│
└── figures/                          # Generated figures (created during analysis)
    └── [Figures will be saved here]
```

---

## Data Sources

### Primary Data
1. **EPA Greenhouse Gas Reporting Program (GHGRP)**
   - Source: U.S. Environmental Protection Agency
   - Coverage: Facilities emitting >25,000 metric tons CO2e/year
   - Period: 2015-2023
   - Variables: Facility emissions, parent company, county, NAICS codes

2. **Climate TRACE (CT)**
   - Source: Climate TRACE inventory
   - Method: Satellite remote sensing + AI modeling
   - Coverage: Contiguous United States (~363,000 observations)
   - Variables: Asset-level emission estimates

### Supplementary Data
3. **Compustat North America Fundamentals Annual**
   - Source: S&P Global Market Intelligence
   - Variables: Total assets, R&D intensity, ROA, leverage
   - Aggregation: Industry-year means (3-digit NAICS)

4. **U.S. Bureau of Labor Statistics (BLS) Quarterly Census of Employment and Wages (QCEW)**
   - Variables: Industry employment, average annual wages
   - Aggregation: 3-digit NAICS, national level

5. **U.S. Economic Census**
   - Variables: Herfindahl-Hirschman Index (HHI) for market concentration
   - Years: 2017, 2022 (interpolated for other years)

---

## Analysis Workflow

### Step 1: Data Preparation

1. **Match GHGRP and Climate TRACE data** (`scripts/data_preparation/GHGRP_CT data matching.ipynb`)
   - Geospatial matching of facilities
   - Annual aggregation of monthly CT data
   - Calculation of emission discrepancies

2. **Add NAICS codes** (`scripts/data_preparation/add_NAICS_code.py`)
   - Extracts NAICS codes from EPA summary spreadsheets
   - Handles multiple facility types (Direct Emitters, Onshore, etc.)
   - Validates consistency across years

3. **Extract BLS data** (`scripts/data_preparation/extract_BLS_columns.py`)
   - Filters QCEW data for national, private-sector, 3-digit NAICS
   - Creates lean CSV files for each year

4. **Add Compustat variables** (`scripts/data_preparation/Add_COMPUSTAT_vars.py`)
   - Aggregates firm-level financial data to industry-year means
   - Creates Z-score normalized variables
   - Handles missing data via mean imputation

5. **Integrate BLS and Census data** (`scripts/data_preparation/integrating_BLS_and_CB.ipynb`)
   - Merges BLS labor data (wages, employment)
   - Adds Census HHI concentration measures
   - Final dataset: `ghgrp_CT_data_final_with_BLS_CS.csv`

### Step 2: Main Analysis

**Primary HLM Model** (`scripts/analysis/GHGRP_CT_HLM_main_analysis.r`)

The main analysis employs Hierarchical Linear Modeling to decompose variance in emission discrepancies across multiple levels:

- **Dependent Variable:** Log-transformed relative error magnitude: `log1p(|discrepancy| / emissions)`
- **Random Effects:**
  - Facility level (`ghgrp_id`)
  - Parent company (`ghgrp_parent_companies`)
  - County (`ghgrp_county_name`)
  - Industry sector (`NAICS3`)
- **Fixed Effects:**
  - Natural spline of facility size (3 df)
  - Year fixed effects
  - Industry covariates (ROA, leverage, R&D intensity, capital intensity)

**Key Outputs:**
- Variance component decomposition
- Industry-level BLUPs (Best Linear Unbiased Predictors)
- Parent-company BLUPs with FDR correction
- Signed discrepancy model (directional bias)
- Between vs. within industry decomposition

**Robustness Analysis** (`scripts/analysis/robustness_analysis_public_firms.ipynb`)

Re-estimates the main HLM model on a subset of publicly traded firms only (N=9,494) to test whether results are driven by differences between public and private firm reporting requirements.

### Step 3: Visualization

**Figure 1: Hierarchy of Uncertainty** (`notebooks/Create visual for paper.ipynb`)

Creates the main figure ranking industries by median relative discrepancy, visualizing:
- Sectoral precision differences
- Fugitive vs. combustion emission patterns
- Systematic over- vs. under-reporting biases

---

## Software Requirements

### R Packages
- `lme4` (v1.1-35+): Hierarchical linear models
- `lmerTest` (v3.1-3+): Statistical tests for mixed models
- `RLRsim`: Exact restricted likelihood ratio tests
- `splines`: Natural splines for size effects
- `readr`, `dplyr`, `stringr`: Data manipulation
- `MuMIn`: Model fit statistics (R²)
- `broom.mixed`: Tidy model outputs

### Python Packages
- `pandas` (v1.5+): Data manipulation
- `numpy` (v1.23+): Numerical operations
- `matplotlib` (v3.6+): Plotting
- `seaborn` (v0.12+): Statistical visualization

### Data Files Required

**Note:** Due to size and licensing restrictions, raw data files are not included in this repository. Users must obtain:

1. GHGRP facility data from EPA
2. Climate TRACE data from Climate TRACE
3. Compustat data (requires subscription)
4. BLS QCEW annual files
5. U.S. Economic Census concentration data

Place all data files in the `data/` directory before running scripts.

---

## Replication Instructions

### Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Felixmk99/GHGRP_vs_ClimateTRACE_Analysis.git
   cd GHGRP_vs_ClimateTRACE_Analysis
   ```

2. **Install R packages:**
   ```r
   install.packages(c("lme4", "lmerTest", "RLRsim", "splines", 
                      "readr", "dplyr", "stringr", "MuMIn", "broom.mixed"))
   ```

3. **Install Python packages:**
   ```bash
   pip install pandas numpy matplotlib seaborn
   ```

4. **Prepare data files:**
   - Place all required data files in `data/` directory
   - Update file paths in scripts if necessary

5. **Run analysis in order:**
   ```bash
   # Step 1: Data preparation
   python scripts/data_preparation/add_NAICS_code.py
   python scripts/data_preparation/extract_BLS_columns.py
   python scripts/data_preparation/Add_COMPUSTAT_vars.py
   
   # Step 2: Main analysis
   Rscript scripts/analysis/GHGRP_CT_HLM_main_analysis.r
   
   # Step 3: Visualization
   jupyter notebook notebooks/Create\ visual\ for\ paper.ipynb
   ```

### Detailed Workflow

See the "Analysis Workflow" section above for step-by-step instructions.

---

## Key Results

### Variance Decomposition

The HLM analysis reveals that:
- **Industry (NAICS3) variance:** ~59% of total variance
- **Facility-level variance:** ~28% of total variance
- **Parent company variance:** ~4% of total variance
- **County variance:** ~2% of total variance
- **Residual variance:** ~9% of total variance

### Industry Effects

- **Systematic under-reporters:** Transportation support (NAICS 488), Pipeline transportation (486), Oil & gas extraction (211)
- **Systematic over-reporters:** Wood product manufacturing (321), Textile mills (313)
- **High noise, low bias:** Warehousing & storage (493)

### Corporate Effects

After False Discovery Rate (FDR) correction:
- **Zero parent companies** show statistically significant directional bias (q < 0.05)
- This confirms that reporting discrepancies are sector-level phenomena, not firm-level "bad apples"

---

## Citation

If you use this code or data in your research, please cite:

```bibtex
@unpublished{Kania2026,
  title={Industrial architecture, not corporate governance, drives the divergence between compliance and surveillance carbon accounting},
  author={Kania, Felix and Vedula, Siddharth and Fitza, Markus and Gurney, Kevin},
  year={2026},
  note={Working Paper}
}
```

---

## License

See `LICENSE` file for details.

---

## Contact

For questions about the code or analysis, please contact: **Felix Kania:** felixkania@gmail.com

---


## Notes for Reviewers

This repository contains all code necessary to replicate the analysis presented in the paper. Due to data licensing restrictions, raw data files are not included. However, all data preparation steps are documented, and intermediate datasets can be generated by following the workflow above.

**Key files for reviewers:**
- Main analysis: `scripts/analysis/GHGRP_CT_HLM_main_analysis.r`
- Robustness check: `scripts/analysis/robustness_analysis_public_firms.ipynb`
- Main figure: `notebooks/Create visual for paper.ipynb`

All scripts include detailed comments and follow best practices for reproducibility.
