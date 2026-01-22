# R Package Requirements
# Install with: install.packages(c("package1", "package2", ...))

# Core data manipulation
install.packages(c("readr", "dplyr", "stringr", "tidyr"))

# Statistical modeling
install.packages(c("lme4", "lmerTest", "RLRsim"))

# Splines and advanced modeling
install.packages(c("splines", "MuMIn"))

# Model output and visualization
install.packages(c("broom.mixed", "stargazer"))

# Additional utilities
install.packages(c("jsonlite", "httr"))  # For robustness analysis (SEC data)

# Note: Some packages may require system dependencies
# On macOS: brew install gfortran (for lme4 compilation)
# On Linux: sudo apt-get install gfortran liblapack-dev

