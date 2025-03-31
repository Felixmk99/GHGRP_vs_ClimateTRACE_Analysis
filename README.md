# 📊 Master Thesis: GHGRP vs. Climate TRACE Data Analysis

This repository contains the Jupyter Notebook and datasets used for analyzing discrepancies between **GHGRP self-reported emissions data** and **Climate TRACE satellite-based emissions data**. The analysis includes **machine learning techniques, Bayesian modeling, and data preprocessing** to ensure accuracy.

---

## 📂 Folder Structure

```
📦 GHGRP_vs_ClimateTRACE_Analysis
 ┣ 📂 data                     # All datasets stored here
 ┃ ┣ 📜 flight_2015.csv        # GHGRP data for 2015
 ┃ ┣ 📜 flight_2016.csv        # GHGRP data for 2016
 ┃ ┣ 📜 ...                    # Additional GHGRP data
 ┃ ┣ 📜 ZIP-COUNTY-FIPS_2017-06.csv  # ZIP to County mapping file
 ┃ ┣ 📜 oil-and-gas-production-and-transport_emissions_sources_ownership.csv # Ownership mapping
 ┃ ┣ 📜 fuzzy_matches.pkl      # Cached fuzzy matching results
 ┃ ┣ 📜 bayesian_posterior_summary.csv # Bayesian model summary
 ┃ ┣ 📜 detailed_bayesian_summary.csv  # Detailed Bayesian summary
 ┃ ┗ 📜 *_emissions_sources.csv  # Climate TRACE emissions data
 ┣ 📜 analysis.ipynb            # Main Jupyter Notebook
 ┣ 📜 README.md                 # This file
 ┗ 📜 requirements.txt          # Required Python libraries
```

---

## 🛠️ Setup Instructions

### **1️⃣ Clone the Repository**

```sh
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
```

### **2️⃣ Install Required Dependencies**

Create a virtual environment (optional but recommended):

```sh
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

Install required Python libraries:

```sh
pip install -r requirements.txt
```

### **3️⃣ Open Jupyter Notebook**

```sh
jupyter notebook
```

Then open `analysis.ipynb` and run the notebook.

---

## 📈 Data Sources

1. **GHGRP (Greenhouse Gas Reporting Program)**  
   - Self-reported emissions data from industrial facilities.
   - Dataset: `data/flight_YYYY.csv`

2. **Climate TRACE**  
   - Satellite-based emissions tracking.
   - Dataset: `data/*_emissions_sources.csv`

3. **ZIP-COUNTY Mapping**  
   - Used to map ZIP codes to county-level emissions.
   - File: `data/ZIP-COUNTY-FIPS_2017-06.csv`

4. **Ownership Data**  
   - Maps facility names to parent companies.
   - File: `data/oil-and-gas-production-and-transport_emissions_sources_ownership.csv`

---

## 📤 Uploading New Data to GitHub

If you add new datasets, follow these steps:

```sh
# Ensure you're in the repository
cd YOUR_REPO

# Add the new file(s) to Git
git add data/

# Commit the changes
git commit -m "Added new emissions data for 2023"

# Push the changes to GitHub
git push origin main
```

---

## 🧠 Key Features

✅ **Automated Data Preprocessing** (Cleaning, Merging, Normalization)  
✅ **Facility-Level Emissions Matching** (Fuzzy Matching & Geolocation)  
✅ **Bayesian Hierarchical Modeling** (Facility, Parent Company, Year)  
✅ **Custom Data Visualization** (Emissions Trends & Uncertainty Plots)  

---

## 📜 License
This project is licensed under the [MIT License](LICENSE). Feel free to use, modify, and share it!

---

## 🤝 Contributing
Feel free to open a pull request or an issue if you have suggestions or improvements!

