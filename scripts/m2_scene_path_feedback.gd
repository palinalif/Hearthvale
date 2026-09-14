extends "res://scripts/m2_scene_street_furniture.gd"

## The former point-route feedback layer is intentionally empty now. Painted
## paths own their complete hold-A / release-to-commit / B-cancel interaction in
## m2_scene_paths.gd, so keeping the old point-pausing overrides here would make
## the scene inherit APIs that no longer exist and break project import.
