import csv
from collections import defaultdict

keys = ["Year", "Airline", "Season", "Region", "TimeOfDay"]
counts = defaultdict(lambda: [0, 0])

with open("flight_months.txt") as months:
    for line in months:
        year, month, tag = line.split()

        with open(f"summary-{tag}.csv", newline="") as source:
            for row in csv.DictReader(source):
                group = tuple(row[key] for key in keys)
                counts[group][0] += int(row["TotalFlights"])
                counts[group][1] += int(row["DelayedFlights"])

with open("summary-2022-2025.csv", "w", newline="") as output:
    writer = csv.writer(output)
    writer.writerow(keys + ["TotalFlights", "DelayedFlights", "DelayRate"])

    for group, (total, delayed) in sorted(counts.items()):
        writer.writerow([*group, total, delayed, delayed / total])

print(f"Created summary-2022-2025.csv with {len(counts)} groups")
