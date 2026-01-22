# ============================================================
# HLM for GHGRP discrepancies — lean, robust, publication-ready
# - Keep ALL REs: facility + parent + county + NAICS3 (no dropping)
# - MIN_IDS_* = 5 (distinct facilities) for stable REs
# - Relative DV winsorized before log1p, then centered & scaled
# - Natural spline for size (ns), df=3, *orthonormalized* basis
# - Stepwise seeding: RE-only -> +size -> +year FE -> +industry FE
# - Multi-optimizer sweep (bobyqa / nloptwrap / nlminbwrap / Nelder_Mead)
# - Robust candidate ranking; seed is always included and safe fallback
# - Optional final polish via optimizeLmer()
# - FE CIs (Wald), random-only shares, convergence verdict
# - ***NEW*** (1) Industry breakdowns; (2) Owner RLRT + owner BLUPs+FDR
#              (3) Signed-discrepancy model; (4) Between vs within decomposition
#              (TIGHTEN) Owner ML-LRT fallback + pre-scale signed DV stats
#              (TIGHTEN++) Owner directional (signed) ML-LRT + signed BLUPs+FDR
# ============================================================

# ----- Lean installs (binary-only) -----
options(repos = c(CRAN = "https://cloud.r-project.org"))
need <- c("readr","dplyr","stringr","splines","lme4","lmerTest","RLRsim")
to_install <- setdiff(need, rownames(installed.packages()))
if (length(to_install)) {
  install.packages(to_install, dependencies = c("Depends","Imports"), type = "binary")
}
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(stringr)
  library(splines); library(lme4); library(lmerTest); library(RLRsim)
})

# Sum-to-zero contrasts for fixed factors (year)
options(contrasts = c("contr.sum", "contr.poly"))

# ------------------ Config ------------------
CSV_PATH         <- "ghgrp_CT_data.csv"
DV_RELATIVE      <- TRUE
REL_WINSOR_P     <- 99.5
ABS_WINSOR_P     <- NA
SIZE_SPLINE_DF   <- 3
GRAD_TOL         <- 0.003
PROFILE_RE_CI    <- FALSE

# Fold thresholds by DISTINCT FACILITIES
MIN_IDS_PARENT   <- 5
MIN_IDS_COUNTY   <- 5
MIN_IDS_NAICS3   <- 5

# ------------------ Helpers ------------------
winsor_vec <- function(x, p=99) {
  if (is.na(p)) return(x)
  lo <- as.numeric(quantile(x, probs = 1 - p/100, type = 7, na.rm = TRUE))
  hi <- as.numeric(quantile(x, probs = p/100,     type = 7, na.rm = TRUE))
  pmin(pmax(x, lo), hi)
}
fold_by_ids <- function(group_vec, id_vec, min_ids = 5, other = "Other") {
  tab <- tapply(id_vec, group_vec, function(z) length(unique(z)))
  tab <- tab[!is.na(names(tab))]
  keep <- names(tab)[tab >= min_ids]
  out <- as.character(group_vec)
  out[!(out %in% keep)] <- other
  factor(out)
}
nakagawa_r2 <- function(mod) {
  X <- lme4::getME(mod, "X")
  beta <- lme4::fixef(mod)
  mu_fe <- as.vector(X %*% beta)
  var_fe <- stats::var(mu_fe, na.rm = TRUE)
  vc <- as.data.frame(lme4::VarCorr(mod))
  var_resid <- sum(vc$vcov[vc$grp == "Residual"])
  var_rand  <- sum(vc$vcov[vc$grp != "Residual"])
  var_tot <- var_fe + var_rand + var_resid
  data.frame(R2_marginal = var_fe/var_tot,
             R2_conditional = (var_fe+var_rand)/var_tot)
}
lr_from_logLik <- function(m0, m1, label) {
  ll0 <- as.numeric(logLik(m0)); df0 <- attr(logLik(m0), "df")
  ll1 <- as.numeric(logLik(m1)); df1 <- attr(logLik(m1), "df")
  chisq <- 2*(ll1 - ll0); df <- df1 - df0
  p <- if (is.finite(chisq) && df > 0) pchisq(chisq, df = df, lower.tail = FALSE) else NA_real_
  data.frame(block = label, Chisq = chisq, df = df, p = p)
}
ginfo <- function(m) {
  grad <- tryCatch({
    gg <- m@optinfo$derivs$gradient
    if (is.null(gg) || length(gg) == 0) NA_real_ else max(abs(gg))
  }, error=function(e) NA_real_)
  code <- tryCatch({
    cc <- m@optinfo$conv$lme4$code
    if (is.null(cc) || length(cc) == 0) NA_integer_ else cc
  }, error=function(e) NA_integer_)
  aic  <- tryCatch({
    aa <- AIC(m); if (length(aa) == 0) NA_real_ else as.numeric(aa)
  }, error=function(e) NA_real_)
  list(grad = grad, code = code, sing = lme4::isSingular(m, tol = 1e-4), aic = aic)
}
log_header <- function(m, tag, y_mean, y_sd) {
  gi <- ginfo(m)
  cat("\n", strrep("=", 78), "\n", sep = "")
  cat(sprintf("HLM — %s FIT (lme4)\n", tag))
  cat(sprintf("REML=%s; n=%s | logLik=%.1f | AIC=%.1f | Singular: %s | max|grad|≈%s | code=%s\n",
              ifelse(isTRUE(lme4::isREML(m)), "yes", "no"),
              format(nobs(m), big.mark=","), as.numeric(logLik(m)), AIC(m),
              gi$sing,
              ifelse(is.na(gi$grad), "NA", sprintf("%.3g", gi$grad)),
              ifelse(is.na(gi$code), "NA", as.character(gi$code))))
  cat(sprintf("DV centering/scaling: y = (raw - %.4f) / %.4f\n", y_mean, y_sd))
  invisible(gi)
}
blup_table <- function(mod, grp) {
  re_list <- ranef(mod, condVar = TRUE)
  RE <- re_list[[grp]]
  pv <- attr(RE, "postVar")
  eff <- as.numeric(RE[, "(Intercept)"])
  nm  <- rownames(RE)
  se <- if (length(dim(pv)) == 3 && dim(pv)[1]==1) {
    sqrt(sapply(seq_len(dim(pv)[3]), function(i) pv[1,1,i]))
  } else {
    rep(NA_real_, length(eff))
  }
  z  <- eff / se
  p  <- 2 * pnorm(-abs(z))
  padj <- p.adjust(p, method = "BH")
  data.frame(level = nm, effect = eff, se = se,
             lwr = eff - 1.96*se, upr = eff + 1.96*se,
             z = z, p = p, p_adj_BH = padj,
             row.names = NULL, check.names = FALSE)
}
get_var_component <- function(mod, grp) {
  vc <- as.data.frame(VarCorr(mod))
  sum(vc$vcov[vc$grp == grp])
}

# ------------------ Load & basic checks ------------------
df <- suppressMessages(readr::read_csv(CSV_PATH, show_col_types = FALSE))

req <- c("ghgrp_year","ghgrp_id","ghgrp_parent_companies","ghgrp_county_name",
         "ghgrp_emissions_tons","NAICS3","emissions_discrepancy",
         "ind_ROA_z","ind_Leverage_z","ind_RD_intensity_z","ind_at_z")
stopifnot(all(req %in% names(df)))
df <- df[stats::complete.cases(df[, req]), , drop = FALSE]

dup_n <- df |>
  dplyr::count(ghgrp_id, ghgrp_year, name = "n") |>
  dplyr::filter(n > 1) |>
  nrow()
stopifnot(dup_n == 0)

# ------------------ Fold by DISTINCT facilities ------------------
df <- df |>
  mutate(
    parent_folded = fold_by_ids(ghgrp_parent_companies, ghgrp_id, min_ids = MIN_IDS_PARENT),
    county_folded = fold_by_ids(ghgrp_county_name,      ghgrp_id, min_ids = MIN_IDS_COUNTY),
    naics3_folded = fold_by_ids(NAICS3,                 ghgrp_id, min_ids = MIN_IDS_NAICS3)
  )

post_fold <- df |>
  summarise(
    n_parent  = n_distinct(parent_folded),
    n_county  = n_distinct(county_folded),
    n_naics3  = n_distinct(naics3_folded),
    share_other_naics3 = mean(naics3_folded == "Other")
  )
cat("\n[Post-fold summary]\n"); print(post_fold)

# ------------------ Size & industry covariates ------------------
df <- df |>
  mutate(
    log1p_size = log1p(as.numeric(ghgrp_emissions_tons)),
    z_size     = as.numeric(scale(log1p_size)),
    ind_ROA_z          = ifelse(is.na(ind_ROA_z),          0, ind_ROA_z),
    ind_Leverage_z     = ifelse(is.na(ind_Leverage_z),     0, ind_Leverage_z),
    ind_RD_intensity_z = ifelse(is.na(ind_RD_intensity_z), 0, ind_RD_intensity_z),
    ind_at_z           = ifelse(is.na(ind_at_z),           0, ind_at_z)
  )

# ------------------ DV (magnitude model) ------------------
if (DV_RELATIVE) {
  ratio_mag <- abs(as.numeric(df$emissions_discrepancy)) / pmax(as.numeric(df$ghgrp_emissions_tons), 1)
  ratio_mag_w <- winsor_vec(ratio_mag, p = REL_WINSOR_P)
  y0    <- log1p(ratio_mag_w)
  dv_label <- "log1p(|Δ| / emissions), winsorized"
} else {
  disc_signed_raw <- winsor_vec(as.numeric(df$emissions_discrepancy), p = ABS_WINSOR_P)
  y0 <- log1p(abs(disc_signed_raw) / 1e6)
  dv_label <- "log1p(|Δ| / 1e6)"
}
y_mean <- mean(y0); y_sd <- sd(y0)
df$y  <- as.numeric((y0 - y_mean) / y_sd)

# ------------------ Size spline (orthonormalized basis) ------------------
ns_raw    <- ns(df$z_size, df = SIZE_SPLINE_DF)
ns_scaled <- scale(ns_raw, center = TRUE, scale = TRUE)
ns_qr     <- qr(ns_scaled)
ns_mat    <- qr.Q(ns_qr)
ns_names  <- paste0("nsZ_", seq_len(ncol(ns_mat)))
for (j in seq_along(ns_names)) df[[ns_names[j]]] <- as.numeric(ns_mat[, j])

# ------------------ Demean industry w/in NAICS3 (within) ------------------
IND_FEATS   <- c("ind_ROA_z","ind_Leverage_z","ind_RD_intensity_z","ind_at_z")
IND_FEATS_C <- paste0(IND_FEATS, "_c")
df <- df |>
  group_by(naics3_folded) |>
  mutate(
    ind_ROA_z_c          = ind_ROA_z          - mean(ind_ROA_z,          na.rm = TRUE),
    ind_Leverage_z_c     = ind_Leverage_z     - mean(ind_Leverage_z,     na.rm = TRUE),
    ind_RD_intensity_z_c = ind_RD_intensity_z - mean(ind_RD_intensity_z, na.rm = TRUE),
    ind_at_z_c           = ind_at_z           - mean(ind_at_z,           na.rm = TRUE)
  ) |>
  ungroup()

# ------------------ Terms ------------------
re_terms <- "(1|ghgrp_id) + (1|parent_folded) + (1|county_folded) + (1|naics3_folded)"
fe_REonly <- "1"
fe_size   <- paste(c("1", ns_names), collapse = " + ")
fe_year   <- paste(c(fe_size, "factor(ghgrp_year)"), collapse = " + ")
fe_full   <- paste(c(fe_year, IND_FEATS_C), collapse = " + ")

form_REonly <- as.formula(paste("y ~", fe_REonly, "+", re_terms))
form_size   <- as.formula(paste("y ~", fe_size,   "+", re_terms))
form_year   <- as.formula(paste("y ~", fe_year,   "+", re_terms))
form_full   <- as.formula(paste("y ~", fe_full,   "+", re_terms))

# ------------------ Optimizers ------------------
make_ctrl <- function(opt_name, ...) {
  tryCatch(lmerControl(optimizer = opt_name, ...), error = function(e) NULL)
}
ctrl_bobyqa     <- make_ctrl("bobyqa",
                             optCtrl = list(maxfun = 1.5e6),
                             calc.derivs = TRUE,
                             check.conv.grad = list(action="warning", tol=GRAD_TOL))
ctrl_nloptwrap  <- make_ctrl("nloptwrap",
                             optCtrl = list(maxfun = 8e5),
                             calc.derivs = TRUE,
                             check.conv.grad = list(action="warning", tol=GRAD_TOL))
ctrl_nlminbwrap <- make_ctrl("nlminbwrap",
                             optCtrl = list(maxfun = 2e6),
                             calc.derivs = TRUE,
                             check.conv.grad = list(action="warning", tol=GRAD_TOL))
ctrl_Nelder_Mead<- make_ctrl("Nelder_Mead",
                             optCtrl = list(maxfun = 2e6),
                             calc.derivs = TRUE,
                             check.conv.grad = list(action="warning", tol=GRAD_TOL))

# ------------------ Stepwise seeded fitting (ALL REs kept) ------------------
m_REonly <- lmer(form_REonly, data = df, control = ctrl_bobyqa, REML = TRUE)
theta0   <- getME(m_REonly, "theta")

m_size <- lmer(form_size, data = df, control = ctrl_bobyqa, REML = TRUE,
               start = list(theta = theta0))
theta1 <- getME(m_size, "theta")

m_year <- lmer(form_year, data = df, control = ctrl_bobyqa, REML = TRUE,
               start = list(theta = theta1))
theta2 <- getME(m_year, "theta")

# Warm ML then REML on full FE, seeding from m_year
m_full_ml <- lmer(form_full, data = df, control = ctrl_bobyqa, REML = FALSE,
                  start = list(theta = theta2))
mod0 <- update(m_full_ml, REML = TRUE, control = ctrl_bobyqa)

# ------------------ Multi-optimizer sweep (robust & safe) ------------------
seed_theta <- getME(mod0, "theta")

safe_refit <- function(ctrl) {
  if (is.null(ctrl)) return(structure("try-error", class = "try-error"))
  try(suppressWarnings(
    lmer(form_full, data = df, control = ctrl, REML = TRUE,
         start = list(theta = seed_theta))
  ), silent = TRUE)
}
cand_list <- list(seed = mod0)
ctrl_map <- list(bobyqa = ctrl_bobyqa,
                 nloptwrap = ctrl_nloptwrap,
                 nlminbwrap = ctrl_nlminbwrap,
                 Nelder_Mead = ctrl_Nelder_Mead)
for (nm in names(ctrl_map)) cand_list[[nm]] <- safe_refit(ctrl_map[[nm]])

cand_info <- lapply(names(cand_list), function(nm) {
  m <- cand_list[[nm]]
  if (inherits(m, "try-error")) {
    data.frame(optimizer = nm, code = 999L, grad = Inf, AIC = Inf)
  } else {
    gi <- ginfo(m)
    code_val <- gi$code; if (length(code_val) == 0 || is.na(code_val)) code_val <- 999L
    grad_val <- gi$grad; if (length(grad_val) == 0 || is.na(grad_val)) grad_val <- Inf
    aic_val  <- gi$aic;  if (length(aic_val)  == 0 || is.na(aic_val))  aic_val  <- Inf
    data.frame(optimizer = nm, code = as.integer(code_val),
               grad = as.numeric(grad_val), AIC = as.numeric(aic_val))
  }
})
cand_df <- do.call(rbind, cand_info)

cat("\n[Optimizer candidates]\n")
rank_key <- ifelse(is.finite(cand_df$code) & cand_df$code == 0, 0, 1)
print(cand_df[order(rank_key, cand_df$grad, cand_df$AIC), ], row.names = FALSE)

# Pick best; fallback to seed if needed
rank_idx <- order(rank_key, cand_df$grad, cand_df$AIC)
best_name <- cand_df$optimizer[ rank_idx[1] ]
mod <- cand_list[[ best_name ]]
if (inherits(mod, "try-error")) { warning("All optimizer updates failed; using seed REML fit."); mod <- cand_list$seed; best_name <- "seed" }

gi_best <- log_header(mod, sprintf("FINAL (%s) — %s", best_name, dv_label), y_mean, y_sd)

# ------------------ Convergence verdict ------------------
cat("\n[Convergence verdict]\n")
if (!is.na(gi_best$grad) && gi_best$grad <= GRAD_TOL && !lme4::isSingular(mod, tol = 1e-4)) {
  cat("Converged: YES (gradient within tolerance; fit non-singular). Final model used:", best_name, "\n")
} else {
  cat("Converged: BORDERLINE — diagnostics suggest stability; see gradient/AIC above.\n")
}

# ---------- Fixed effects (industry) ----------
coefs <- coef(summary(mod))
coef_tab <- data.frame(term = rownames(coefs), coefs, row.names = NULL, check.names = FALSE)
IND_FEATS   <- c("ind_ROA_z","ind_Leverage_z","ind_RD_intensity_z","ind_at_z")
IND_FEATS_C <- paste0(IND_FEATS, "_c")
fe_inds <- subset(coef_tab, term %in% IND_FEATS_C)[, c("term","Estimate","Std. Error","t value","Pr(>|t|)")]
names(fe_inds) <- c("term","estimate","std.error","t","p.value")
cat("\n[Fixed effects — Industry covariates (NAICS3-demeaned)]\n")
if (nrow(fe_inds) == 0) cat("(none)\n") else print(fe_inds, row.names = FALSE)

# ---------- FE Confidence Intervals (Wald) ----------
fe_names_all <- rownames(coef(summary(mod)))
fe_ci <- tryCatch({
  as.data.frame(confint(mod, parm = fe_names_all, method = "Wald"))
}, error = function(e) {
  ss <- coef(summary(mod))
  L <- ss[, "Estimate"] - 1.96 * ss[, "Std. Error"]
  U <- ss[, "Estimate"] + 1.96 * ss[, "Std. Error"]
  data.frame(`2.5 %` = L, `97.5 %` = U, row.names = rownames(ss))
})
fe_ci$term <- rownames(fe_ci)
cat("\n[Fixed effects — 95% Wald CIs]\n")
print(fe_ci[, c("term","2.5 %","97.5 %")], row.names = FALSE)

# Optional: RE profile CIs (can be slow)
if (isTRUE(PROFILE_RE_CI)) {
  re_ci <- tryCatch(as.data.frame(confint(mod, method = "profile")), error = function(e) NULL)
  if (!is.null(re_ci)) {
    cat("\n[Random effects SD — profile 95% CIs]\n")
    print(re_ci[grepl("^sd__", rownames(re_ci)), , drop=FALSE])
  }
}

# ---------- Variance components & shares ----------
vc <- as.data.frame(VarCorr(mod))
var_tab <- vc |>
  dplyr::transmute(component = ifelse(grp == "Residual", "residual", as.character(grp)),
                   variance  = vcov) |>
  dplyr::group_by(component) |>
  dplyr::summarise(variance = sum(variance), .groups = "drop") |>
  dplyr::mutate(
    share_pct = 100 * variance / sum(variance),
    component = dplyr::recode(component,
                              "ghgrp_id"      = "facility (ghgrp_id)",
                              "parent_folded" = "parent",
                              "county_folded" = "county",
                              "naics3_folded" = "naics3",
                              "residual"      = "residual")
  ) |>
  dplyr::arrange(factor(component, levels = c("facility (ghgrp_id)","parent","county","naics3","residual")))
cat("\n[Variance components (REML) and shares — of TOTAL variance]\n")
print(var_tab, row.names = FALSE)

# ---------- Random-only shares ----------
var_tab_random_only <- subset(var_tab, component != "residual")
if (nrow(var_tab_random_only) > 0) {
  var_tab_random_only$share_of_random <- 100 * var_tab_random_only$variance / sum(var_tab_random_only$variance)
  cat("\n[Random effects — shares WITHIN RANDOM variance only]\n")
  print(var_tab_random_only[, c("component","variance","share_of_random")], row.names = FALSE)
}

# ---------- R² (Nakagawa) ----------
r2_tbl <- nakagawa_r2(mod)
cat("\n[R² (Nakagawa & Schielzeth)]\n")
print(r2_tbl, row.names = FALSE)

# ---------- Block ΔR² (marginal, drop-one FE) ----------
stopifnot(all(ns_names %in% colnames(lme4::getME(mod,"X"))))
# seed only theta for refits
refit_drop <- function(drop_terms) {
  f2 <- update(form_full, paste(". ~ . -", paste(drop_terms, collapse = " - ")))
  suppressWarnings(
    lmer(f2, data = df, control = ctrl_bobyqa, REML = TRUE,
         start = list(theta = getME(mod, "theta")))
  )
}
block_year <- "factor(ghgrp_year)"
block_size <- ns_names
block_ind  <- IND_FEATS_C
r2_full    <- nakagawa_r2(mod)$R2_marginal

mod_no_year <- refit_drop(block_year)
mod_no_size <- refit_drop(block_size)
mod_no_ind  <- refit_drop(block_ind)

r2_no_year <- nakagawa_r2(mod_no_year)$R2_marginal
r2_no_size <- nakagawa_r2(mod_no_size)$R2_marginal
r2_no_ind  <- nakagawa_r2(mod_no_ind)$R2_marginal

block_tbl <- data.frame(
  block        = c("years (FE)", "size (natural spline)", "industry covariates"),
  delta_R2_marg= c(r2_full - r2_no_year,
                   r2_full - r2_no_size,
                   r2_full - r2_no_ind),
  base_R2_marg = r2_full
)
block_tbl <- block_tbl[order(-block_tbl$delta_R2_marg), ]
cat("\n[Block ΔR² (marginal, drop-one FE)]\n")
print(block_tbl, row.names = FALSE)

# ---------- ML LR tests for FE blocks ----------
refit_ml <- function(drop_terms = NULL) {
  f <- form_full
  if (!is.null(drop_terms) && length(drop_terms)) {
    f <- update(f, paste(". ~ . -", paste(drop_terms, collapse = " - ")))
  }
  suppressWarnings(
    lmer(f, data = df, control = ctrl_bobyqa, REML = FALSE,
         start = list(theta = getME(mod, "theta")))
  )
}
m_full_ml_blocks <- refit_ml(NULL)
m_no_year <- refit_ml(block_year)
m_no_size <- refit_ml(block_size)
m_no_ind  <- refit_ml(block_ind)
lr_tbl <- rbind(
  lr_from_logLik(m_no_year, m_full_ml_blocks, "years (FE)"),
  lr_from_logLik(m_no_size, m_full_ml_blocks, "size (natural spline)"),
  lr_from_logLik(m_no_ind,  m_full_ml_blocks, "industry covariates")
)
cat("\n[Fixed-effect blocks — ML Likelihood-Ratio tests]\n")
print(lr_tbl, row.names = FALSE)

# ---------- Fixed-effect variance shares (of TOTAL variance) ----------
fe_names <- names(lme4::fixef(mod))
X_all <- lme4::getME(mod, "X"); colnames(X_all) <- fe_names
b <- lme4::fixef(mod)
idx_year <- grepl("^factor\\(ghgrp_year\\)", fe_names)
idx_size <- fe_names %in% ns_names
idx_ind  <- fe_names %in% IND_FEATS_C
eta_year <- if (any(idx_year)) as.vector(X_all[, idx_year, drop=FALSE] %*% b[idx_year]) else rep(0, nrow(X_all))
eta_size <- if (any(idx_size)) as.vector(X_all[, idx_size, drop=FALSE] %*% b[idx_size]) else rep(0, nrow(X_all))
eta_ind  <- if (any(idx_ind))  as.vector(X_all[, idx_ind,  drop=FALSE] %*% b[idx_ind])  else rep(0, nrow(X_all))
var_year <- stats::var(eta_year, na.rm = TRUE)
var_size <- stats::var(eta_size, na.rm = TRUE)
var_ind  <- stats::var(eta_ind,  na.rm = TRUE)
vc2 <- as.data.frame(VarCorr(mod))
var_resid  <- sum(vc2$vcov[vc2$grp == "Residual"])
var_random <- sum(vc2$vcov[vc2$grp != "Residual"])
var_fe_tot <- stats::var(as.vector(X_all %*% b), na.rm = TRUE)
var_total  <- var_fe_tot + var_random + var_resid
fe_share_tbl <- data.frame(
  fixed_block = c("Year FE","Size (ns) FE","Industry FE"),
  variance    = c(var_year, var_size, var_ind),
  share_pct_of_total = 100 * c(var_year, var_size, var_ind) / var_total
)
cat("\n[Fixed-effect variance shares (as % of TOTAL variance)]\n")
print(fe_share_tbl, row.names = FALSE)

# ---------- Per-variable ΔR² (industry terms) ----------
per_var_rows <- lapply(IND_FEATS_C, function(v){
  if (!v %in% fe_names) return(NULL)
  m_drop <- refit_drop(v)
  r2_drop <- nakagawa_r2(m_drop)$R2_marginal
  data.frame(term = v, delta_R2_marg = r2_full - r2_drop, base_R2_marg = r2_full)
})
per_var_tbl <- do.call(rbind, Filter(Negate(is.null), per_var_rows))
if (nrow(per_var_tbl)) {
  per_var_tbl <- per_var_tbl[order(-per_var_tbl$delta_R2_marg), ]
  cat("\n[Per-variable ΔR² (marginal) — industry covariates]\n")
  print(per_var_tbl, row.names = FALSE)
}

# =====================================================================
# (1) INDUSTRY BREAKDOWNS — raw discrepancy + model-based NAICS3 BLUPs
# =====================================================================
cat("\n[Industry breakdown — raw discrepancy by NAICS3 (winsorized ratio, not log1p)]\n")
ratio_desc <- winsor_vec(abs(as.numeric(df$emissions_discrepancy)) / pmax(as.numeric(df$ghgrp_emissions_tons), 1),
                         p = REL_WINSOR_P)
ind_tab <- df |>
  mutate(ratio_desc = ratio_desc) |>
  group_by(naics3_folded) |>
  summarise(n_obs = n(),
            n_facilities = n_distinct(ghgrp_id),
            median_ratio = median(ratio_desc, na.rm = TRUE),
            p25 = quantile(ratio_desc, 0.25, na.rm = TRUE),
            p75 = quantile(ratio_desc, 0.75, na.rm = TRUE),
            p90 = quantile(ratio_desc, 0.90, na.rm = TRUE),
            .groups = "drop") |>
  arrange(desc(median_ratio))
print(ind_tab, n = min(nrow(ind_tab), 40))

cat("\n[Top 10 industries by median discrepancy]\n")
print(head(ind_tab, 10), row.names = FALSE)
cat("\n[Bottom 10 industries by median discrepancy]\n")
print(tail(ind_tab, 10), row.names = FALSE)

cat("\n[Industry random effects (BLUPs) with 95% CIs — NAICS3]\n")
naics_blup <- blup_table(mod, "naics3_folded") |>
  arrange(desc(effect))
print(head(naics_blup, 15), row.names = FALSE)
cat("\n[Bottom 15 industries (most negative BLUPs)]\n")
print(tail(naics_blup, 15), row.names = FALSE)

# =======================================================
# (2) OWNER (PARENT) EFFECT — RLRT + owner BLUPs with FDR
# =======================================================
cat("\n[Owner effect — exact RLRT via lmerTest::rand]\n")
rand_tbl <- tryCatch(as.data.frame(lmerTest::rand(mod)), error = function(e) NULL)
if (!is.null(rand_tbl)) {
  print(rand_tbl, row.names = FALSE)
  if ("parent_folded" %in% rand_tbl$grp) {
    p_parent <- rand_tbl$`Pr(>Chisq)`[rand_tbl$grp == "parent_folded"]
    cat(sprintf("\nRLRT p-value for (1|parent_folded): %s\n", format(p_parent, digits = 4)))
  }
} else {
  cat("RLRT table unavailable (rand() failed).\n")
}

# --- TIGHTEN: Boundary-corrected ML LRT fallback (0.5 * chi^2_1) ---
cat("\n[Owner effect — boundary-corrected ML LRT fallback (0.5 * χ^2_1)]\n")
re_terms_no_parent <- "(1|ghgrp_id) + (1|county_folded) + (1|naics3_folded)"
form_full_no_parent <- as.formula(paste("y ~", fe_full, "+", re_terms_no_parent))
m_full_ml_parent <- try(lmer(form_full,          data = df, control = ctrl_bobyqa, REML = FALSE), silent = TRUE)
m_no_parent_ml   <- try(lmer(form_full_no_parent, data = df, control = ctrl_bobyqa, REML = FALSE), silent = TRUE)
if (!inherits(m_full_ml_parent, "try-error") && !inherits(m_no_parent_ml, "try-error")) {
  ll_full <- as.numeric(logLik(m_full_ml_parent))
  ll_nop  <- as.numeric(logLik(m_no_parent_ml))
  chisq <- 2 * (ll_full - ll_nop)
  p_mix <- 0.5 * pchisq(chisq, df = 1, lower.tail = FALSE)
  cat(sprintf("Full vs. no-parent ML LRT: 2ΔLL=%.3f, df=1, boundary p=%.4g\n", chisq, p_mix))
} else {
  cat("ML LRT fallback could not be computed (one of the ML fits failed).\n")
}

cat("\n[Owner BLUPs with 95% CIs + BH-FDR]\n")
parent_blup <- blup_table(mod, "parent_folded") |>
  arrange(desc(abs(effect)))
parent_sig <- sum(parent_blup$p_adj_BH < 0.05, na.rm = TRUE)
cat(sprintf("Owners with |BLUP| significantly ≠ 0 after BH-FDR (q<0.05): %d of %d\n",
            parent_sig, nrow(parent_blup)))
print(head(parent_blup, 20), row.names = FALSE)

# ================================================
# (3) SIGNED DISCREPANCY MODEL — industry *bias*
# ================================================
cat("\n[Signed discrepancy model — outcome is signed ratio (winsorized, centered/scaled)]\n")
ratio_signed <- as.numeric(df$emissions_discrepancy) / pmax(as.numeric(df$ghgrp_emissions_tons), 1)
ratio_signed_w <- winsor_vec(ratio_signed, p = REL_WINSOR_P)

# --- TIGHTEN: report pre-scale mean/sd for interpretability ---
signed_mean <- mean(ratio_signed_w, na.rm = TRUE)
signed_sd   <- sd(ratio_signed_w, na.rm = TRUE)
cat(sprintf("Signed ratio (pre-scale) mean=%.6f, sd=%.6f\n", signed_mean, signed_sd))

y2 <- as.numeric(scale(ratio_signed_w))
df$y_signed <- y2

form_full_signed <- update(form_full, y_signed ~ .)

mod_signed <- lmer(form_full_signed, data = df, control = ctrl_bobyqa, REML = TRUE,
                   start = list(theta = getME(mod, "theta")))
gi_signed <- log_header(mod_signed, "SIGNED DV (winsorized ratio)", mean(y2), sd(y2))

# NAICS3 signed BLUPs: who tends to over/under-report?
cat("\n[NAICS3 signed BLUPs (directional bias), 95% CIs]\n")
naics_signed <- blup_table(mod_signed, "naics3_folded") |>
  arrange(desc(effect))
cat("\n[Top 12 industries (positive bias)]\n"); print(head(naics_signed, 12), row.names = FALSE)
cat("\n[Bottom 12 industries (negative bias)]\n"); print(tail(naics_signed, 12), row.names = FALSE)
sig_ind <- sum(naics_signed$p_adj_BH < 0.05, na.rm = TRUE)
cat(sprintf("\nIndustries with signed BLUP significantly ≠ 0 after BH-FDR (q<0.05): %d of %d\n",
            sig_ind, nrow(naics_signed)))

# --- TIGHTEN++: OWNER directional (signed) tests ---
cat("\n[Owner directional effect — ML LRT on SIGNED DV (0.5 * χ^2_1)]\n")
form_full_signed_no_parent <- as.formula(paste("y_signed ~", fe_full, "+", re_terms_no_parent))
m_signed_full_ml <- try(lmer(update(form_full_signed, . ~ .), data = df,
                             control = ctrl_bobyqa, REML = FALSE), silent = TRUE)
m_signed_nop_ml  <- try(lmer(form_full_signed_no_parent, data = df,
                             control = ctrl_bobyqa, REML = FALSE), silent = TRUE)
if (!inherits(m_signed_full_ml, "try-error") && !inherits(m_signed_nop_ml, "try-error")) {
  llf <- as.numeric(logLik(m_signed_full_ml))
  lln <- as.numeric(logLik(m_signed_nop_ml))
  chisq_s <- 2 * (llf - lln)
  p_mix_s <- 0.5 * pchisq(chisq_s, df = 1, lower.tail = FALSE)
  cat(sprintf("SIGNED: Full vs. no-parent ML LRT: 2ΔLL=%.3f, df=1, boundary p=%.4g\n", chisq_s, p_mix_s))
} else {
  cat("SIGNED: ML LRT could not be computed (one of the ML fits failed).\n")
}

cat("\n[Owner signed BLUPs with 95% CIs + BH-FDR]\n")
parent_blup_signed <- blup_table(mod_signed, "parent_folded") |>
  arrange(desc(abs(effect)))
parent_sig_signed <- sum(parent_blup_signed$p_adj_BH < 0.05, na.rm = TRUE)
cat(sprintf("Owners with signed |BLUP| significantly ≠ 0 after BH-FDR (q<0.05): %d of %d\n",
            parent_sig_signed, nrow(parent_blup_signed)))
print(head(parent_blup_signed, 20), row.names = FALSE)

# ==============================================================
# (4) BETWEEN vs WITHIN industry characteristics decomposition
# ==============================================================

# Add NAICS3 means ("between") alongside within-demeaned covariates
df <- df |>
  group_by(naics3_folded) |>
  mutate(
    ind_ROA_naics3_mean       = mean(ind_ROA_z,          na.rm = TRUE),
    ind_Leverage_naics3_mean  = mean(ind_Leverage_z,     na.rm = TRUE),
    ind_RD_int_naics3_mean    = mean(ind_RD_intensity_z, na.rm = TRUE),
    ind_at_naics3_mean        = mean(ind_at_z,           na.rm = TRUE)
  ) |>
  ungroup()

IND_FEATS_B <- c("ind_ROA_naics3_mean","ind_Leverage_naics3_mean",
                 "ind_RD_int_naics3_mean","ind_at_naics3_mean")

fe_full_bw <- paste(c(fe_year, IND_FEATS_C, IND_FEATS_B), collapse = " + ")
form_full_bw <- as.formula(paste("y ~", fe_full_bw, "+", re_terms))

cat("\n[Between vs Within model — adding NAICS3 means as separate FE]\n")
mod_bw <- lmer(form_full_bw, data = df, control = ctrl_bobyqa, REML = TRUE,
               start = list(theta = getME(mod, "theta")))
gi_bw <- ginfo(mod_bw)
cat(sprintf("REML=yes | logLik=%.1f | AIC=%.1f | Singular: %s | max|grad|≈%s\n",
            as.numeric(logLik(mod_bw)), AIC(mod_bw),
            lme4::isSingular(mod_bw, tol=1e-4),
            ifelse(is.na(gi_bw$grad), "NA", sprintf("%.3g", gi_bw$grad))))

# How much NAICS3 random variance does BETWEEN explain?
v_naics_full <- get_var_component(mod,    "naics3_folded")
v_naics_bw   <- get_var_component(mod_bw, "naics3_folded")
explained_share <- if (isTRUE(v_naics_full>0)) 100 * (v_naics_full - v_naics_bw) / v_naics_full else NA_real_
cat(sprintf("\n[NAICS3 variance explained by BETWEEN covariates]\nFull model var=%.6f vs With BETWEEN var=%.6f => reduction=%.2f%%\n",
            v_naics_full, v_naics_bw, explained_share))

# ΔR² for BETWEEN vs WITHIN blocks (marginal R², on mod_bw)
r2_bw_full <- nakagawa_r2(mod_bw)$R2_marginal
refit_drop_bw <- function(drop_terms) {
  f2 <- update(form_full_bw, paste(". ~ . -", paste(drop_terms, collapse = " - ")))
  suppressWarnings(
    lmer(f2, data = df, control = ctrl_bobyqa, REML = TRUE,
         start = list(theta = getME(mod_bw, "theta")))
  )
}
m_bw_no_within  <- refit_drop_bw(IND_FEATS_C)
m_bw_no_between <- refit_drop_bw(IND_FEATS_B)
r2_no_within    <- nakagawa_r2(m_bw_no_within)$R2_marginal
r2_no_between   <- nakagawa_r2(m_bw_no_between)$R2_marginal

bw_block_tbl <- data.frame(
  block = c("Within-industry covariates (demeaned)","Between-industry covariates (NAICS3 means)"),
  delta_R2_marg = c(r2_bw_full - r2_no_within, r2_bw_full - r2_no_between),
  base_R2_marg = r2_bw_full
)
cat("\n[Block ΔR² — Between vs Within (marginal R² on mod_bw)]\n")
print(bw_block_tbl, row.names = FALSE)

# Correlate NAICS3 BLUPs (from magnitude model) with NAICS3 means (industry traits)
cat("\n[Correlation of NAICS3 BLUPs (magnitude model) with NAICS3 means]\n")
naics_means <- df |>
  group_by(naics3_folded) |>
  summarise(across(all_of(IND_FEATS_B), \(x) mean(x, na.rm = TRUE)), .groups = "drop")
naics_blup_only <- naics_blup[, c("level","effect")]
names(naics_blup_only) <- c("naics3_folded","blup_effect")
corr_rows <- lapply(IND_FEATS_B, function(v){
  vv <- merge(naics_means[, c("naics3_folded", v)], naics_blup_only, by = "naics3_folded", all.x = TRUE)
  ct <- suppressWarnings(cor.test(vv[[v]], vv$blup_effect))
  data.frame(var = v, cor = unname(ct$estimate), p.value = ct$p.value)
})
corr_tbl <- do.call(rbind, corr_rows)
print(corr_tbl, row.names = FALSE)

# Per-facility averages (in raw tons) — RECOMPUTED ON FULL COVERAGE
# (Only require ghgrp_id, ghgrp_emissions_tons, emissions_discrepancy; ignore modeling covariates)

# ---------------- Facility metrics & Top-100 (FULL COVERAGE) ----------------
cat("\n[Facility emissions & error magnitudes — FULL COVERAGE]\n")

# Read minimal columns (full coverage for facility stats)
df_fac <- suppressMessages(readr::read_csv(CSV_PATH, show_col_types = FALSE)) |>
  dplyr::filter(!is.na(ghgrp_id),
                !is.na(ghgrp_emissions_tons),
                !is.na(emissions_discrepancy))

# Sanity: no duplicate facility-year rows
dup_fac <- df_fac |>
  dplyr::count(ghgrp_id, ghgrp_year, name = "n") |>
  dplyr::filter(n > 1) |>
  nrow()
stopifnot(dup_fac == 0)

# Fold NAICS3 for readability in outputs
df_fac <- df_fac |>
  dplyr::mutate(naics3_folded = fold_by_ids(NAICS3, ghgrp_id, min_ids = MIN_IDS_NAICS3))

# Helper: mode label per facility
mode_chr <- function(x){
  x <- x[!is.na(x)]
  if (!length(x)) return(NA_character_)
  names(sort(table(x), decreasing = TRUE))[1]
}

# One-pass facility-level table (NO multi-key grouping)
fac <- df_fac |>
  dplyr::group_by(ghgrp_id) |>
  dplyr::summarise(
    n_years                  = dplyr::n(),
    # stable labels (mode across years)
    ghgrp_parent_companies   = mode_chr(ghgrp_parent_companies),
    ghgrp_county_name        = mode_chr(ghgrp_county_name),
    naics3_folded            = mode_chr(naics3_folded),
    # emissions
    mean_emissions_tons      = mean(as.numeric(ghgrp_emissions_tons),  na.rm = TRUE),
    median_emissions_tons    = stats::median(as.numeric(ghgrp_emissions_tons), na.rm = TRUE),
    # discrepancy (signed tons)
    mean_signed_delta_tons   = mean(as.numeric(emissions_discrepancy), na.rm = TRUE),
    mean_abs_delta_tons      = mean(abs(as.numeric(emissions_discrepancy)), na.rm = TRUE),
    median_signed_delta_tons = stats::median(as.numeric(emissions_discrepancy), na.rm = TRUE),
    sd_signed_delta_tons     = stats::sd(as.numeric(emissions_discrepancy), na.rm = TRUE),
    min_signed_delta_tons    = min(as.numeric(emissions_discrepancy), na.rm = TRUE),
    max_signed_delta_tons    = max(as.numeric(emissions_discrepancy), na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    # relative magnitudes at facility level
    rel_abs_error = mean_abs_delta_tons / pmax(mean_emissions_tons, 1),
    rel_signed    = mean_signed_delta_tons / pmax(mean_emissions_tons, 1)
  )

# Overall (row-weighted, all years)
options(scipen = 999)
overall_mean_signed   <- mean(as.numeric(df_fac$emissions_discrepancy), na.rm = TRUE)
overall_median_signed <- median(as.numeric(df_fac$emissions_discrepancy), na.rm = TRUE)
overall_mean_abs      <- mean(abs(as.numeric(df_fac$emissions_discrepancy)), na.rm = TRUE)

facility_mean_of_means   <- mean(fac$mean_signed_delta_tons, na.rm = TRUE)
facility_median_of_means <- median(fac$mean_signed_delta_tons, na.rm = TRUE)

cat("\n[Average signed error (tons) — overall & facility-level]\n")
cat(sprintf("Overall mean signed Δ (tons): %.6f\n",  overall_mean_signed))
cat(sprintf("Overall median signed Δ (tons): %.6f\n", overall_median_signed))
cat(sprintf("Overall mean |Δ| (tons): %.6f\n",        overall_mean_abs))
cat(sprintf("Facility-level mean of means (signed Δ, tons): %.6f\n",   facility_mean_of_means))
cat(sprintf("Facility-level median of means (signed Δ, tons): %.6f\n", facility_median_of_means))
cat(sprintf("Number of facilities used: %s\n", format(nrow(fac), big.mark=",")))

# Top-100 (unique facilities)
top100_fac_pos <- fac |>
  dplyr::arrange(dplyr::desc(mean_signed_delta_tons)) |>
  dplyr::slice_head(n = 100)
top100_fac_neg <- fac |>
  dplyr::arrange(mean_signed_delta_tons) |>
  dplyr::slice_head(n = 100)

# Safeguard: no duplicates
stopifnot(!any(duplicated(top100_fac_pos$ghgrp_id)))
stopifnot(!any(duplicated(top100_fac_neg$ghgrp_id)))

cat("\n[Top 100 facilities — strongest average OVERSTATEMENT (largest + mean Δ in tons)]\n")
print(utils::head(top100_fac_pos, 5))
cat("\n[Top 100 facilities — strongest average UNDERSTATEMENT (most − mean Δ in tons)]\n")
print(utils::head(top100_fac_neg, 5))

# Save CSVs for the professor
readr::write_csv(top100_fac_pos, "top100_facilities_overstatement_signed_tons.csv")
readr::write_csv(top100_fac_neg, "top100_facilities_understatement_signed_tons.csv")
cat("\nSaved CSVs: 'top100_facilities_overstatement_signed_tons.csv' and 'top100_facilities_understatement_signed_tons.csv'\n")

# “Is it big?” summaries (facility level)
fmt_num <- function(x) formatC(as.numeric(x), big.mark = ",", digits = 3, format = "f")
fmt_pct <- function(x) sprintf("%.1f%%", 100*as.numeric(x))
summ <- list(
  facilities_n               = nrow(fac),
  mean_fac_emissions_tons    = mean(fac$mean_emissions_tons,   na.rm = TRUE),
  median_fac_emissions_tons  = median(fac$mean_emissions_tons, na.rm = TRUE),
  mean_abs_fac_error_tons    = mean(abs(fac$mean_signed_delta_tons), na.rm = TRUE),  # |mean Δ_i|
  median_abs_fac_error_tons  = median(abs(fac$mean_signed_delta_tons), na.rm = TRUE),
  median_rel_abs_error       = median(fac$rel_abs_error, na.rm = TRUE),
  iqr_rel_abs_error_low      = quantile(fac$rel_abs_error, 0.25, na.rm = TRUE),
  iqr_rel_abs_error_high     = quantile(fac$rel_abs_error, 0.75, na.rm = TRUE),
  share_fac_rel_abs_gt_5pct  = mean(fac$rel_abs_error > 0.05, na.rm = TRUE),
  share_fac_rel_abs_gt_10pct = mean(fac$rel_abs_error > 0.10, na.rm = TRUE),
  share_fac_rel_abs_gt_50pct = mean(fac$rel_abs_error > 0.50, na.rm = TRUE)
)
cat("\n[Facility emissions & error magnitudes — summaries]\n")
cat(sprintf(
  paste0(
    "Facilities (with >=1 year): %s\n",
    "Average annual emissions per facility (mean | median): %s | %s tons\n",
    "Average absolute facility error (|mean Δ| across years per facility):\n",
    "  mean %s tons | median %s tons\n",
    "Typical relative magnitude at facility level (mean |Δ| / mean emissions):\n",
    "  median %s (IQR %s–%s)\n",
    "Fraction of facilities with |Δ|/emissions > 5%% / 10%% / 50%%: %s / %s / %s\n"
  ),
  fmt_num(summ$facilities_n),
  fmt_num(summ$mean_fac_emissions_tons), fmt_num(summ$median_fac_emissions_tons),
  fmt_num(summ$mean_abs_fac_error_tons), fmt_num(summ$median_abs_fac_error_tons),
  fmt_pct(summ$median_rel_abs_error),
  fmt_pct(summ$iqr_rel_abs_error_low), fmt_pct(summ$iqr_rel_abs_error_high),
  fmt_pct(summ$share_fac_rel_abs_gt_5pct),
  fmt_pct(summ$share_fac_rel_abs_gt_10pct),
  fmt_pct(summ$share_fac_rel_abs_gt_50pct)
))

# Emissions-weighted system-level one-liner
cat(sprintf("\nEmissions-weighted |Δ|/emissions = %.2f%%\n",
            100 * with(df_fac,
                       sum(abs(as.numeric(emissions_discrepancy)), na.rm = TRUE) /
                       sum(as.numeric(ghgrp_emissions_tons),       na.rm = TRUE))))