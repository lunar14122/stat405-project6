# Judy: Overall Comparison and Statistical Modeling

## Research question

How do morning and evening departure-delay rates differ after
adjusting for airline, season, origin region, and year?

## Data

Input: ../summary-2022-2025.csv, produced by the group's data
processing workflow.

The input contains 1,781 groups representing 16,665,904 included
flights from 2022 through 2025.

Each row groups flights by Year, Airline, Season, Region, and
TimeOfDay, with TotalFlights and DelayedFlights.

Morning: scheduled local departure from 06:00 through 11:59.
Evening: scheduled local departure from 18:00 through 23:59.
Delay: departure at least 15 minutes after schedule.
Cancelled flights and records without usable delay information
are excluded. Origins outside the mapped states and DC are excluded.

Source:
https://www.transtats.bts.gov/Fields.asp?gnoyr_VQ=FGJ

## Run

Requires R and Bash. No additional R packages are required.

From the repository root:

```bash
bash judy_statistical_analysis/run_analysis.sh
cat > judy_statistical_analysis/README.md <<'EOF'
# Judy: Overall Comparison and Statistical Modeling

## Research Question

How do morning and evening departure-delay rates differ after
accounting for airline, season, region, and year?

## Data

The analysis uses summary-2022-2025.csv from the repository root,
which contains 1,781 groups representing 16,665,904 included flights
from 2022 through 2025. Each row contains the total and delayed-flight
counts for one combination of year, airline, season, region, and
time of day.

Morning flights have scheduled local departure times from 06:00
through 11:59, while evening flights depart between 18:00 and 23:59.
A flight is classified as delayed when its departure is at least
15 minutes behind schedule.

The analysis excludes cancelled flights, records without usable
delay information, and flights departing outside the 50 states
and Washington, DC.

BTS variable definitions:
https://www.transtats.bts.gov/Fields.asp?gnoyr_VQ=FGJ

## Running the Analysis

The analysis requires R and Bash, with no additional R packages.
Run the following command from the repository root:

```bash
bash judy_statistical_analysis/run_analysis.sh
```

The script saves tables, figures, and model output in
judy_statistical_analysis/results/ and replaces previous results
each time it runs.

## Methods

We calculate morning and evening delay rates by dividing the total
number of delayed flights by the total number of flights in each
time period. The evening penalty is the evening rate minus the
morning rate, measured in percentage points.

We fit a grouped logistic regression using delayed and non-delayed
flight counts, with airline, season, region, year, and time of day
as predictors. Interactions between time of day and each other
factor allow the morning-evening difference to vary across groups.

Because the data show more variation than the binomial model allows,
we use a quasibinomial model and approximate F tests to assess
the interactions.

We calculate adjusted probabilities using the same flight-weighted
reference population from the 14 airlines represented in all four
years. For each comparison, we change the factor being examined
while keeping the other reference characteristics the same.

We also refit the model using only these 14 airlines to check
whether changes in airline coverage affect the findings.

## Results

The overall delay rate is 13.08% for morning flights and 30.81%
for evening flights, giving an evening penalty of 17.73 percentage
points before adjustment.

After adjustment, the evening penalties are 16.99 percentage points
in 2022, 16.57 in 2023, 17.16 in 2024, and 18.78 in 2025. Restricting
the model to airlines represented in every year produces similar
estimates.

Southwest (WN), summer, and the Northeast have the largest adjusted
evening penalties within their respective comparisons, although
these rankings do not establish significant differences between
individual groups.

## Files

- analysis.R contains the data checks, statistical analysis, and plots.
- run_analysis.sh runs the analysis and saves its output.
- results/ contains the generated tables, figures, and model results.
- results/final_model_summary.txt contains the final quasibinomial model.
- results/final_model_coefficients.csv contains its coefficient estimates.
- results/final_model_diagnostics.csv contains its diagnostic summary.
- results/final_model_tests.csv contains the final interaction tests.
- results/main_model_* files describe the initial binomial model.
- results/common_airline_* files contain the sensitivity analysis.
- results/analysis_output.txt contains the complete console output.
- results/session_info.txt records the R environment used.

## Limitations

The results describe associations rather than causal effects.
Substantial unexplained variation remains, and although the
quasibinomial model adjusts standard errors for extra variation,
it does not directly model dependence among flights.

The grouped data do not retain flight dates, airports, routes,
or weather, so the analysis cannot adjust for these factors.
Some adjusted comparisons also involve combinations with little
or no observed data, particularly when comparing airlines
across regions.

The figures show point estimates without confidence intervals.
Odds ratios should not be interpreted as ratios of delay
probabilities, and coefficients involving interactions must
be interpreted in relation to their reference categories.
