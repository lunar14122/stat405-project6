#!/bin/bash
set -e

year=$1
month=$2

series=1987_present
if [[ $year == 2023 && $month == 12 ]]; then
    series='(1987_present)'
fi

base=https://www.transtats.bts.gov/PREZIP
url="$base/On_Time_Reporting_Carrier_On_Time_Performance_${series}_${year}_${month}.zip"
zip="bts-${year}-${month}.zip"

wget -O "$zip" "$url"

python3 - "$zip" "$year" "$month" <<'PY'
import csv
import io
import sys
from collections import defaultdict
from zipfile import ZipFile

zip_file, year, month = sys.argv[1:]
month = int(month)

seasons = [
    "Winter", "Winter", "Spring", "Spring", "Spring", "Summer",
    "Summer", "Summer", "Fall", "Fall", "Fall", "Winter",
]
season = seasons[month - 1]

regions = {
    "Northeast": "CT ME MA NH RI VT NJ NY PA",
    "Midwest": "IL IN MI OH WI IA KS MN MO NE ND SD",
    "South": "DE DC FL GA MD NC SC VA WV AL KY MS TN AR LA OK TX",
    "West": "AZ CO ID MT NV NM UT WY AK CA HI OR WA",
}

state_region = {}
for region, states in regions.items():
    for state in states.split():
        state_region[state] = region

counts = defaultdict(lambda: [0, 0])

with ZipFile(zip_file) as archive:
    csv_name = next(name for name in archive.namelist()
                    if name.lower().endswith(".csv"))

    with archive.open(csv_name) as raw:
        rows = csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline=""))

        for row in rows:
            if float(row["Cancelled"] or "-1") != 0:
                continue

            airline = row["Reporting_Airline"].strip()
            region = state_region.get(row["OriginState"])
            departure = int(row["CRSDepTime"] or "-1")

            if not airline or not region or departure % 100 > 59:
                continue

            if 600 <= departure <= 1159:
                time_of_day = "Morning"
            elif 1800 <= departure <= 2359:
                time_of_day = "Evening"
            else:
                continue

            flag = float(row["DepDel15"] or "-1")
            if flag in (0, 1):
                delayed = int(flag)
            elif row["DepDelay"]:
                delayed = int(float(row["DepDelay"]) >= 15)
            else:
                continue

            group = (year, airline, season, region, time_of_day)
            counts[group][0] += 1
            counts[group][1] += delayed

output = f"summary-{year}-{month:02d}.csv"

with open(output, "w", newline="", encoding="utf-8") as file:
    writer = csv.writer(file)
    writer.writerow([
        "Year", "Airline", "Season", "Region", "TimeOfDay",
        "TotalFlights", "DelayedFlights", "DelayRate",
    ])

    for group, (total, delayed) in sorted(counts.items()):
        writer.writerow([*group, total, delayed, delayed / total])

print(f"Created {output}")
PY

rm -- "$zip"
