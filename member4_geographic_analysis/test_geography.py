"""Check the analysis against small examples and independent CSV aggregation."""

import csv
from collections import defaultdict
from pathlib import Path
import tempfile
import unittest

import pandas as pd

from analyze_geography import aggregate_rates, calculate_penalties, load_data, REGION_STATES

SOURCE = Path(__file__).resolve().parent.parent / "summary-2022-2025.csv"


class GeographicAnalysisTests(unittest.TestCase):
    def test_flight_weighting_and_percentage_point_units(self):
        # Unweighted mean of the morning cell rates would be 50%, not 10%.
        sample = pd.DataFrame({
            "Region": ["West"] * 4,
            "TimeOfDay": ["Morning", "Morning", "Evening", "Evening"],
            "TotalFlights": [10, 90, 20, 80],
            "DelayedFlights": [10, 0, 10, 20],
        })
        rates = aggregate_rates(sample, ["Region"])
        penalty = calculate_penalties(rates, ["Region"]).iloc[0]
        self.assertAlmostEqual(penalty.MorningDelayRatePct, 10)
        self.assertAlmostEqual(penalty.EveningDelayRatePct, 30)
        self.assertAlmostEqual(penalty.EveningPenaltyPP, 20)
        self.assertEqual(penalty.MorningFlights, 100)

    def test_source_reconciles_with_standard_library(self):
        independent = defaultdict(lambda: [0, 0])
        with SOURCE.open(newline="") as handle:
            for row in csv.DictReader(handle):
                key = (row["Region"], row["TimeOfDay"])
                independent[key][0] += int(row["TotalFlights"])
                independent[key][1] += int(row["DelayedFlights"])
        actual = aggregate_rates(load_data(SOURCE), ["Region"])
        for row in actual.itertuples():
            n, d = independent[(row.Region, row.TimeOfDay)]
            self.assertEqual(row.TotalFlights, n)
            self.assertEqual(row.DelayedFlights, d)
            self.assertAlmostEqual(row.DelayRate, d / n)

    def assert_invalid(self, df, message):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "invalid.csv"
            df.to_csv(path, index=False)
            with self.assertRaisesRegex(ValueError, message):
                load_data(path)

    def test_duplicate_cells_rejected(self):
        df = pd.read_csv(SOURCE)
        self.assert_invalid(pd.concat([df, df.iloc[[0]]]), "Duplicate")

    def test_invalid_counts_rejected(self):
        df = pd.read_csv(SOURCE)
        df.loc[0, "DelayedFlights"] = df.loc[0, "TotalFlights"] + 1
        self.assert_invalid(df, "exceeds")

    def test_incorrect_stored_rates_rejected(self):
        df = pd.read_csv(SOURCE)
        df.loc[0, "DelayRate"] = .999
        self.assert_invalid(df, "disagrees")

    def test_missing_coverage_rejected(self):
        df = pd.read_csv(SOURCE)
        missing = ((df.Year == 2022) & (df.Region == "West") &
                   (df.Season == "Summer") & (df.TimeOfDay == "Evening"))
        self.assert_invalid(df.loc[~missing], "coverage")

    def test_unpaired_comparison_rejected(self):
        sample = pd.DataFrame({"Region": ["West"], "TimeOfDay": ["Morning"],
                               "TotalFlights": [10], "DelayedFlights": [1]})
        with self.assertRaisesRegex(ValueError, "both morning and evening"):
            calculate_penalties(aggregate_rates(sample, ["Region"]), ["Region"])

    def test_state_mapping_has_50_states_and_dc_once(self):
        states = [state for group in REGION_STATES.values() for state in group.split()]
        self.assertEqual(len(states), 51)
        self.assertEqual(len(set(states)), 51)
        self.assertIn("DC", REGION_STATES["South"].split())
        self.assertTrue({"AK", "HI"}.issubset(REGION_STATES["West"].split()))


if __name__ == "__main__":
    unittest.main()
