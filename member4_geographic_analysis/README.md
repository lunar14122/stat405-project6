# Member 4 — Geographic Analysis

**Research question:** Does the evening flight delay penalty vary across U.S. geographic regions? How does the regional pattern vary by season?

Read [RESULTS.md](RESULTS.md) for calculated findings, English explanations, Chinese takeaways, and the figures. This folder uses the team's existing data and does not download or modify raw flight records.

## Reproduce

Run from the repository root with Python 3.12 or newer:

```bash
python3 -m venv member4_geographic_analysis/.venv
source member4_geographic_analysis/.venv/bin/activate
python -m pip install -r member4_geographic_analysis/requirements.txt
python member4_geographic_analysis/analyze_geography.py
python -m unittest discover -s member4_geographic_analysis -p 'test_*.py' -v
```

On Windows, activate `member4_geographic_analysis\.venv\Scripts\activate` instead. The default input and output paths are relative to the script, so running it from another working directory also works.

Optional paths:

```bash
python member4_geographic_analysis/analyze_geography.py \
  --input summary-2022-2025.csv \
  --output-dir member4_geographic_analysis
```

The script regenerates its named plots, tables, audit, and `RESULTS.md`. `README.md` is maintained separately. Dependencies are pinned to the versions used to produce the checked-in results. Plot rendering is noninteractive and needs no display or network connection after installation.

## Input and definitions

- Input: [`../summary-2022-2025.csv`](../summary-2022-2025.csv), supplied at repository commit `9f98c68`. Its SHA-256 is recorded in `tables/data_audit.json`.
- Each row represents a **Year × Airline × Season × Region × TimeOfDay** aggregate, not one flight.
- Region is assigned upstream using the departure airport's `OriginState`. The mapping below matches [`../getandclean.sh`](../getandclean.sh) and the [U.S. Census Bureau regions](https://www.census.gov/programs-surveys/economic-census/guidance-geographies/levels.html). The input no longer contains states, so this script uses its existing `Region` column; the exported state lookup documents the upstream mapping.
- Morning: scheduled departure 06:00–11:59. Evening: scheduled departure 18:00–23:59. These use `CRSDepTime`, not actual departure time. [BTS reporting instructions](https://www.bts.gov/explore-topics-and-geography/modes/aviation/number-39-technical-directive-reporting-time) specify local time.
- Delayed: `DepDel15 = 1`, with an upstream fallback to `DepDelay >= 15` when needed.
- The upstream script excludes cancelled flights, unrecognized origin states, other time windows, and flights without usable delay information. It does not separately exclude diverted flights when departure-delay data are available.
- Spring = March–May; Summer = June–August; Fall = September–November; Winter = December–February. The `Year` is the calendar year, including for winter.
- All reporting airlines in the supplied summary are included. There is no additional major-airline filter in this geographic analysis.

| Region | Origin-state abbreviations |
|---|---|
| Northeast | CT ME MA NH RI VT NJ NY PA |
| Midwest | IL IN MI OH WI IA KS MN MO NE ND SD |
| South | DE DC FL GA MD NC SC VA WV AL KY MS TN AR LA OK TX |
| West | AZ CO ID MT NV NM UT WY AK CA HI OR WA |

Alaska and Hawaii are in West; DC is in South. Origins outside these 50 states and DC, including U.S. territories, were excluded upstream.

## Calculation

For each region and time period, sum counts across the relevant airlines, years, and seasons before dividing:

```text
DelayRate = sum(DelayedFlights) / sum(TotalFlights)
DelayRatePct = 100 × DelayRate
EveningPenaltyPP = EveningDelayRatePct − MorningDelayRatePct
```

Do **not** take an unweighted mean of the original `DelayRate` column. A group with 100 flights must not receive the same weight as a group with 100,000 flights. Percentage points also differ from relative percentage increases: 30% − 10% is a 20 pp penalty.

The script validates required columns, integer counts, count bounds, labels, unique aggregate keys, stored rates, paired morning/evening data, and all 128 Year × Region × Season × TimeOfDay combinations. It also checks count conservation at each aggregation level. It does not invent missing airline cells or treat missing observations as zero.

## Deliverables

| File | Purpose |
|---|---|
| `analyze_geography.py` | Full reproducible analysis and plotting code |
| `test_geography.py` | Checks weighting, penalty units, invalid input handling, and independent source reconciliation |
| `plots/01_regional_delay_rates.*` | Morning and evening delay rates in four regions |
| `plots/02_regional_evening_penalty.*` | Regional evening penalty ranking |
| `plots/03_region_season_delay_rates.*` | Morning/evening seasonal profiles within each region |
| `plots/04_region_season_penalty_heatmap.*` | Region × Season evening penalties |
| `plots/05_regional_penalty_by_year.*` | Descriptive annual consistency check |
| `tables/*_delay_rates.csv` | Aggregated counts and rates for region, region-season, and region-year |
| `tables/*_penalties.csv` | Paired counts, rates, and evening penalties at the same three levels |
| `tables/state_region_mapping.csv` | Documented upstream state-to-region lookup |
| `tables/data_audit.json` | Input fingerprint, totals, coverage checks, and package versions |
| `RESULTS.md` | Generated findings with embedded figures |

Every figure is saved as a high-resolution PNG for slides and an SVG for scalable editing. CSV rates ending in `Pct` are on a 0–100 scale; `DelayRate` is on a 0–1 scale. `EveningPenaltyPP` is a difference in percentage points. Counts are retained so teammates can verify the denominators.

## Scope and limitations

These are **descriptive, unadjusted comparisons**. The plots show effect sizes, not statistical significance. No causal effect or weather mechanism is established. Counts are not independent samples when flights share airport/day/weather conditions; the current summaries cannot support cluster-aware uncertainty estimates. Member 5 handles adjusted modeling.

The [48-row month manifest](../flight_months.txt) and [merge script](../merge_summaries.py) describe the intended 2022–2025 coverage. Because the supplied summary has no month or flight identifiers, monthly completeness, raw-flight deduplication, and upstream state assignments cannot be independently verified here. The checked-in audit refers only to checks possible on this aggregate file.
