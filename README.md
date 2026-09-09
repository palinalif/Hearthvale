# Hearthvale — editable cottage milestone

**Working title. Design draft 0.1, 6 September 2026.**

This repository began as a planning package for a personal cozy voxel town-builder on AYN Thor Max. It now contains the Godot project, the retained M0 platform scene, and an M1 build ready for physical playtest. M0 remains subject to its evidence gate and player review; desktop tests and exported APKs do not establish physical Thor results.

M1 artifacts, exact verification results, screenshots and remaining checks are recorded in [the M1 handoff](reports/M1-editable-cottage.md).

## Start here

Read `AGENTS.md`, then `docs/design.md`, then both authoritative M1 tickets: `tasks/M1-editable-cottage.md` and `tasks/M1-terrain-sculpting.md`. The player has authorized one editable procedural cottage, continuous volumetric sculpting and a modest visual checkpoint. The planned M2 residential expansion—including free placement and rotation—is recorded in `tasks/M2-hamlet-building.md` and is not active implementation scope. Build instructions are in `docs/build-and-test.md`; M1 controls and physical checks are in `docs/M1-controller-and-review.md` and `docs/M1-thor-playtest.md`. M0 evidence gaps remain open in `reports/M0-platform-spike.md`, `reports/M0-placement-followup.md` and `docs/thor-playtest.md`.

The pinned bundle is official Godot 4.7.2 with matching export templates and Voxel Tools GDExtension v1.7x. Exact origins, commits, and hashes are in `dependencies.lock.json`. The Godot AI 3.2.5 MCP sandbox is development-only under `dev/mcp`.

## Contents

- `docs/design.md`: complete design, hardware specifications, engineering targets, dependency research, and numbered sources.
- `docs/design.pdf`: original illustrated planning draft; current milestone corrections and art direction are authoritative in `docs/design.md`.
- `docs/references/`: the three supplied inspiration images, with attribution and usage notes.
- `BACKLOG.md`: uncommitted future ideas and explicit product boundaries; entries do not authorize implementation.
- `AGENTS.md`: project boundaries and development workflow.
- `tasks/M0-platform-spike.md`: first implementation ticket and evidence requirements.
- `tasks/M1-editable-cottage.md`: authorized current ticket; functioning building editing and its full regression are mandatory.
- `tasks/M1-terrain-sculpting.md`: authorized parallel M1 workstream; continuous volumetric strokes and controller safety are mandatory.

## Creative brief

A small, fully sculptable valley with caves and overhangs. Stretchable procedural buildings whose individual details remain editable. Humans and animals using cafés, inns, playgrounds, and other places. Detailed voxel forms and attractive lighting. Several non-modern architectural styles. Single-screen, controller-only play, including on a TV.

The draft proposes unlimited resources, no failure or economy, exterior-focused buildings, offline play, and editable scenic water instead of general fluid physics. Those are proposed scope defaults, not additional requirements already explicitly approved by the player.

## Evidence status

The original design contains proposals, not benchmark results. Milestone reports contain the actual evidence. The player reported successful manual Thor testing of the original M0 build; detailed device checks, the revised controls playtest, and the MCP persistence issue remain separate open items. M1 implementation is authorized, but this does not waive those checks or establish M1 device acceptance.
