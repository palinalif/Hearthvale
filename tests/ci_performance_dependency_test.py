"""Catch incomplete CI transplants before launching the renderer."""

import json
import math
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "tests/m2_mobile_performance_guard.gd"


class PerformanceDependencyTest(unittest.TestCase):
    def load_baseline(self):
        source = GUARD.read_text(encoding="utf-8")
        match = re.search(r'^const BASELINE_PATH := "res://([^"\n]+)"$', source, re.MULTILINE)
        self.assertIsNotNone(match, "performance guard must declare its baseline dependency")
        path = ROOT / match.group(1)
        self.assertTrue(path.is_file(), f"CI performance baseline is missing: {path.relative_to(ROOT)}")
        return source, json.loads(path.read_text(encoding="utf-8"))

    def test_baseline_is_bundled_and_has_supported_schema(self):
        _, baseline = self.load_baseline()
        self.assertEqual(baseline["version"], 1)
        self.assertEqual(baseline["kind"], "normalized-hosted-runner-budget")

    def test_every_measured_scenario_has_a_finite_positive_budget(self):
        source, baseline = self.load_baseline()
        measured = set(re.findall(r'normalized\["([^"\n]+)"\]\s*=', source))
        self.assertTrue(measured, "guard must measure performance scenarios")
        budgets = baseline["normalized_budgets"]
        self.assertEqual(set(budgets), measured)
        for name, value in budgets.items():
            with self.subTest(metric=name):
                self.assertIs(type(value), float)
                self.assertTrue(math.isfinite(value) and value > 0.0)

    def test_regression_allowance_is_explicit_and_valid(self):
        _, baseline = self.load_baseline()
        value = baseline["allowed_regression_fraction"]
        self.assertIs(type(value), float)
        self.assertTrue(math.isfinite(value) and 0.0 <= value < 1.0)


if __name__ == "__main__":
    unittest.main()
