"""Read-only source/provenance and deterministic export checks for MCP planters."""
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/magicavoxel"))
from vox_to_obj import FACES, convert, read_vox

NAMES = ("flowers", "herbs", "light")
SOURCE = ROOT / "assets/source/magicavoxel"
MODELS = ROOT / "assets/models/magicavoxel"


class PlanterSourceTest(unittest.TestCase):
    def test_editable_sources_and_provenance(self):
        provenance = json.loads((SOURCE / "planters.authoring.json").read_text())
        records = {r["source"]: r for r in provenance["records"]}
        self.assertEqual(provenance["voxel_unit"], 0.0625)
        self.assertEqual(provenance["pivot_voxels"], [6, 0, 6])
        for suffix in NAMES:
            with self.subTest(suffix=suffix):
                path = SOURCE / f"hearthvale_planter_{suffix}.vox"
                size, cells, palette = read_vox(path)
                self.assertEqual(size, (12, 14, 12))
                self.assertEqual(records[path.name]["source_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
                self.assertTrue(records[path.name]["geometry_and_palette_unchanged"])
                self.assertGreater(len(cells), 450)
                self.assertLess(len(cells), 650)
                for index, colour in provenance["palette"].items():
                    self.assertEqual(palette[int(index)], tuple(bytes.fromhex(colour)) + (255,))
                remaining = set(cells)
                stack = [remaining.pop()]
                while stack:
                    cell = stack.pop()
                    for direction in FACES:
                        neighbour = tuple(cell[i] + direction[i] for i in range(3))
                        if neighbour in remaining:
                            remaining.remove(neighbour)
                            stack.append(neighbour)
                self.assertFalse(remaining, "no detached leaves, flowers, hoops or staves")

    def test_shaped_barrel_rim_seams_and_inset_soil(self):
        _, base, _ = read_vox(SOURCE / "hearthvale_planter_barrel.vox")
        self.assertEqual(base[(5, 4, 5)], 11)
        for y in (5, 6):
            self.assertNotIn((5, y, 5), base, "soil is recessed beneath an open rim")
        for y in (1, 4):
            self.assertEqual(base[(5, y, 1)], 9, "two separate iron hoops")
        self.assertEqual(base[(5, 6, 1)], 7, "wooden overhanging rim")
        for y in (2, 3):
            for axis in (0, 2):
                for across in (4, 7):
                    for side in (1, 10):
                        outer = (across, y, side) if axis == 0 else (side, y, across)
                        inner_side = 2 if side == 1 else 9
                        inner = (across, y, inner_side) if axis == 0 else (inner_side, y, across)
                        self.assertNotIn(outer, base, "recessed seam is real geometry, not a stripe")
                        self.assertIn(inner, base, "seams do not cut holes through the barrel")
        self.assertNotIn((1, 0, 5), base, "base tapers inward")
        self.assertIn((1, 2, 5), base, "belly is wider than base")
        for suffix in NAMES:
            _, cells, _ = read_vox(SOURCE / f"hearthvale_planter_{suffix}.vox")
            structure = {p: c for p, c in cells.items() if p[1] < 7 and c not in (2, 3, 4)}
            self.assertEqual(structure, base, "all variations retain the same physical barrel")

    def test_distinct_planting_and_exposed_soil(self):
        counts = {}
        for suffix in NAMES:
            _, cells, _ = read_vox(SOURCE / f"hearthvale_planter_{suffix}.vox")
            foliage = {p: c for p, c in cells.items() if p[1] >= 7}
            counts[suffix] = len(foliage)
            self.assertTrue(any(c == 11 and not any((p[0], y, p[2]) in cells for y in range(p[1] + 1, 14)) for p, c in cells.items()), "visible soil remains between planting")
            self.assertTrue(any((11 - p[0], p[1], p[2]) not in foliage for p in foliage), "asymmetric leaf silhouette")
            flower_heights = {p[1] for p, c in foliage.items() if c in (5, 6)}
            if suffix == "flowers":
                self.assertGreaterEqual(len(flower_heights), 3)
            elif suffix == "herbs":
                self.assertFalse(flower_heights)
            else:
                self.assertEqual(len(flower_heights), 1)
        self.assertGreater(counts["flowers"], counts["light"])
        self.assertGreater(counts["herbs"], counts["light"])

    def test_reproducible_exports_and_bounded_meshes(self):
        with tempfile.TemporaryDirectory() as folder:
            for suffix in NAMES:
                name = f"hearthvale_planter_{suffix}"
                output = Path(folder) / (name + ".obj")
                receipt = convert(SOURCE / (name + ".vox"), output, 0.0625, True)
                self.assertLess(receipt["triangles"], 1000)
                self.assertEqual(receipt, json.loads((MODELS / (name + ".asset.json")).read_text()))
                for extension in (".obj", ".mtl"):
                    exported = output.with_suffix(extension).read_bytes()
                    checked_out = (MODELS / (name + extension)).read_bytes()
                    # Git's Windows core.autocrlf changes text checkout bytes.
                    # Reverse only that transport change; do not parse, round,
                    # reorder or otherwise relax exact geometry/material content.
                    self.assertNotIn(b"\r", exported, "Exporter emits canonical LF")
                    canonical = checked_out.replace(b"\r\n", b"\n")
                    self.assertNotIn(b"\r", canonical, "Reject malformed line endings")
                    self.assertEqual(exported, canonical)


if __name__ == "__main__":
    unittest.main()
