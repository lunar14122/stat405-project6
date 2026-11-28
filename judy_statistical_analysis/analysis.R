# STAT 405 Group 6: Judy
# Run from the repository root:
# Rscript judy_statistical_analysis/analysis.R

# Read Member 1's grouped data
flights <- read.csv(
  "summary-2022-2025.csv",
  stringsAsFactors = FALSE
)

dir.create(
  "judy_statistical_analysis/results",
  recursive = TRUE,
  showWarnings = FALSE
)

# Check the required columns
required <- c(
  "Year", "Airline", "Season", "Region", "TimeOfDay",
  "TotalFlights", "DelayedFlights", "DelayRate"
)

stopifnot(all(required %in% names(flights)))
stopifnot(nrow(flights) > 0)
stopifnot(!anyNA(flights[required]))

# Check counts and grouping keys
stopifnot(
  all(flights$TotalFlights > 0),
  all(flights$TotalFlights == floor(flights$TotalFlights)),
  all(flights$DelayedFlights >= 0),
  all(flights$DelayedFlights == floor(flights$DelayedFlights)),
  all(flights$DelayedFlights <= flights$TotalFlights),
  all(flights$TimeOfDay %in% c("Morning", "Evening"))
)

keys <- c("Year", "Airline", "Season", "Region", "TimeOfDay")
stopifnot(!anyDuplicated(flights[keys]))

rate_error <- max(abs(
  flights$DelayRate -
    flights$DelayedFlights / flights$TotalFlights
))
stopifnot(rate_error < 1e-10)

cat("Data checks passed.\n")
cat("Number of groups:", nrow(flights), "\n")
cat("Included flights:", sum(flights$TotalFlights), "\n\n")

# Sum counts first, then calculate overall delay rates
overall <- aggregate(
  cbind(TotalFlights, DelayedFlights) ~ TimeOfDay,
  data = flights,
  FUN = sum
)

overall <- overall[
  match(c("Morning", "Evening"), overall$TimeOfDay),
]
rownames(overall) <- NULL

overall$DelayRate <-
  overall$DelayedFlights / overall$TotalFlights

overall$DelayPercent <- 100 * overall$DelayRate

cat("Overall departure-delay rates:\n")
print(overall, row.names = FALSE)

# Evening penalty: percentage-point difference
penalty_pp <- overall$DelayPercent[2] -
  overall$DelayPercent[1]

cat(sprintf(
  "\nEvening penalty: %.2f percentage points\n",
  penalty_pp
))

# Save the table
write.csv(
  overall,
  "judy_statistical_analysis/results/overall_delay_rates.csv",
  row.names = FALSE
)

# Save a figure using base R
pdf(
  "judy_statistical_analysis/results/overall_delay_rates.pdf",
  width = 7,
  height = 5
)

positions <- barplot(
  overall$DelayPercent,
  names.arg = overall$TimeOfDay,
  col = c("steelblue", "darkorange"),
  ylim = c(0, max(overall$DelayPercent) * 1.25),
  ylab = "Departure delay rate (%)",
  main = "Morning and Evening Departure Delays, 2022-2025",
  sub = "Delay = 15+ minutes; cancelled flights excluded"
)

text(
  x = positions,
  y = overall$DelayPercent,
  labels = sprintf("%.1f%%", overall$DelayPercent),
  pos = 3
)

dev.off()

flights$TimeOfDay <- factor(
  flights$TimeOfDay,
  levels = c("Morning", "Evening")
)
flights$Airline <- factor(flights$Airline)
flights$Season <- factor(
  flights$Season,
  levels = c("Spring", "Summer", "Fall", "Winter")
)
flights$Region <- factor(
  flights$Region,
  levels = c("Midwest", "Northeast", "South", "West")
)
flights$Year <- factor(flights$Year)

flights$NotDelayedFlights <-
  flights$TotalFlights - flights$DelayedFlights

model_main <- glm(
  cbind(DelayedFlights, NotDelayedFlights) ~
    TimeOfDay + Airline + Season + Region + Year,
  family = binomial,
  data = flights
)

print(summary(model_main))
cat("\nConverged:", model_main$converged, "\n")
cat("Aliased coefficients:", sum(is.na(coef(model_main))), "\n")

evening_or <- exp(coef(model_main)["TimeOfDayEvening"])
cat("Adjusted evening/morning odds ratio:", evening_or, "\n")

dispersion <- sum(
  residuals(model_main, type = "pearson")^2
) / df.residual(model_main)

cat("Pearson dispersion:", dispersion, "\n")

capture.output(
  summary(model_main),
  cat("\nConverged:", model_main$converged, "\n"),
  cat("Pearson dispersion:", dispersion, "\n"),
  file = "judy_statistical_analysis/results/main_model_summary.txt"
)

coefficients <- as.data.frame(coef(summary(model_main)))
coefficients$Term <- rownames(coefficients)
rownames(coefficients) <- NULL
coefficients$OddsRatio <- exp(coefficients$Estimate)

write.csv(
  coefficients,
  "judy_statistical_analysis/results/main_model_coefficients.csv",
  row.names = FALSE
)

model_main_quasi <- update(
  model_main,
  family = quasibinomial
)

model_interaction <- glm(
  cbind(DelayedFlights, NotDelayedFlights) ~
    TimeOfDay * (Airline + Season + Region) + Year,
  family = quasibinomial,
  data = flights
)

comparison <- anova(
  model_main_quasi,
  model_interaction,
  test = "F"
)

interaction_tests <- drop1(
  model_interaction,
  test = "F"
)

dispersion_interaction <- sum(
  residuals(model_interaction, type = "pearson")^2
) / df.residual(model_interaction)

cat("\nInteraction model converged:",
    model_interaction$converged, "\n")
cat("Aliased coefficients:",
    sum(is.na(coef(model_interaction))), "\n")
cat("Pearson dispersion:",
    dispersion_interaction, "\n")

print(comparison)
print(interaction_tests)

capture.output(
  summary(model_interaction),
  comparison,
  interaction_tests,
  file = paste0(
    "judy_statistical_analysis/results/",
    "interaction_model_summary.txt"
  )
)

write.csv(
  as.data.frame(interaction_tests),
  paste0(
    "judy_statistical_analysis/results/",
    "interaction_tests.csv"
  ),
  row.names = TRUE
)

model_year <- update(
  model_interaction,
  . ~ . + TimeOfDay:Year
)

year_test <- anova(
  model_interaction,
  model_year,
  test = "F"
)

cat("\nYear interaction model converged:",
    model_year$converged, "\n")
cat("Aliased coefficients:",
    sum(is.na(coef(model_year))), "\n")

print(year_test)

capture.output(
  summary(model_year),
  year_test,
  file = "judy_statistical_analysis/results/year_interaction_summary.txt"
)

write.csv(
  as.data.frame(year_test),
  "judy_statistical_analysis/results/year_interaction_test.csv",
  row.names = FALSE
)

coverage <- with(flights, table(Airline, Year))
common_airlines <- rownames(coverage)[
  rowSums(coverage > 0) == ncol(coverage)
]

reference <- flights[
  flights$Airline %in% common_airlines,
]

reference <- aggregate(
  TotalFlights ~ Airline + Season + Region,
  data = reference,
  FUN = sum
)

weights <- reference$TotalFlights /
  sum(reference$TotalFlights)

adjusted <- expand.grid(
  Year = levels(flights$Year),
  TimeOfDay = levels(flights$TimeOfDay),
  stringsAsFactors = FALSE
)

adjusted$AdjustedDelayPercent <- NA_real_

for (i in seq_len(nrow(adjusted))) {
  newdata <- reference

  newdata$Year <- factor(
    rep(adjusted$Year[i], nrow(newdata)),
    levels = levels(flights$Year)
  )

  newdata$TimeOfDay <- factor(
    rep(adjusted$TimeOfDay[i], nrow(newdata)),
    levels = levels(flights$TimeOfDay)
  )

  probabilities <- predict(
    model_year,
    newdata = newdata,
    type = "response"
  )

  adjusted$AdjustedDelayPercent[i] <-
    100 * sum(weights * probabilities)
}

penalties <- reshape(
  adjusted,
  idvar = "Year",
  timevar = "TimeOfDay",
  direction = "wide"
)

names(penalties) <- c(
  "Year", "MorningPercent", "EveningPercent"
)

penalties$EveningPenaltyPP <-
  penalties$EveningPercent - penalties$MorningPercent

cat("\nCommon airlines:\n")
print(common_airlines)

cat("\nAdjusted probabilities and evening penalties:\n")
print(penalties, row.names = FALSE, digits = 4)

write.csv(
  adjusted,
  "judy_statistical_analysis/results/adjusted_probabilities_by_year.csv",
  row.names = FALSE
)

write.csv(
  penalties,
  "judy_statistical_analysis/results/adjusted_evening_penalty_by_year.csv",
  row.names = FALSE
)

pdf(
  "judy_statistical_analysis/results/adjusted_probabilities_by_year.pdf",
  width = 7,
  height = 5
)

plot(
  as.numeric(as.character(penalties$Year)),
  penalties$MorningPercent,
  type = "b",
  pch = 16,
  col = "steelblue",
  ylim = c(
    0,
    max(penalties$MorningPercent,
        penalties$EveningPercent) * 1.15
  ),
  xaxt = "n",
  xlab = "Year",
  ylab = "Adjusted departure delay probability (%)",
  main = "Adjusted Morning and Evening Delay Probabilities"
)

axis(
  1,
  at = as.numeric(as.character(penalties$Year)),
  labels = penalties$Year
)

lines(
  as.numeric(as.character(penalties$Year)),
  penalties$EveningPercent,
  type = "b",
  pch = 17,
  col = "darkorange"
)

legend(
  "topleft",
  legend = c("Morning", "Evening"),
  col = c("steelblue", "darkorange"),
  pch = c(16, 17),
  lty = 1,
  bty = "n"
)

dev.off()

flights_common <- droplevels(
  flights[flights$Airline %in% common_airlines, ]
)

model_common <- update(
  model_year,
  data = flights_common
)

model_common_no_year_interaction <- update(
  model_common,
  . ~ . - TimeOfDay:Year
)

common_year_test <- anova(
  model_common_no_year_interaction,
  model_common,
  test = "F"
)

penalties_common <- penalties

for (i in seq_len(nrow(adjusted))) {
  newdata <- reference

  newdata$Year <- factor(
    rep(adjusted$Year[i], nrow(newdata)),
    levels = levels(flights$Year)
  )

  newdata$TimeOfDay <- factor(
    rep(adjusted$TimeOfDay[i], nrow(newdata)),
    levels = levels(flights$TimeOfDay)
  )

  probability <- 100 * sum(
    weights * predict(
      model_common,
      newdata = newdata,
      type = "response"
    )
  )

  column <- paste0(adjusted$TimeOfDay[i], "Percent")
  row <- match(adjusted$Year[i], penalties_common$Year)
  penalties_common[row, column] <- probability
}

penalties_common$EveningPenaltyPP <-
  penalties_common$EveningPercent -
  penalties_common$MorningPercent

cat("\nCommon-airline model converged:",
    model_common$converged, "\n")
cat("Aliased coefficients:",
    sum(is.na(coef(model_common))), "\n")

print(common_year_test)
print(penalties_common, row.names = FALSE, digits = 4)

write.csv(
  penalties_common,
  "judy_statistical_analysis/results/common_airline_year_comparison.csv",
  row.names = FALSE
)

capture.output(
  summary(model_common),
  common_year_test,
  penalties_common,
  file = "judy_statistical_analysis/results/common_airline_model_summary.txt"
)

adjusted_comparison <- function(variable, values) {
  output <- data.frame()

  for (value in values) {
    probabilities <- numeric(2)

    for (j in seq_along(levels(flights$TimeOfDay))) {
      newdata <- flights_common

      newdata[[variable]] <- factor(
        rep(value, nrow(newdata)),
        levels = levels(flights[[variable]])
      )

      newdata$TimeOfDay <- factor(
        rep(levels(flights$TimeOfDay)[j], nrow(newdata)),
        levels = levels(flights$TimeOfDay)
      )

      probabilities[j] <- 100 * weighted.mean(
        predict(model_year, newdata = newdata, type = "response"),
        w = flights_common$TotalFlights
      )
    }

    output <- rbind(
      output,
      data.frame(
        Group = value,
        MorningPercent = probabilities[1],
        EveningPercent = probabilities[2],
        EveningPenaltyPP = probabilities[2] - probabilities[1]
      )
    )
  }

  output
}

comparisons <- list(
  Airline = adjusted_comparison("Airline", common_airlines),
  Season = adjusted_comparison(
    "Season", levels(flights$Season)
  ),
  Region = adjusted_comparison(
    "Region", levels(flights$Region)
  )
)

for (variable in names(comparisons)) {
  result <- comparisons[[variable]]

  cat("\nAdjusted comparison:", variable, "\n")
  print(result, row.names = FALSE, digits = 4)

  write.csv(
    result,
    paste0(
      "judy_statistical_analysis/results/adjusted_",
      tolower(variable), "_comparison.csv"
    ),
    row.names = FALSE
  )

  display <- result[
    order(result$EveningPenaltyPP),
  ]

  pdf(
    paste0(
      "judy_statistical_analysis/results/adjusted_",
      tolower(variable), "_penalty.pdf"
    ),
    width = 8,
    height = if (variable == "Airline") 7 else 5
  )

  par(mar = c(5, 7, 4, 2))

  barplot(
    display$EveningPenaltyPP,
    names.arg = display$Group,
    horiz = TRUE,
    las = 1,
    col = "steelblue",
    xlim = range(c(0, display$EveningPenaltyPP)) +
      c(-1, 2),
    xlab = "Adjusted evening penalty (percentage points)",
    main = paste("Evening Penalty by", variable)
  )

  abline(v = 0, col = "gray50")
  dev.off()
}

final_dispersion <- sum(
  residuals(model_year, type = "pearson")^2
) / df.residual(model_year)

diagnostics <- data.frame(
  Model = "Quasibinomial with time-of-day interactions",
  Groups = nobs(model_year),
  Converged = model_year$converged,
  AliasedCoefficients = sum(is.na(coef(model_year))),
  PearsonDispersion = final_dispersion
)

final_coefficients <- data.frame(
  Term = rownames(coef(summary(model_year))),
  coef(summary(model_year)),
  row.names = NULL,
  check.names = FALSE
)

final_coefficients$OddsRatio <-
  exp(final_coefficients$Estimate)

final_tests <- drop1(model_year, test = "F")

write.csv(
  diagnostics,
  "judy_statistical_analysis/results/final_model_diagnostics.csv",
  row.names = FALSE
)

write.csv(
  final_coefficients,
  "judy_statistical_analysis/results/final_model_coefficients.csv",
  row.names = FALSE
)

write.csv(
  as.data.frame(final_tests),
  "judy_statistical_analysis/results/final_model_tests.csv",
  row.names = TRUE
)

capture.output(
  summary(model_year),
  diagnostics,
  final_tests,
  file = "judy_statistical_analysis/results/final_model_summary.txt"
)

cat("\nFinal model diagnostics:\n")
print(diagnostics, row.names = FALSE)
print(final_tests)
