#!/usr/bin/env python3
"""Reproduce Member 4 tables, figures, and findings from the shared BTS summary."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

# Run without a display and keep Matplotlib's cache outside the repository.
os.environ.setdefault("MPLCONFIGDIR", str(Path(tempfile.gettempdir()) / "stat405-mpl"))
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import PercentFormatter
import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
REGIONS = ["Northeast", "Midwest", "South", "West"]
SEASONS = ["Spring", "Summer", "Fall", "Winter"]
YEARS = [2022, 2023, 2024, 2025]
TIMES = ["Morning", "Evening"]
KEYS = ["Year", "Airline", "Season", "Region", "TimeOfDay"]
COUNTS = ["TotalFlights", "DelayedFlights"]
REGION_STATES = {
    "Northeast": "CT ME MA NH RI VT NJ NY PA",
    "Midwest": "IL IN MI OH WI IA KS MN MO NE ND SD",
    "South": "DE DC FL GA MD NC SC VA WV AL KY MS TN AR LA OK TX",
    "West": "AZ CO ID MT NV NM UT WY AK CA HI OR WA",
}
TIME_COLORS = {"Morning": "#246A90", "Evening": "#C66A28"}
REGION_COLORS = dict(zip(REGIONS, ["#7865A7", "#246A90", "#C66A28", "#238270"]))
FOOTNOTE = (
    "Source: shared BTS summary, 2022–2025. Noncancelled flights with valid departure-delay data.\n"
    "Scheduled local time: morning 06:00–11:59; evening 18:00–23:59. Delay = 15+ minutes."
)


def load_data(path):
    """Reject inconsistent counts, duplicate aggregate keys, or missing coverage."""
    df = pd.read_csv(path)
    missing = set(KEYS + COUNTS + ["DelayRate"]) - set(df.columns)
    if missing:
        raise ValueError(f"Missing columns: {sorted(missing)}")
    if df.empty or df[KEYS + COUNTS + ["DelayRate"]].isna().any().any():
        raise ValueError("Input is empty or contains missing required values.")
    for col in ["Airline", "Season", "Region", "TimeOfDay"]:
        df[col] = df[col].astype(str).str.strip()
        if df[col].eq("").any():
            raise ValueError(f"Empty label in {col}.")
    for col in ["Year"] + COUNTS:
        values = pd.to_numeric(df[col], errors="raise")
        if not np.isfinite(values).all() or not (values % 1 == 0).all():
            raise ValueError(f"{col} must contain finite integers.")
        df[col] = values.astype("int64")
    if (df.TotalFlights <= 0).any() or (df.DelayedFlights < 0).any():
        raise ValueError("TotalFlights must be positive; DelayedFlights cannot be negative.")
    if (df.DelayedFlights > df.TotalFlights).any():
        raise ValueError("DelayedFlights exceeds TotalFlights.")
    if df.duplicated(KEYS).any():
        raise ValueError("Duplicate aggregate keys would double-count flights.")
    for col, expected in [("Year", YEARS), ("Region", REGIONS),
                          ("Season", SEASONS), ("TimeOfDay", TIMES)]:
        if set(df[col]) != set(expected):
            raise ValueError(f"{col} must contain exactly {expected}.")
    rate = pd.to_numeric(df.DelayRate, errors="raise")
    if not np.allclose(rate, df.DelayedFlights / df.TotalFlights, rtol=0, atol=1e-8):
        raise ValueError("Stored DelayRate disagrees with the flight counts.")
    coverage_keys = ["Year", "Region", "Season", "TimeOfDay"]
    expected = pd.MultiIndex.from_product([YEARS, REGIONS, SEASONS, TIMES], names=coverage_keys)
    observed = pd.MultiIndex.from_frame(df[coverage_keys].drop_duplicates())
    if len(expected.difference(observed)):
        raise ValueError("Missing Year × Region × Season × TimeOfDay coverage.")
    return df


def aggregate_rates(df, groups):
    """Weight every flight equally by summing numerators and denominators first."""
    result = df.groupby(groups + ["TimeOfDay"], as_index=False, sort=True)[COUNTS].sum()
    result["DelayRate"] = result.DelayedFlights / result.TotalFlights
    result["DelayRatePct"] = 100 * result.DelayRate
    # All three output resolutions must conserve the input counts.
    if not result[COUNTS].sum().equals(df[COUNTS].sum()):
        raise ValueError("Aggregation did not conserve flight counts.")
    return result


def calculate_penalties(rates, groups):
    """Percentage-point difference, not relative percent change or delay minutes."""
    wide = rates.pivot(index=groups, columns="TimeOfDay", values=COUNTS + ["DelayRatePct"])
    if wide.isna().any().any() or set(wide.columns.get_level_values(1)) != set(TIMES):
        raise ValueError("Each comparison needs both morning and evening observations.")
    out = pd.DataFrame(index=wide.index)
    for time in TIMES:
        out[f"{time}Flights"] = wide[("TotalFlights", time)].astype("int64")
        out[f"{time}DelayedFlights"] = wide[("DelayedFlights", time)].astype("int64")
        out[f"{time}DelayRatePct"] = wide[("DelayRatePct", time)]
    out["EveningPenaltyPP"] = out.EveningDelayRatePct - out.MorningDelayRatePct
    return out.reset_index()


def finish_figure(fig, stem, output):
    fig.text(0.08, 0.025, FOOTNOTE, fontsize=8, color="#52616B", va="bottom")
    for suffix in ["png", "svg"]:
        path = output / f"{stem}.{suffix}"
        fig.savefig(path, dpi=220, facecolor="white",
                    metadata={"Date": None} if suffix == "svg" else None)
        if suffix == "svg":
            # Matplotlib emits trailing spaces in SVG paths; normalize for Git.
            path.write_text("\n".join(line.rstrip() for line in path.read_text(encoding="utf-8").splitlines())
                            + "\n", encoding="utf-8")
    plt.close(fig)


def plot_results(regional, seasonal, annual, output):
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 11,
        "axes.titlesize": 15, "axes.titleweight": "bold",
        "axes.spines.top": False, "axes.spines.right": False,
        "axes.labelcolor": "#253544", "text.color": "#253544",
        "axes.axisbelow": True, "svg.hashsalt": "stat405-member4",
    })
    regional = regional.set_index("Region").loc[REGIONS]
    x = np.arange(len(REGIONS))
    fig, ax = plt.subplots(figsize=(10, 6.2))
    fig.subplots_adjust(left=.10, right=.96, bottom=.20, top=.86)
    for offset, time in [(-.19, "Morning"), (.19, "Evening")]:
        bars = ax.bar(x + offset, regional[f"{time}DelayRatePct"], .35,
                      label=time, color=TIME_COLORS[time])
        ax.bar_label(bars, fmt="%.2f%%", padding=4, fontsize=10)
    ax.set(xticks=x, xticklabels=REGIONS, ylabel="Departure delay rate",
           title="Morning and evening departure delays by region", ylim=(0, 42))
    ax.yaxis.set_major_formatter(PercentFormatter(100))
    ax.grid(axis="y", alpha=.18)
    ax.legend(frameon=False, ncols=2, loc="upper left")
    finish_figure(fig, "01_regional_delay_rates", output)

    ranked = regional.sort_values("EveningPenaltyPP", ascending=False)
    fig, ax = plt.subplots(figsize=(10, 5.8))
    fig.subplots_adjust(left=.16, right=.96, bottom=.22, top=.84)
    bars = ax.barh(ranked.index, ranked.EveningPenaltyPP,
                   color=[REGION_COLORS[r] for r in ranked.index], height=.58)
    ax.invert_yaxis()
    ax.bar_label(bars, fmt="%.2f pp", padding=8)
    ax.set(xlabel="Evening − morning delay rate (percentage points)",
           title="Evening delay penalty by region", xlim=(0, 25))
    ax.grid(axis="x", alpha=.18)
    finish_figure(fig, "02_regional_evening_penalty", output)

    fig, axes = plt.subplots(2, 2, figsize=(12, 9), sharex=True, sharey=True)
    fig.subplots_adjust(left=.09, right=.97, bottom=.18, top=.83, hspace=.30, wspace=.13)
    fig.suptitle("Morning and evening delay rates across seasons", fontsize=18, fontweight="bold", y=.96)
    for ax, region in zip(axes.flat, REGIONS):
        data = seasonal[seasonal.Region.eq(region)].set_index("Season").loc[SEASONS]
        for time in TIMES:
            ax.plot(SEASONS, data[f"{time}DelayRatePct"], marker="o", linewidth=2.3,
                    color=TIME_COLORS[time], label=time)
        ax.set(title=region, ylim=(0, 50))
        ax.yaxis.set_major_formatter(PercentFormatter(100))
        ax.grid(axis="y", alpha=.18)
        ax.tick_params(labelbottom=True)
    for ax in axes[:, 0]:
        ax.set_ylabel("Departure delay rate")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", bbox_to_anchor=(.5, .915), ncols=2, frameon=False)
    finish_figure(fig, "03_region_season_delay_rates", output)

    matrix = seasonal.pivot(index="Region", columns="Season", values="EveningPenaltyPP").loc[REGIONS, SEASONS]
    fig, ax = plt.subplots(figsize=(10, 6.4))
    fig.subplots_adjust(left=.16, right=.87, bottom=.20, top=.85)
    # Fixed zero baseline makes magnitude comparisons across cells honest.
    heat = ax.imshow(matrix, cmap="YlOrRd", vmin=0, vmax=35, aspect="auto")
    ax.set(xticks=range(4), xticklabels=SEASONS, yticks=range(4), yticklabels=REGIONS,
           title="Evening delay penalty by region and season")
    for row in range(4):
        for col in range(4):
            value = matrix.iloc[row, col]
            ax.text(col, row, f"{value:.2f} pp", ha="center", va="center", fontsize=13,
                    fontweight="bold", color="white" if value > 22 else "#253544")
    colorbar = fig.colorbar(heat, ax=ax, fraction=.046, pad=.05)
    colorbar.set_label("Evening − morning (percentage points)")
    finish_figure(fig, "04_region_season_penalty_heatmap", output)

    fig, ax = plt.subplots(figsize=(10, 6.3))
    fig.subplots_adjust(left=.10, right=.96, bottom=.20, top=.85)
    for region in REGIONS:
        data = annual[annual.Region.eq(region)].set_index("Year").loc[YEARS]
        ax.plot(YEARS, data.EveningPenaltyPP, marker="o", linewidth=2.2,
                label=region, color=REGION_COLORS[region])
    upper = np.ceil(annual.EveningPenaltyPP.max() / 5) * 5 + 5
    ax.set(xticks=YEARS, xlabel="Calendar year", ylim=(0, upper),
           ylabel="Evening − morning (percentage points)",
           title="Regional evening delay penalties, 2022–2025")
    ax.grid(axis="y", alpha=.18)
    ax.legend(frameon=False, ncols=2, loc="upper left")
    finish_figure(fig, "05_regional_penalty_by_year", output)


def write_findings(regional, seasonal, annual, df, output):
    ranked = regional.sort_values("EveningPenaltyPP", ascending=False)
    largest, smallest = ranked.iloc[0], ranked.iloc[-1]
    peak = seasonal.loc[seasonal.EveningPenaltyPP.idxmax()]
    low = seasonal.loc[seasonal.EveningPenaltyPP.idxmin()]
    rows = ["| Region | Morning flights | Evening flights | Morning delay rate | Evening delay rate | Evening penalty |",
            "|---|---:|---:|---:|---:|---:|"]
    for r in ranked.itertuples():
        rows.append(f"| {r.Region} | {r.MorningFlights:,} | {r.EveningFlights:,} | "
                    f"{r.MorningDelayRatePct:.2f}% | {r.EveningDelayRatePct:.2f}% | {r.EveningPenaltyPP:.2f} pp |")
    matrix = seasonal.pivot(index="Region", columns="Season", values="EveningPenaltyPP").loc[REGIONS, SEASONS]
    seasonal_rows = ["| Region | Spring | Summer | Fall | Winter |", "|---|---:|---:|---:|---:|"]
    for region, values in matrix.iterrows():
        seasonal_rows.append("| " + region + " | " + " | ".join(f"{v:.2f}" for v in values) + " |")
    seasonal_peaks = seasonal.loc[seasonal.groupby("Region").EveningPenaltyPP.idxmax()]
    all_summer = seasonal_peaks.Season.eq("Summer").all()
    annual_rows = []
    for region in REGIONS:
        values = annual.loc[annual.Region.eq(region), "EveningPenaltyPP"]
        annual_rows.append(f"- {region}: {values.min():.2f}–{values.max():.2f} percentage points across the four years.")
    text = f"""# Member 4 — Geographic analysis results

## Research question

Does the evening flight delay penalty vary across U.S. geographic regions, and how does the pattern change across seasons?

## Regional comparison

The shared dataset contains {int(df.TotalFlights.sum()):,} eligible flights in {len(df):,} aggregate rows for 2022–2025. Rates pool the reporting airlines and years using flight counts as weights. The evening penalty is the evening delay rate minus the morning delay rate, measured in **percentage points (pp)**.

{chr(10).join(rows)}

The evening rate exceeds the morning rate in {int((regional.EveningPenaltyPP > 0).sum())} of the four regions. {largest.Region} has the largest pooled penalty ({largest.EveningPenaltyPP:.2f} pp), and {smallest.Region} has the smallest ({smallest.EveningPenaltyPP:.2f} pp), a difference of {largest.EveningPenaltyPP - smallest.EveningPenaltyPP:.2f} pp. The two highest penalties, {ranked.iloc[0].Region} and {ranked.iloc[1].Region}, differ by only {ranked.iloc[0].EveningPenaltyPP - ranked.iloc[1].EveningPenaltyPP:.2f} pp, so they should be described as similar in magnitude rather than as a strong ranking distinction.

![Regional rates](plots/01_regional_delay_rates.png)

![Regional penalty ranking](plots/02_regional_evening_penalty.png)

## Region × season

Each cell below is an evening-minus-morning difference in percentage points, with all four calendar years pooled.

{chr(10).join(seasonal_rows)}

{"Summer has the largest evening penalty in every region." if all_summer else "The season with the largest evening penalty differs across regions."} The largest region–season penalty is {peak.Region} in {peak.Season} ({peak.EveningPenaltyPP:.2f} pp; morning {peak.MorningDelayRatePct:.2f}%, evening {peak.EveningDelayRatePct:.2f}%). The smallest is {low.Region} in {low.Season} ({low.EveningPenaltyPP:.2f} pp). Evening rates exceed morning rates in {int((seasonal.EveningPenaltyPP > 0).sum())} of the 16 region–season combinations.

![Seasonal morning and evening rates](plots/03_region_season_delay_rates.png)

![Region-season penalties](plots/04_region_season_penalty_heatmap.png)

## Annual descriptive check

Evening penalties are positive in {int((annual.EveningPenaltyPP > 0).sum())} of the 16 region–year combinations. Their magnitudes vary:

{chr(10).join(annual_rows)}

![Yearly regional penalties](plots/05_regional_penalty_by_year.png)

These are separate annual summaries, not a regression that controls for year.

## Interpretation and limits

The results show a geographic association in the observed morning–evening difference. The wider summer gaps motivate further investigation of weather, traffic volume, and disruptions carried forward from earlier flights. These are hypotheses; this summary has no weather, airport-level, or individual-flight timing data to test them.

Airline mix, airport mix, season mix, and year mix can differ between morning and evening flights and across regions. These pooled differences are unadjusted and do not establish a causal effect of geography. Member 5's binomial model can assess whether the TimeOfDay × Region association persists after including Airline, Season, and Year. The seasonal patterns also motivate a TimeOfDay × Region × Season interaction if the model scope permits it.

This analysis describes the included BTS reporting flights, not every U.S. flight. Cancelled flights and flights without usable departure-delay data were excluded upstream. Cancellation risk is a separate outcome. No p-values or confidence intervals are claimed here: flights can share airport, day, and weather disruptions, and the available aggregates cannot recover those clusters.

The supplied file contains all Year × Region × Season × TimeOfDay combinations. However, it has no Month column. The repository lists 48 planned monthly inputs, but this aggregate alone cannot independently verify that every month was fully processed. Winter means January, February, and December within each calendar year, not a continuous cross-year winter.

## 中文要点

- 使用各组延误航班数和总航班数相加后计算延误率，不能直接平均原表的 DelayRate。
- {largest.Region} 的早晚延误率差距最大（{largest.EveningPenaltyPP:.2f} 个百分点），{smallest.Region} 最小（{smallest.EveningPenaltyPP:.2f} 个百分点）。排名前两名只差 {ranked.iloc[0].EveningPenaltyPP - ranked.iloc[1].EveningPenaltyPP:.2f} 个百分点，幅度非常接近。
- {"四个地区的早晚差距都在夏季最大。" if all_summer else "各地区早晚差距最大的季节有所不同。"}最大的地区与季节组合为 {peak.Region} 的 {peak.Season}（{peak.EveningPenaltyPP:.2f} 个百分点）。
- 这里的 penalty 是延误率差值，不是延误分钟数，也不是相对百分比增幅。地理差异与天气之间的因果关系不能由当前汇总数据直接证明。

See [README](README.md) for definitions, data provenance, and reproduction commands. The tables and this report are regenerated by the analysis script.
"""
    (output / "RESULTS.md").write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=HERE.parent / "summary-2022-2025.csv")
    parser.add_argument("--output-dir", type=Path, default=HERE)
    args = parser.parse_args()
    df = load_data(args.input)
    output = args.output_dir.resolve()
    for directory in [output, output / "tables", output / "plots"]:
        directory.mkdir(parents=True, exist_ok=True)
    results = {}
    for stem, groups in [("regional", ["Region"]), ("region_season", ["Region", "Season"]),
                         ("region_year", ["Region", "Year"])]:
        rates = aggregate_rates(df, groups)
        penalties = calculate_penalties(rates, groups)
        rates.to_csv(output / "tables" / f"{stem}_delay_rates.csv", index=False, float_format="%.10f")
        penalties.to_csv(output / "tables" / f"{stem}_penalties.csv", index=False, float_format="%.10f")
        results[stem] = penalties
    mapping = [(state, region) for region, states in REGION_STATES.items() for state in states.split()]
    pd.DataFrame(mapping, columns=["OriginState", "Region"]).sort_values("OriginState").to_csv(
        output / "tables" / "state_region_mapping.csv", index=False)
    audit = {
        "source_file": args.input.name,
        "source_sha256": hashlib.sha256(args.input.read_bytes()).hexdigest(),
        "aggregate_rows": len(df), "years": YEARS, "airlines": sorted(df.Airline.unique()),
        "total_eligible_flights": int(df.TotalFlights.sum()),
        "total_delayed_flights": int(df.DelayedFlights.sum()),
        "flights_by_year": {str(k): int(v) for k, v in df.groupby("Year").TotalFlights.sum().items()},
        "checks": {"unique_aggregate_keys": True, "valid_integer_counts": True,
                   "stored_rates_match_counts": True, "all_128_year_region_season_time_cells": True,
                   "aggregations_conserve_counts": True},
        "monthly_completeness": "Not verifiable from the supplied seasonal aggregates.",
        "versions": {"pandas": pd.__version__, "numpy": np.__version__, "matplotlib": matplotlib.__version__},
    }
    (output / "tables" / "data_audit.json").write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
    plot_results(results["regional"], results["region_season"], results["region_year"], output / "plots")
    write_findings(results["regional"], results["region_season"], results["region_year"], df, output)
    print(f"Validated {len(df):,} source rows representing {int(df.TotalFlights.sum()):,} flights.")
    print(results["regional"].sort_values("EveningPenaltyPP", ascending=False).to_string(index=False))
    print(f"Saved 5 figures (PNG + SVG), 7 CSV tables, audit JSON, and RESULTS.md to {output}")


if __name__ == "__main__":
    main()
