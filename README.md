# Hearthvale — M0 platform spike

**Working title. Design draft 0.1, 6 September 2026.**

This repository began as a planning package for a personal cozy voxel town-builder on AYN Thor Max. It now contains the M0 Godot project. M0 remains subject to its evidence gate and player review; desktop tests and exported APKs do not establish physical Thor results.

## Start here

Read `AGENTS.md`, then `docs/design.md`, then `tasks/M0-platform-spike.md`. Only M0 is authorised. See `reports/M0-platform-spike.md` for measured results and limitations, `docs/build-and-test.md` for local commands, and `docs/thor-playtest.md` for the device route.

The pinned bundle is official Godot 4.7.2 with matching export templates and Voxel Tools GDExtension v1.7x. Exact origins, commits, and hashes are in `dependencies.lock.json`. The Godot AI 3.2.5 MCP sandbox is development-only under `dev/mcp`.

## Contents

- `docs/design.md`: complete design, hardware specifications, engineering targets, dependency research, and numbered sources.
- `docs/design.pdf`: illustrated reading copy of the same draft.
- `docs/references/`: the three supplied inspiration images, with attribution and usage notes.
- `AGENTS.md`: project boundaries and development workflow.
- `tasks/M0-platform-spike.md`: first implementation ticket and evidence requirements.
- `tasks/M1-editable-cottage.md`: next ticket, blocked on M0 and player approval.

## Creative brief

A small, fully sculptable valley with caves and overhangs. Stretchable procedural buildings whose individual details remain editable. Humans and animals using cafés, inns, playgrounds, and other places. Detailed voxel forms and attractive lighting. Several non-modern architectural styles. Single-screen, controller-only play, including on a TV.

The draft proposes unlimited resources, no failure or economy, exterior-focused buildings, offline play, and editable scenic water instead of general fluid physics. Those are proposed scope defaults, not additional requirements already explicitly approved by the player.

## Evidence status

The original design contains proposals, not benchmark results. The milestone report is the current evidence ledger. Physical Thor and TV checks are not run while the device is disconnected. M1 remains blocked on M0 evidence and player review.
