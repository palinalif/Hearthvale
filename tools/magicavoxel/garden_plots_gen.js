// Provenance: the deterministic pattern used to author the six garden plots
// through the MagicaVoxel MCP (batched fill_box calls, one mcpScript per model).
//
//   create_voxel_model(name, W, H, D)
//   set_palette_color(idx, "#rrggbb")   // idx 0 is MagicaVoxel's empty slot
//   [pattern below]
//
// Palette convention (all six plots):
//   1 timber frame  #8a6a4a        3 dark green   #4e7142
//   2 soil          #6b4a31        4 light green  #86a258
//   5 accent (per plot: rose / berry / lavender)
//
// Coordinate convention: x = width (size.x), z = depth (size.y), y up, origin
// at the southwest corner of the plot. The MCP shrinks the declared SIZE to
// the content bounds after edits; the converter pivot stays centred on the
// declared (even) horizontal volume, and runtime placement snaps the model's
// AABB to the surface, so no post-authoring SIZE restore is needed here.

function kitchen(w, d) {
  // Palette: 1 #8a6a4a, 2 #6b4a31, 3 #4e7142, 4 #86a258, 5 #c96f43
  fill({ x0: 0, x1: w - 1, y0: 0, y1: 3, z0: 0, z1: d - 1, palette_index: 2 });
  for (const z of [0, d - 1]) box(0, 0, z, w - 1, 1, z, 1);
  for (const x of [0, w - 1]) box(x, 0, 0, x, 1, d - 1, 1);
  // Three raised rows along the depth axis (x bands 1/3, 2/3).
  const xs = [[1, Math.round(w / 3) - 1], [Math.round(w / 3) + 1, Math.round(2 * w / 3) - 1], [Math.round(2 * w / 3) + 1, w - 2]];
  for (const [xa, xb] of xs) {
    box(xa, 4, 1, xb, 4, d - 2, 2);
    for (let p = 0; p < 10; p++) {
      const px = xa + 1 + ((p * 3 + p % 2) % (xb - xa - 1));
      const pz = 1 + Math.floor((d - 2) / 2) + (p % 2 === 0 ? -Math.floor((d - 2) / 4) : Math.floor((d - 2) / 4));
      box(px, 5, pz, px + 1, 6, pz + 1, 3);
      box(px + 1, 7, pz + 1, px + 1, 7, pz + 1, 4);
      if (p % 3 === 0) box(px, 8, pz + 1, px, 8, pz + 1, 5);
    }
  }
}

function flowers(w, d) {
  // Palette: 1 #8a6a4a, 2 #6b4a31, 3 #4e7142, 4 #86a258, 5 #d8a2a0
  box(0, 0, 0, w - 1, 0, d - 1, 2);
  for (const z of [0, d - 1]) box(0, 0, z, w - 1, 0, z, 1);
  for (const x of [0, w - 1]) box(x, 0, 0, x, 0, d - 1, 1);
  // Six drifting rows of two-segment stems; every third flower is wider.
  const h = (i) => 1 + (i * 7 % 3);
  for (let i = 0; i < 36; i++) {
    const x = 2 + (i % 6) * (Math.floor(w / 6)) + (i % 2);
    const z = 2 + Math.floor(i / 6) * (Math.floor(d / 6)) + ((i * 3) % 3);
    const hh = h(i);
    for (let s = 0; s < hh; s++) box(x, 1 + s, z, x, 1 + s, z, 3);
    if (i % 3 === 0) box(x - 1, 1 + hh, z, x + 1, 2 + hh, z + 1, 5);
    else box(x, 1 + hh, z, x, 2 + hh, z, 5);
  }
}

function herbs(w, d) {
  // Palette: 1 #8a6a4a, 2 #6b4a31, 3 #4e7142, 4 #86a258, 5 #9d8fa6
  box(0, 0, 0, w - 1, 0, d - 1, 2);
  for (const z of [0, d - 1]) box(0, 0, z, w - 1, 1, z, 1);
  for (const x of [0, w - 1]) box(x, 0, 0, x, 1, d - 1, 1);
  box(Math.floor(w / 2), 0, 1, Math.floor(w / 2), 1, d - 2, 1);
  box(1, 0, Math.floor(d / 2), w - 2, 1, Math.floor(d / 2), 1);
  // Two-tier tufts in a 7 x 7 grid; lavender caps where the index is odd.
  for (let c = 0; c < 7; c++) {
    for (let r = 0; r < 7; r++) {
      const x = 1 + c * (Math.floor((w - 2) / 7));
      const z = 1 + r * (Math.floor((d - 2) / 7));
      const i = c * 7 + r;
      box(x, 1, z, x + (i % 3 === 0 ? 1 : 0), 2, z + (i % 2 === 0 ? 1 : 0), 3);
      box(x + (i % 2 === 0 ? 1 : 0), 3, z, x + (i % 2 === 0 ? 1 : 0), 3, z + (i % 3 === 0 ? 1 : 0), i % 2 === 0 ? 5 : 4);
    }
  }
}

// Models and sizes (MCP declared volumes; W x H x D):
//   hearthvale_garden_kitchen_48x28  kitchen(48, 28)
//   hearthvale_garden_kitchen_56x40  kitchen(56, 40)
//   hearthvale_garden_flowers_16x32  flowers(16, 32)
//   hearthvale_garden_flowers_48x32  flowers(48, 32)
//   hearthvale_garden_herbs_24x16    herbs(24, 16)
//   hearthvale_garden_herbs_36x36    herbs(36, 36)
// (box(a0, b0, c0, a1, b1, c1, palette_index) = inclusive fill_box.)
