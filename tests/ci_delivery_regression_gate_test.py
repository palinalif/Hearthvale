"""Private delivery must wait for every regression, not only valid packages.

Uses the workflow's deliberately simple inline needs lists, without adding a
YAML dependency to pinned CI. A syntax/layout change fails closed for review.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/m1-drive-delivery.yml"
REQUIRED = {"delivery-contract", "build-candidates", "sculpt-feedback", "terrain-ux", "placement", "performance", "cottage-and-apk"}


def job_block(source, name):
    found = re.search(r"^  " + re.escape(name) + r":\n(.*?)(?=^  [a-z][a-z0-9-]*:|\Z)", source, re.M | re.S)
    if not found:
        raise AssertionError("Missing workflow job: " + name)
    return found.group(1)


class DeliveryRegressionGateTest(unittest.TestCase):
    def test_both_private_uploads_wait_for_all_required_gates(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        for name in ("drive-apk", "drive-pc"):
            with self.subTest(job=name):
                block = job_block(source, name)
                match = re.search(r"^    needs: \[([^\]\n]+)\]$", block, re.M)
                self.assertIsNotNone(match, "Delivery needs must remain explicit")
                self.assertEqual({value.strip() for value in match.group(1).split(",")}, REQUIRED)
                self.assertIn("if: vars.GOOGLE_DRIVE_UPLOAD_ENABLED == 'true'", block)
                self.assertNotRegex(block, r"always\s*\(|continue-on-error|failure\s*\(|cancelled\s*\(")
                self.assertIn("$record.commit -ne $env:GITHUB_SHA", block)
                self.assertIn("$record.sha256 -ne $hash", block)
                self.assertIn("[int64]$record.bytes -ne", block)
        for name in REQUIRED:
            self.assertNotIn("continue-on-error", job_block(source, name))

    def test_planter_source_interaction_and_render_checks_are_wired(self):
        workflow = (ROOT / ".github/workflows/cottage-playtest.yml").read_text(encoding="utf-8")
        self.assertRegex(workflow, r"(?m)^          - planters$")
        self.assertIn("reports/screenshots/m2-planters/", workflow)
        runner = (ROOT / "tools/test-cottage-shard.ps1").read_text(encoding="utf-8")
        block = re.search(r"(?ms)^    'planters' \{(.*?)^    \}", runner)
        self.assertIsNotNone(block)
        for name in ("m2_planter_asset_test", "m2_planter_placement_test", "m2_planter_render_test"):
            self.assertIn(name, block.group(1))
            self.assertTrue((ROOT / "tests" / (name + ".gd")).is_file())
        self.assertIn("Invoke-ProjectImport", block.group(1))
        self.assertIn("Invoke-MobileReview", block.group(1))
        self.assertIn("PLANTER_MOBILE_CAPTURE", block.group(1))
        self.assertNotIn("--promote", block.group(1), "CI validates canonical exports without private MCP staging")

    def test_windows_candidate_proves_runtime_terrain_readiness(self):
        workflow = (ROOT / ".github/workflows/thor-repair-apk.yml").read_text(encoding="utf-8")
        build = job_block(workflow, "build-windows")
        self.assertIn("terrain-ready.json", build)
        self.assertIn("TERRAIN_RUNTIME_READY", build)
        self.assertIn("Get-Content $receipt -Raw | ConvertFrom-Json", build)
        self.assertRegex(build, r"if \(-not \$.*\.ok\)")
        project = (ROOT / "project.godot").read_text(encoding="utf-8")
        self.assertIn('TerrainRuntimeProbe="*res://scripts/terrain_runtime_probe.gd"', project)
        self.assertTrue((ROOT / "scripts/terrain_runtime_probe.gd").is_file())

    def test_backend_readiness_diagnostics_expose_initialization_phase_and_error(self):
        helper = (ROOT / "tests/scene_readiness.gd").read_text(encoding="utf-8")
        self.assertIn('"backend_phase"', helper)
        self.assertIn('"backend_error"', helper)
        self.assertIn("is_area_editable", helper)
        self.assertIn("is_area_meshed", helper)

    def test_gate_contract_runs_in_delivery_prerequisite(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("tests/ci_delivery_regression_gate_test.py", job_block(source, "delivery-contract"))


if __name__ == "__main__":
    unittest.main()
