# Hearthvale — Godot development conventions

Read this document when introducing a new Godot subsystem, substantially
refactoring an existing one, or making a change that affects ownership,
scene architecture, persistence, threading, rendering or runtime performance.

For ordinary focused bug fixes, follow `AGENTS.md` and the local code instead
of loading this entire document unnecessarily.

The goal is not maximum abstraction. The goal is code whose ownership,
runtime cost and behavior remain understandable as Hearthvale grows.

## 1. Ownership first

Before adding code, identify the authoritative owner of the state being changed.

A piece of gameplay state should normally have exactly one authority.

Examples:

- placement records own what exists and where
- save/checkpoint data owns persisted state
- terrain data owns voxel contents
- a generated mesh displays authoritative data but does not replace it
- a preview displays a prospective edit but is not committed state
- caches accelerate derivation but are disposable

Avoid maintaining two mutable representations that must be manually kept in
sync.

If a derived representation can be rebuilt from authority, treat it as derived.

When ownership is unclear, resolve that before adding callbacks,
synchronization logic or another manager.

## 2. Prefer composition over more inheritance

Hearthvale already has a very deep gameplay scene-script inheritance chain.

Preserve existing inheritance contracts when editing them, but do not extend
the chain merely because another feature needs one override.

For new functionality, prefer in roughly this order:

1. an existing owner/seam
2. a small helper or `RefCounted`
3. a dedicated child node/component
4. a `Resource` for reusable/configurable data
5. a new inherited scene/script layer only when inheritance is genuinely the
   correct ownership relationship

Never copy a parent's multi-line implementation into a child to change one
piece of behavior.

Prefer a child implementation that calls `super._build_world()` and then
changes only the one thing that layer owns, rather than duplicating the
parent's entire `_build_world()`.

If an inherited method repeatedly needs exceptions, consider extracting a
small overridable seam in the common owner rather than creating parallel
copies.

## 3. Keep scene scripts as orchestrators

Scene scripts should mostly coordinate:

- lifecycle
- input
- subsystem creation
- high-level state transitions
- integration between clearly owned systems

Reusable calculations, validation, geometry/layout generation and document
transformations should usually live in independently testable helpers.

A large script is not automatically bad. Split it only when there is a real
ownership or cohesion boundary.

Do not turn one understandable 500-line subsystem into twelve tiny files whose
relationships are harder to understand merely to reduce line count.

A useful extraction should make it easier to answer:

- what does this object own?
- who calls it?
- what inputs does it need?
- what state can it mutate?

## 4. Typed GDScript by default

Prefer explicit types for:

- members
- function parameters
- return values
- collections where the element type matters
- values crossing subsystem boundaries

Prefer explicit signatures such as:

    func find_surface(cell: Vector3i) -> Vector3:

rather than relying on `Variant` propagation.

Avoid spreading dynamic APIs through normal project code:

    object.get("thing")
    object.set("thing", value)
    object.call("method_name")

Dynamic access is reasonable at boundaries such as optional plugins,
ClassDB/GDExtension integration or compatibility probes.

When dynamic access is necessary, isolate it in a small adapter and convert
back to typed project values as quickly as possible.

Do not guess Godot APIs. Follow the API-verification rules in `AGENTS.md`.

## 5. Explicit references beat SceneTree archaeology

Prefer keeping a reference to a subsystem when creating it and passing that
reference where needed.

Avoid routine gameplay code that repeatedly searches for dependencies using:

- `get_tree().get_nodes_in_group(...)`
- broad recursive child searches
- node-name string searches
- global singleton lookup merely for convenience

Groups are useful for genuine many-to-many categorization or discovery, but
should not replace clear ownership.

If object A always owns object B, A should normally retain a reference to B.

## 6. Signals versus direct calls

Use direct typed method calls when:

- ownership is clear
- one subsystem is intentionally commanding another
- the caller needs an immediate result

Use signals when:

- several independent listeners may care about an event
- the emitter should not know its listeners
- the event represents notification rather than command/control

Avoid signal chains where A emits to B, B emits to C, and nobody can tell what
actually caused the state change.

Do not use signals merely to avoid writing a normal function call.

## 7. Separate input, authority and presentation

Input should request gameplay actions through established interfaces.

Do not make input code directly mutate:

- generated meshes
- save files
- caches
- presentation-only node state as a substitute for gameplay state

A typical flow should resemble:

    InputMap/controller event
        -> gameplay action
        -> authoritative state mutation
        -> revision/event
        -> derived visuals/cache update

Use InputMap actions for gameplay controls rather than hard-coded physical
keys/buttons.

Keep debug/test semantic actions routed through the same authoritative
gameplay operations whenever practical.

## 8. Avoid unnecessary per-frame work

Do not use `_process()` or `_physics_process()` as a convenient place to
continually rediscover whether something changed.

Prefer:

- signals/events
- revision counters
- dirty flags
- queued/deferred work
- incremental invalidation
- explicit state transitions

Avoid per-frame:

- whole-world scans
- JSON serialization for change detection
- rebuilding unchanged meshes
- traversing large node trees
- regenerating immutable data
- allocating large temporary arrays/dictionaries

If work only needs to happen when data changes, make the data change trigger
it.

If expensive work must be spread over time, use a bounded queue/budget rather
than one giant frame spike.

## 9. Incremental work and caching

Cache only when there is a measured reason or a clearly repeated expensive
operation.

Every cache must have an understandable invalidation rule.

Prefer revision/key-based invalidation:

    authority revision changed
        -> invalidate affected derived region
        -> rebuild only that region

over "rebuild everything to be safe."

Do not allow a cache to quietly become another authoritative state store.

When implementing incremental systems, explicitly test:

- first element / empty -> non-empty
- append/growth
- replacement
- deletion
- invalidation
- no-op unchanged update
- save/load restoration where relevant

## 10. Resources and shared state

Remember that Godot `Resource`s may be shared between instances.

Do not mutate a shared Material, Mesh, Resource or configuration object for
one instance unless that sharing is intentional.

If an instance needs unique mutable resource state, duplicate or create an
instance-owned resource deliberately.

Prefer sharing immutable resources such as common materials or meshes when it
reduces memory/draw/setup cost without introducing hidden coupling.

## 11. Rendering and mobile performance

Hearthvale targets the AYN Thor Max and Godot Mobile rendering.

Desktop rendering is useful development evidence but is not device performance
evidence.

Before introducing a rendering optimization:

1. measure the actual bottleneck
2. identify whether cost is CPU, GPU, draw calls, primitives, memory, startup,
   generation or interaction latency
3. change one meaningful variable
4. measure again on the relevant target

Do not remove visual detail or introduce complicated native/C++
infrastructure based purely on intuition.

Prefer:

- reusing resources
- batching genuinely repeated geometry
- incremental geometry rebuilds
- reducing unnecessary rebuilds/submissions
- bounded visible work

before introducing a substantially more complex architecture.

Do not optimize stale worlds or stale APKs.

## 12. Async and threaded work

The live SceneTree is main-thread-owned unless a Godot API explicitly
documents otherwise.

Worker/background jobs should operate on isolated data, snapshots or immutable
inputs.

Do not mutate live Nodes from worker threads.

Any asynchronous result that can outlive the state it was computed from needs
a staleness check, such as:

- revision ID
- document version
- request generation
- stable object ID plus expected state

Example:

    start job at revision 12
    world advances to revision 13
    job finishes
        -> reject revision-12 result

Do not publish partially generated authoritative state. Commit complete results
atomically where possible.

Provide cancellation/cleanup for work whose owner can disappear.

## 13. Save data is an API

Treat persisted formats as compatibility contracts.

Persist:

- stable IDs
- authoritative records
- explicit user choices/overrides
- enough information to reconstruct derived state

Avoid persisting:

- Node references
- generated Mesh instances
- caches
- preview state
- transient editor/runtime implementation details

New fields should have safe defaults for older saves.

If a schema truly must change incompatibly, implement an explicit migration
rather than silently changing interpretation.

Never discard real player/test saves to make new code easier.

## 14. Autoloads and globals

Do not create an Autoload simply because accessing an object globally is
convenient.

An Autoload should represent something with genuinely application-wide
lifetime/identity.

Gameplay systems should normally be owned by the gameplay scene or another
clear project object.

Avoid generic global "Manager" singletons that gradually accumulate unrelated
responsibilities.

## 15. Abstractions must earn their existence

Do not build frameworks for hypothetical future requirements.

Before introducing:

- an interface hierarchy
- service locator
- event bus
- generic repository layer
- manager framework
- factory system
- new scene inheritance layer

identify the concrete problem it solves today.

Good reasons include:

- real duplicated logic
- unclear ownership
- difficult testing
- repeated coupling
- multiple implementations that genuinely share a contract

"We might need this later" is not sufficient.

Prefer the simplest design that preserves current contracts cleanly.

## 16. Tests

Test the smallest layer capable of proving the behavior.

Prefer:

    pure/helper test
        -> focused scene/subsystem test when integration matters
        -> full gameplay/device test only when genuinely required

Do not instantiate the full gameplay chain to test a calculation that can be
tested directly.

Assert observable contracts and invariants rather than incidental
implementation details.

Avoid brittle assertions such as exact:

- node counts
- internal child ordering
- triangle/pixel counts unless they are explicitly the contract
- private method call sequences

Prefer:

- exists / does not exist
- monotonic relationships
- bounded ranges
- stable IDs
- expected state transition
- round-trip save behavior
- no-op behavior for unchanged input

A bug fix should usually gain the smallest regression test that would have
caught that specific class of failure.

## 17. Refactoring discipline

Do not combine a broad architecture cleanup with an unrelated feature unless
the feature cannot be implemented safely without it.

For consequential refactors:

1. identify the concrete problem
2. preserve externally observable contracts
3. add or identify coverage first
4. refactor in reviewable steps
5. keep the project importing/runnable between meaningful steps where practical
6. verify behavior after the refactor
7. measure again if performance motivated the change

Do not rewrite working systems merely because another style is aesthetically
preferable.

## 18. Before creating a new subsystem

Answer these questions first:

1. What authoritative state does it own?
2. Who creates and destroys it?
3. Who is allowed to mutate it?
4. What are its inputs and outputs?
5. Can its core logic be tested without the full gameplay scene?
6. Is there already an owner/seam that should contain this instead?
7. Does it require persistence? If so, what is the stable schema?
8. Does it perform work every frame? Why?
9. Can it invalidate/rebuild only affected data?
10. Is a new abstraction actually solving a demonstrated problem?

If those answers are unclear, investigate the existing architecture before
adding code.

## 19. Before handoff

For significant Godot changes, check that:

- authority remains unambiguous
- no duplicate mutable state was introduced
- no unnecessary inheritance layer or Autoload was added
- dynamic/plugin APIs are isolated
- expensive work is event-driven/incremental where appropriate
- relevant regressions pass
- save compatibility is preserved
- device-specific claims are backed by device evidence
- implementation matches the approved todo/plan
