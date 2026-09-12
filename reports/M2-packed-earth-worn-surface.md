# Packed-earth worn-surface pass

Status at commit: implementation candidate; native/render/package verification pending.
Base commit: `8e384a13bc2fdbb4775f48bcb5917beb4db7076b`.

## Changes

The previous base/light colour blend changed the lightest channel by only
about three 8-bit levels. The candidate instead uses base `#957058`, compacted
`#a58165` and scuffed `#896751` as flat patch colours. Existing deterministic
route-relative wear fields define the patches. Scalar clipping partitions
each native-grounded triangle: scuffs first, then compacted soil and the
remaining quiet base. The partitions share boundaries; no coincident overlay
or additional material surface is introduced. Terrain cells are not assigned
random colours. Clipping inserts vertices at the intended wear boundaries.

Route samples are refined to at most 0.25 units without moving their segments
or changing authoritative points. Occasional seeded, multi-station bites on
either side break up the long outline; these remain bounded by the existing
visible-core clamp and saved footprint. The native terrain is still exposed
outside the outline. Asymmetric ends narrow over a width-relative physical
distance rather than acquiring a different taper when sampling changes.

The terrain-height cache, coalesced native rectangle clipping, top epsilon,
material setup, grass helper bodies, and their caps remain byte-identical.
No save/terrain authority, stone renderer, dependency, workflow, collision,
placement or world-size file was changed.

## Added checks and comparison

`tests/m2_packed_earth_surface_checks.gd` is invoked by the existing width gate.
It checks complementary clipping (including threshold-equal plateaus), finite
and correctly classified vertices, sampling/endpoints/input preservation,
clockwise output from either input winding, uniform patch colours and palette
separation. Existing width, native grounding, lifecycle, authority, geometry
and draw-call assertions are retained, not relaxed.

The exact previous helper is retained as
`tests/fixtures/m2_packed_earth_8e384a13.txt`, with SHA256
`dd463b622e654c7049530be2e2bf68313b26e8b074d01053161916c3eeb5cf36`.
The existing close/reverse/terrace cameras are unchanged and now use this
fixture as their before image, rather than an older iteration of packed earth.

Local numerical checks executed the scalar clipping/wear function bodies
through a restricted Python syntax translation, not Godot. All 10,000 random
and threshold-equality partition cases passed; maximum area error was
1.1102230246251565e-16. Scalar width/wear checks passed at 0.25, 0.75 and 3.0.
Source checks confirmed the eight unchanged helper bodies and preservation of
existing acceptance assertions. Candidate runtime file SHA256:
`569ec9316ff435a721a046b235ab6e62ee01a4fc507cf8618ac4ec81d29154f2`.

Native Godot compilation/execution, Mobile captures, actual geometry cost,
performance, APK/Windows verification and private Drive delivery are NOT
claimed by these local results. Exact-head CI must supply that evidence.
The three source blob SHAs returned by GitHub matched the local files.

## Remaining work

Inspect the actual Mobile result before judging this art pass. Geometry and
vertex cost will increase where patch contours cut triangles and where the
route is refined; existing budget gates must pass without being weakened.
Junction footprint unions, doorstep-aware endpoints and fitted bend geometry
are not implemented in this commit. No claim of physical Thor acceptance or
player visual approval is made.
