# Packed-earth visual review follow-up

Reference remains `e8560f30e2466854ab359459463659e0c9cd5b9e`.
First candidate: `a85d28d8944fea5fc1bc9da46464f282fa1a43f1`.
Its actual-Mobile Roads & Paths job in run `34681098622` passed 193 checks,
zero failures, and wrote 15 captures. Downloaded artifact: `10294014040`.

The exact-baseline paired close/reverse/terrace images were inspected. The
seams, shoulder rails and rectangle patches were gone; native grounding and
centre continuity improved. However, the boundary still read too cleanly as
a brown strip. Technical success alone was not treated as visual acceptance.

This follow-up changes only the soil vertex-colour field and the matched
packed-earth close/reverse cameras. The existing earthy centre is slightly
more subdued. The outer band transitions unequally into the native terrain's
`#7d9957` grass colour using a continuous, stable path-ID/position field.
The central 64% stays soil-only except the restrained end termination.
There is no alpha blending, terrain mask, raised shoulder, extra surface,
new geometry, increased grass density or changed terrain/path record.
Both before/after cameras move identically to reduce roof occlusion.
A new assertion checks finite, fully opaque vertex colours in each audit.
All earlier tests, source locks and budgets remain intact.

First-candidate committed dirt cost including its grass: 432 vertices and
216 triangles, versus baseline 63 boxes / 1512 vertices / 756 triangles.
Two tufts contain six cubes total. Dirt retains two material surfaces and
the three-style scene retains seven opaque surface draws including accepted
stepping-stone grass. With the additional terrace route the dirt totals were
992 vertices / 496 triangles and five tufts across two paths, spanning three
native surface heights. The colour follow-up leaves geometry unchanged, but
these figures must still be rechecked against the exact new-head CI receipt.

The unchanged full verification, Mobile performance, Android/Windows package
validation and gated private Drive workflow must pass for the follow-up head.
No first-candidate success is a substitute for that verification. Final task
evidence contains the final SHA, run, matched screenshots and delivery receipt.
Hosted D3D12 Forward Mobile evidence is not physical AYN Thor testing.
