"""Exact boundary coverage regression for the opt-in candidate mesher."""
import sys
import unittest
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/magicavoxel"))
from vox_to_obj import FACES, merge_faces, read_vox
from vox_to_obj import convert


class CandidateMeshingTest(unittest.TestCase):
    def test_converter_accepts_both_project_tiers(self):
        source = ROOT / "assets/source/magicavoxel/hearthvale_foliage_grass.vox"
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "grass.obj"
            self.assertEqual(convert(source, output, 0.0625, True)["voxel_tier"], "prop/detail")
            self.assertEqual(convert(source, output, 0.125, True)["voxel_tier"], "terrain/structure")
            with self.assertRaises(ValueError):
                convert(source, output, 0.25, True)

    def test_exact_palette_boundary_coverage(self):
        for name in ("tree_orchard", "tree_riverside", "tree_wind", "foliage_grass", "foliage_wildflowers", "foliage_leafy", "foliage_seedgrass", "foliage_cream", "foliage_mauve", "rock_slab", "rock_split", "rock_moss", "foliage_reeds", "foliage_fern", "foliage_mushrooms", "tree_orchard_compact", "tree_riverside_young", "tree_wind_low", "foliage_mushrooms_flat", "foliage_mushrooms_flat_scatter"):
            with self.subTest(candidate=name):
                _, voxels, _ = read_vox(ROOT / f"assets/source/magicavoxel/hearthvale_{name}.vox")
                # A tuft may contain separate rooted stems, but no floating tips.
                remaining = set(voxels)
                while remaining:
                    todo = [remaining.pop()]
                    grounded = False
                    while todo:
                        x, y, z = todo.pop()
                        grounded |= y == 0
                        for dx, dy, dz in FACES:
                            adjacent = (x + dx, y + dy, z + dz)
                            if adjacent in remaining:
                                remaining.remove(adjacent)
                                todo.append(adjacent)
                    self.assertTrue(grounded, "every connected component has a root")
                faces = defaultdict(list)
                expected = Counter()
                for (x, y, z), color in voxels.items():
                    for normal, corners in FACES.items():
                        if (x + normal[0], y + normal[1], z + normal[2]) in voxels:
                            continue
                        face = corners(x, y, z, x + 1, y + 1, z + 1)
                        faces[color].append((normal, face))
                        axis = next(a for a in range(3) if normal[a])
                        u, v = (axis + 1) % 3, (axis + 2) % 3
                        expected[(color, normal, face[0][axis], min(p[u] for p in face), min(p[v] for p in face))] += 1
                merged = merge_faces(faces)
                actual = Counter()
                for color, group in merged.items():
                    for normal, corners in group:
                        axis = next(a for a in range(3) if normal[a])
                        u, v = (axis + 1) % 3, (axis + 2) % 3
                        self.assertEqual(len({p[axis] for p in corners}), 1)
                        for a in range(min(p[u] for p in corners), max(p[u] for p in corners)):
                            for b in range(min(p[v] for p in corners), max(p[v] for p in corners)):
                                actual[(color, normal, corners[0][axis], a, b)] += 1
                self.assertEqual(expected, actual, "no missing, duplicate, internal or recolored faces")
                self.assertLess(sum(map(len, merged.values())), sum(map(len, faces.values())))


if __name__ == "__main__":
    unittest.main()
