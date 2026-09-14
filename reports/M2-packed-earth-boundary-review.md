# Packed-earth visual review follow-up

Reference remains `e8560f30e2466854ab359459463659e0c9cd5b9e`.
First candidate: `a85d28d8944fea5fc1bc9da46464f282fa1a43f1`.
Its actual-Mobile Roads & Paths job in run `34681098622` passed 193 checks,
zero failures, and wrote 15 captures. Downloaded artifact: `10294014040`.

The exact-baseline paired close/reverse/terrace images were inspected. The
seams, shoulder rails and rectangle patches were gone; native grounding and
centre continuity improved. However, the boundary still read too cleanly as
a brown strip. Technical success alone was not treated as visual acceptance.

The second candidate, `32520145106030e5e4d35f7ebe77e5327d0b2b21`, changed
only the soil vertex-colour field and matched packed-earth close/reverse
cameras. Run `34681757787`, artifact `10294315726`, passed all 196 path checks
with zero errors. Android and Windows package receipts for that head were
also downloaded and their bytes/SHA256/commit independently revalidated.
The colour-only transition improved contact but still left a too-uniform
visible boundary, so one final packed-earth-only adjustment follows.

The existing five across-route stations and outer footprint are retained.
The inner soil/grass boundary now moves coherently along the route, using
stable path ID, distance and independent side phases. Its position stays
between 76% and 96% of each local half-width. The outer edge meets the native
terrain's `#7d9957` grass colour fully, rather than retaining a straight brown
outline. The same opaque soil surface provides the unequal transition depth;
there is no overlay, alpha blending, terrain mask or raised shoulder.
The centre stays clear, and sparse tuft placement/density are unchanged.
The saved centreline, width, records, terrain heights and outer geometry
bounds are unchanged. No stations, materials or per-frame work are added.
Both before/after cameras remain exactly matched and avoid roof occlusion.

First- and second-candidate committed dirt cost including grass: 432 vertices
and 216 triangles, versus baseline 63 boxes / 1512 vertices / 756 triangles.
Two tufts contain six cubes total. Dirt retains two material surfaces and
the three-style scene retains seven opaque surface draws including accepted
stepping-stone grass. With the additional terrace route the dirt totals were
992 vertices / 496 triangles and five tufts across two paths, spanning three
native surface heights. The final transition uses the same station count,
but exact geometry/cost must be read from its own CI audit, not inferred.

All prior assertions, source locks, width/geometry/performance budgets and
workflows remain intact. The unchanged full verification, Mobile performance,
Android/Windows package validation and gated private Drive workflow must pass
for the final head. Earlier candidate success is not a substitute. Final task
evidence contains the final SHA, run, matched screenshots and delivery receipt.
Hosted D3D12 Forward Mobile evidence is not physical AYN Thor testing.
