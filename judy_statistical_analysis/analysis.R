flights <- read.csv("summary-2022-2025.csv")
out <- "judy_statistical_analysis/results"
dir.create(out, recursive = TRUE, showWarnings = FALSE)

keys <- c("Year", "Airline", "Season", "Region", "TimeOfDay")
required <- c(keys, "TotalFlights", "DelayedFlights", "DelayRate")
stopifnot(all(required %in% names(flights)), nrow(flights) > 0)
stopifnot(!anyNA(flights[required]), !anyDuplicated(flights[keys]))
stopifnot(all(flights$TotalFlights > 0))
stopifnot(all(flights$TotalFlights == floor(flights$TotalFlights)))
stopifnot(all(flights$DelayedFlights == floor(flights$DelayedFlights)))
stopifnot(all(flights$DelayedFlights >= 0))
stopifnot(all(flights$DelayedFlights <= flights$TotalFlights))
stopifnot(all(flights$TimeOfDay %in% c("Morning", "Evening")))
stopifnot(max(abs(flights$DelayRate - flights$DelayedFlights / flights$TotalFlights)) < 1e-10)

flights$TimeOfDay <- factor(flights$TimeOfDay, levels = c("Morning", "Evening"))
flights$Airline <- factor(flights$Airline)
flights$Season <- factor(flights$Season, levels = c("Spring", "Summer", "Fall", "Winter"))
flights$Region <- factor(flights$Region, levels = c("Midwest", "Northeast", "South", "West"))
flights$Year <- factor(flights$Year)
stopifnot(!anyNA(flights[keys]))
flights$NotDelayedFlights <- flights$TotalFlights - flights$DelayedFlights

overall <- aggregate(cbind(TotalFlights, DelayedFlights) ~ TimeOfDay, flights, sum)
overall <- overall[match(c("Morning", "Evening"), overall$TimeOfDay), ]
overall$DelayRate <- overall$DelayedFlights / overall$TotalFlights
overall$DelayPercent <- 100 * overall$DelayRate
write.csv(overall, file.path(out, "overall_delay_rates.csv"), row.names = FALSE)

cat("Groups:", nrow(flights), "\nIncluded flights:", sum(flights$TotalFlights), "\n")
print(overall, row.names = FALSE)
cat("Overall evening penalty:", diff(overall$DelayPercent), "percentage points\n")

pdf(file.path(out, "overall_delay_rates.pdf"), width = 7, height = 5)
bars <- barplot(overall$DelayPercent, names.arg = overall$TimeOfDay,
                col = c("steelblue", "darkorange"), ylim = c(0, max(overall$DelayPercent) * 1.25),
                ylab = "Departure delay rate (%)", main = "Morning and Evening Delays, 2022-2025",
                sub = "Delay = 15+ minutes; cancelled flights excluded")
text(bars, overall$DelayPercent, labels = sprintf("%.1f%%", overall$DelayPercent), pos = 3)
dev.off()

model_main <- glm(
  cbind(DelayedFlights, NotDelayedFlights) ~ TimeOfDay + Airline + Season + Region + Year,
  family = binomial, data = flights
)
model_main_quasi <- update(model_main, family = quasibinomial)
model_interaction <- update(model_main_quasi, . ~ . + TimeOfDay:(Airline + Season + Region))
model_year <- update(model_interaction, . ~ . + TimeOfDay:Year)

comparison <- anova(model_main_quasi, model_interaction, test = "F")
interaction_tests <- drop1(model_interaction, test = "F")
year_test <- anova(model_interaction, model_year, test = "F")
final_tests <- drop1(model_year, test = "F")

models <- list(main_model = model_main, interaction_model = model_interaction,
               year_interaction = model_year, final_model = model_year)

for (name in names(models)) {
  capture.output(summary(models[[name]]), file = file.path(out, paste0(name, "_summary.txt")))
}

for (name in c("main_model", "final_model")) {
  table <- as.data.frame(coef(summary(models[[name]])))
  table$Term <- rownames(table)
  table$OddsRatio <- exp(table$Estimate)
  write.csv(table, file.path(out, paste0(name, "_coefficients.csv")), row.names = FALSE)
}

write.csv(as.data.frame(interaction_tests), file.path(out, "interaction_tests.csv"))
write.csv(as.data.frame(year_test), file.path(out, "year_interaction_test.csv"), row.names = FALSE)
write.csv(as.data.frame(final_tests), file.path(out, "final_model_tests.csv"))
capture.output(summary(model_interaction), comparison, interaction_tests,
               file = file.path(out, "interaction_model_summary.txt"))
capture.output(summary(model_year), year_test,
               file = file.path(out, "year_interaction_summary.txt"))

dispersion <- sum(residuals(model_year, type = "pearson")^2) / df.residual(model_year)
diagnostics <- data.frame(
  Groups = nobs(model_year), Converged = model_year$converged,
  AliasedCoefficients = sum(is.na(coef(model_year))), PearsonDispersion = dispersion
)
stopifnot(model_year$converged, !anyNA(coef(model_year)))
write.csv(diagnostics, file.path(out, "final_model_diagnostics.csv"), row.names = FALSE)
capture.output(summary(model_year), diagnostics, final_tests,
               file = file.path(out, "final_model_summary.txt"))

coverage <- with(flights, table(Airline, Year))
common_airlines <- rownames(coverage)[rowSums(coverage > 0) == ncol(coverage)]
flights_common <- droplevels(flights[flights$Airline %in% common_airlines, ])

model_common <- update(model_year, data = flights_common)
model_common_no_year <- update(model_common, . ~ . - TimeOfDay:Year)
common_year_test <- anova(model_common_no_year, model_common, test = "F")
stopifnot(model_common$converged, !anyNA(coef(model_common)))

adjusted_rates <- function(model, variable, values) {
  result <- data.frame(Group = as.character(values), MorningPercent = NA_real_,
                       EveningPercent = NA_real_, EveningPenaltyPP = NA_real_)
  for (i in seq_along(values)) {
    for (time in c("Morning", "Evening")) {
      newdata <- flights_common
      newdata[[variable]] <- factor(rep(values[i], nrow(newdata)),
                                    levels = levels(flights[[variable]]))
      newdata$TimeOfDay <- factor(rep(time, nrow(newdata)), levels = c("Morning", "Evening"))
      probability <- predict(model, newdata, type = "response")
      result[i, paste0(time, "Percent")] <- 100 * weighted.mean(probability, newdata$TotalFlights)
    }
  }
  result$EveningPenaltyPP <- result$EveningPercent - result$MorningPercent
  result
}

penalties <- adjusted_rates(model_year, "Year", levels(flights$Year))
names(penalties)[1] <- "Year"
penalties_common <- adjusted_rates(model_common, "Year", levels(flights$Year))
names(penalties_common)[1] <- "Year"

adjusted <- data.frame(
  Year = rep(penalties$Year, 2),
  TimeOfDay = rep(c("Morning", "Evening"), each = nrow(penalties)),
  AdjustedDelayPercent = c(penalties$MorningPercent, penalties$EveningPercent)
)

write.csv(adjusted, file.path(out, "adjusted_probabilities_by_year.csv"), row.names = FALSE)
write.csv(penalties, file.path(out, "adjusted_evening_penalty_by_year.csv"), row.names = FALSE)
write.csv(penalties_common, file.path(out, "common_airline_year_comparison.csv"), row.names = FALSE)
capture.output(summary(model_common), common_year_test, penalties_common,
               file = file.path(out, "common_airline_model_summary.txt"))

pdf(file.path(out, "adjusted_probabilities_by_year.pdf"), width = 7, height = 5)
years <- as.numeric(penalties$Year)
plot(years, penalties$MorningPercent, type = "b", pch = 16, col = "steelblue",
     ylim = c(0, max(penalties$EveningPercent, penalties$MorningPercent) * 1.15),
     xaxt = "n", xlab = "Year", ylab = "Adjusted delay probability (%)",
     main = "Adjusted Morning and Evening Delay Probabilities")
axis(1, at = years, labels = penalties$Year)
lines(years, penalties$EveningPercent, type = "b", pch = 17, col = "darkorange")
legend("topleft", c("Morning", "Evening"), col = c("steelblue", "darkorange"),
       pch = c(16, 17), lty = 1, bty = "n")
dev.off()

comparisons <- list(
  Airline = adjusted_rates(model_year, "Airline", common_airlines),
  Season = adjusted_rates(model_year, "Season", levels(flights$Season)),
  Region = adjusted_rates(model_year, "Region", levels(flights$Region))
)

for (variable in names(comparisons)) {
  result <- comparisons[[variable]]
  write.csv(result, file.path(out, paste0("adjusted_", tolower(variable), "_comparison.csv")),
            row.names = FALSE)
  display <- result[order(result$EveningPenaltyPP), ]
  pdf(file.path(out, paste0("adjusted_", tolower(variable), "_penalty.pdf")),
      width = 8, height = if (variable == "Airline") 7 else 5)
  par(mar = c(5, 7, 4, 2))
  bars <- barplot(display$EveningPenaltyPP, names.arg = display$Group, horiz = TRUE,
                  las = 1, col = "steelblue", xlim = range(c(0, display$EveningPenaltyPP)) + c(-1, 3),
                  xlab = "Adjusted evening penalty (percentage points)",
                  main = paste("Evening Penalty by", variable))
  text(display$EveningPenaltyPP, bars, labels = sprintf("%.1f", display$EveningPenaltyPP), pos = 4)
  abline(v = 0, col = "gray50")
  dev.off()
  cat("\nAdjusted comparison:", variable, "\n")
  print(result, row.names = FALSE, digits = 4)
}

cat("\nAdjusted annual comparison:\n")
print(penalties, row.names = FALSE, digits = 4)
cat("\nCommon-airline annual comparison:\n")
print(penalties_common, row.names = FALSE, digits = 4)
print(common_year_test)
cat("\nFinal model diagnostics:\n")
print(diagnostics, row.names = FALSE)
print(final_tests)
