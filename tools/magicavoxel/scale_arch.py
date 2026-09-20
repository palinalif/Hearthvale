"""Deterministic 2x supersample of an approved canonical MagicaVoxel .vox.

Reads a VOX 150 source, scales every voxel into a 2x2x2 block, and writes the
result to the ignored MCP staging directory. No voxel is moved, removed or
recoloured — the palette bytes are copied verbatim. Used to grow an approved
asset to a larger walk-through scale without re-authoring by hand.

Handles both the canonical layout (empty MAIN content, `RGBA` palette chunk,
as normalised by planter_assets.py) and the MCP-native layout (20-byte MAIN
content, `COLOR` chunk).

Default: assets/source/magicavoxel/hearthvale_flower_arch.vox ->
.tools/magicavoxel/vox/hearthvale_flower_arch_big3.vox
"""

from __future__ import annotations

import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/source/magicavoxel/hearthvale_flower_arch.vox"
STAGING = ROOT / ".tools/magicavoxel/vox/hearthvale_flower_arch_big3.vox"
SCALE = 2


def read_vox(path: Path):
    data = path.read_bytes()
    if data[:4] != b"VOX " or struct.unpack_from("<I", data, 4)[0] != 150:
        raise ValueError("not a VOX 150 file")
    _chunk, content_size, children_size = struct.unpack_from("<4sII", data, 8)
    cursor = 8 + 12 + content_size
    end = cursor + children_size
    size = None
    voxels = []
    palette_chunk = None
    while cursor < end:
        chunk, content_size, child_size = struct.unpack_from("<4sII", data, cursor)
        content = cursor + 12
        if chunk == b"SIZE":
            size = struct.unpack_from("<III", data, content)
        elif chunk == b"XYZI":
            count = struct.unpack_from("<I", data, content)[0]
            for index in range(count):
                voxels.append(struct.unpack_from("<BBBB", data, content + 4 + index * 4))
        elif chunk in (b"COLOR", b"RGBA"):
            palette_chunk = (chunk, data[content : content + 1024])
        cursor = content + content_size + child_size
    if size is None or not voxels or palette_chunk is None:
        raise ValueError("missing SIZE/XYZI/palette chunk")
    return size, voxels, palette_chunk


def write_vox(path: Path, size, voxels, palette_chunk) -> None:
    chunk_name, palette = palette_chunk
    body = bytearray()
    body += struct.pack("<4sII", b"SIZE", 12, 0) + struct.pack("<III", *size)
    body += struct.pack("<4sII", b"XYZI", 4 + 4 * len(voxels), 0)
    body += struct.pack("<I", len(voxels))
    body += b"".join(struct.pack("<BBBB", *v) for v in voxels)
    body += struct.pack("<4sII", chunk_name, 1024, 0) + palette
    # Keep the canonical (planter-normalised) empty-MAIN layout.
    out = b"VOX " + struct.pack("<I", 150) + struct.pack("<4sII", b"MAIN", 0, len(body)) + body
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out)


def main() -> None:
    size, voxels, palette = read_vox(SOURCE)
    scaled_size = tuple(s * SCALE for s in size)
    scaled = []
    for x, y, z, color in voxels:
        for dx in range(SCALE):
            for dy in range(SCALE):
                for dz in range(SCALE):
                    scaled.append((x * SCALE + dx, y * SCALE + dy, z * SCALE + dz, color))
    write_vox(STAGING, scaled_size, scaled, palette)
    print(f"{SOURCE.name} {size} {len(voxels)} voxels -> {STAGING.name} {scaled_size} {len(scaled)} voxels")


if __name__ == "__main__":
    main()
