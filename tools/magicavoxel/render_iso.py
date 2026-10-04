#!/usr/bin/env python3
"""Render .vox models as shaded isometric previews for visual review.

Painter's algorithm over voxels sorted far-to-near; each voxel contributes its
top, front and right faces as shaded parallelograms.  Used only to review
authored voxel art — it is not part of the runtime render path.
"""
import sys, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from vox150 import read_vox
from PIL import Image, ImageDraw


def shade(rgb, f):
    return tuple(min(255, int(c * f)) for c in rgb[:3])


def render(path, scale=8, bg=(18, 18, 22)):
    size, voxels, pal = read_vox(Path(path))
    cells = [(v[0], v[1], v[2], v[3]) for v in voxels]
    if not cells:
        raise SystemExit(f"{path}: no voxels")
    sx, sy, sz = size
    w = (sx + sy) * scale + 40
    h = (sx + sy) // 2 * scale + sz * scale + 60
    img = Image.new('RGB', (w, h), bg)
    dr = ImageDraw.Draw(img)
    cells.sort(key=lambda c: c[0] + c[1] + c[2])
    for x, y, z, ci in cells:
        rgb = pal[ci][:3] if ci < len(pal) and pal[ci][3] else (255, 0, 255)
        px = (x - y) * scale + sy * scale + 20
        py = (x + y) * scale // 2 - z * scale + 30
        top = [(px, py), (px + scale, py + scale // 2), (px, py + scale), (px - scale, py + scale // 2)]
        right = [(px + scale, py + scale // 2), (px + scale, py + scale // 2 + scale),
                 (px, py + scale + scale), (px, py + scale)]
        front = [(px - scale, py + scale // 2), (px - scale, py + scale // 2 + scale),
                 (px, py + scale + scale), (px, py + scale)]
        dr.polygon(top, fill=shade(rgb, 1.0))
        dr.polygon(right, fill=shade(rgb, 0.62))
        dr.polygon(front, fill=shade(rgb, 0.80))
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='+')
    ap.add_argument('--labels', nargs='*', default=[])
    ap.add_argument('--scale', type=int, default=8)
    ap.add_argument('--out', default='/tmp/iso.png')
    a = ap.parse_args()
    imgs = [render(f, a.scale) for f in a.files]
    labels = a.labels or [Path(f).stem for f in a.files]
    W = sum(i.width for i in imgs) + 20 * (len(imgs) + 1)
    H = max(i.height for i in imgs) + 34
    canvas = Image.new('RGB', (W, H), (10, 10, 14))
    dr = ImageDraw.Draw(canvas)
    x = 20
    for label, im in zip(labels, imgs):
        canvas.paste(im, (x, 30))
        dr.text((x, 8), label, fill=(235, 235, 235))
        x += im.width + 20
    canvas = canvas.resize((canvas.width * 2, canvas.height * 2), Image.NEAREST)
    canvas.save(a.out)
    print(f"{a.out} {canvas.size}")


if __name__ == '__main__':
    main()
