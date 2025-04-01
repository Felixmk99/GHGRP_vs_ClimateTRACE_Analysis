📊 Master Thesis: GHGRP vs. Climate TRACE Data Analysis

This repository contains the Jupyter Notebook and required scripts for analyzing discrepancies between GHGRP self-reported emissions data and Climate TRACE satellite-based emissions data. The analysis includes machine learning techniques, Bayesian modeling, and data preprocessing to ensure accuracy.

📢 Important: The dataset files are no longer included in this repository due to size constraints. You can download them from Zenodo (see below).

⸻

📂 Folder Structure

📦 GHGRP_vs_ClimateTRACE_Analysis  
 ┣ 📜 analysis.ipynb            # Main Jupyter Notebook  
 ┣ 📜 README.md                 # This file  
 ┣ 📜 requirements.txt          # Required Python libraries  



⸻

📥 Download the Dataset

Since the dataset files are too large for GitHub, they are hosted on Zenodo.

👉 Download the datasets here: [Zenodo DOI/URL]

After downloading, place all CSV files in a new data/ folder inside this repository:

GHGRP_vs_ClimateTRACE_Analysis/  
 ┣ 📂 data/  
 ┃ ┣ 📜 flight_2015.csv  
 ┃ ┣ 📜 flight_2016.csv  
 ┃ ┣ 📜 ... (more data files)  
 ┣ 📜 analysis.ipynb  
 ┣ 📜 README.md  
 ┗ 📜 requirements.txt  



⸻

🛠️ Setup Instructions

1️⃣ Clone the Repository

git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git  
cd YOUR_REPO  

2️⃣ Install Required Dependencies

Create a virtual environment (optional but recommended):

python3 -m venv venv  
source venv/bin/activate  # On Windows: venv\Scripts\activate  

Install required Python libraries:

pip install -r requirements.txt  

3️⃣ Place the Dataset in the data/ Folder

After downloading the dataset from Zenodo, extract and place all CSV files into the data/ folder.

4️⃣ Open Jupyter Notebook

jupyter notebook  

Then open analysis.ipynb and run the notebook.

⸻

📈 Data Sources
	1.	GHGRP (Greenhouse Gas Reporting Program)
	•	Self-reported emissions data from industrial facilities.
	•	Dataset: data/flight_YYYY.csv
	2.	Climate TRACE
	•	Satellite-based emissions tracking.
	•	Dataset: data/*_emissions_sources.csv
	3.	ZIP-COUNTY Mapping
	•	Used to map ZIP codes to county-level emissions.
	•	File: data/ZIP-COUNTY-FIPS_2017-06.csv
	4.	Ownership Data
	•	Maps facility names to parent companies.
	•	File: data/oil-and-gas-production-and-transport_emissions_sources_ownership.csv

⸻

📤 Uploading New Data to GitHub

Since large datasets should not be committed to GitHub, make sure to only upload scripts and notebooks. If you add new processed datasets that should be shared, upload them to Zenodo instead.

⸻

🧠 Key Features

✅ Automated Data Preprocessing (Cleaning, Merging, Normalization)
✅ Facility-Level Emissions Matching (Fuzzy Matching & Geolocation)
✅ Bayesian Hierarchical Modeling (Facility, Parent Company, Year)
✅ Custom Data Visualization (Emissions Trends & Uncertainty Plots)

⸻

📜 License

This project is licensed under the MIT License. Feel free to use, modify, and share it!

⸻

🤝 Contributing

Feel free to open a pull request or an issue if you have suggestions or improvements!

⸻

🚀 Next Steps
	•	Replace [Zenodo DOI/URL] with your actual Zenodo link.
	•	Add any missing information specific to your analysis.
	•	If needed, add a data download script (e.g., download_data.py) to automate dataset retrieval.

Let me know if you need any modifications! 😊

