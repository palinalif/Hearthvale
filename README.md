# Hearthvale — design and agent handoff

**Working title. Design draft 0.1, 6 September 2026.**

This is a planning package for a personal cozy voxel town-builder on AYN Thor Max. It is **not** a Godot project, an APK, a tested dependency bundle, or a claim that the target frame rate has been achieved.

## Start here

Read `AGENTS.md`, then `docs/design.md`, then `tasks/M0-platform-spike.md`. Begin with M0 only. The player has asked for agent-led implementation, but engine installation, device access, and project creation have not been performed by this package.

The proposed engine/backend versions need a compatibility check as a set. Prefer the tagged installation documentation linked in the design. Do not mix instructions from an unreleased branch with a released plugin.

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

The document contains researched claims and original design proposals. It does not contain measured Thor results. A future agent must report desktop tests and physical-device tests separately, and must identify blockers rather than inventing successful runs.
