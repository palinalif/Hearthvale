# M2-02 — Residential catalogue foundation

**Status:** implemented on `feat/m2-hamlet-building`; physical Thor feel and player visual approval remain separate.

Turn M2-01's safe transform preview into a true new-home route with three independent saved residential recipes.

## Scope

- Add a controller-first **Place new home** catalogue with a readable silhouette, name, shape/style summary, and current wall/roof material choices for every entry.
- Provide classic riverside cottage, low woodland lodge, and tall village-gable recipes with different footprints, proportions, rooflines, architectural accents, and material defaults.
- Save shape, style, roof profile, wall material, and roof material as independent authoritative fields while retaining compatibility with M1 documents.
- Enter the existing complete-home placement ghost without creating authority until confirmation.
- Allocate fresh building, surface, and detail identities for a confirmed catalogue home.
- Preserve cancellation, stale-revision rejection, overlap/bounds validity, undo/redo, reload, resize, attachments, and duplication.

## Acceptance

- The catalogue is fully navigable with D-pad, A, and B and does not overlap ordinary building options.
- Choosing any entry previews that exact recipe and leaves the document unchanged.
- A confirmed home is independent of the selected cottage and retains its chosen recipe and materials after reload.
- Wall and roof material edits can coexist and undo independently.
- The three catalogue silhouettes and rendered massing are materially distinguishable at normal and close Mobile views.
