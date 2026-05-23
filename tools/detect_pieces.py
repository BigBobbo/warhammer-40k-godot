#!/usr/bin/env python3
"""Detect terrain pieces in a reference layout image by color segmentation.

Outputs piece bounding boxes in inches, classified as:
  - "tall"  = gray hatched
  - "low"   = blue rectangle

Assumes the board is on a light gray background with the
"TERRAIN LAYOUT N" tab on the LEFT (cropped out via --left-crop).

Usage:
    python3 tools/detect_pieces.py 40k/terrain_layouts/source/layout2_reference.jpg \\
        --left-crop 0.06 --board-in 60x44 --debug /tmp/detect_debug.png
"""

import argparse
import json
import math
from collections import deque

from PIL import Image, ImageDraw, ImageFont


def classify(rgb):
    r, g, b = rgb[:3]
    # Blue rectangles: very specific dark blue ~ (0, 90, 135)
    if r < 40 and 60 < g < 130 and 100 < b < 170 and b > r + 60:
        return "low"
    # Gray ruins: dark gray (hatched stripes + smooth walls)
    # Stripes ~ (95, 99, 100), walls similar; background is ~ (230, 230, 230)
    if 50 <= r <= 130 and 50 <= g <= 130 and 50 <= b <= 130 \
            and abs(r - g) < 15 and abs(g - b) < 15 and abs(r - b) < 15:
        return "tall"
    return None


def flood(mask, x0, y0, W, H):
    """Iterative flood fill on a 2D bool mask. Returns the component pixels."""
    q = deque([(x0, y0)])
    pts = []
    while q:
        x, y = q.popleft()
        if x < 0 or x >= W or y < 0 or y >= H:
            continue
        if not mask[y][x]:
            continue
        mask[y][x] = False
        pts.append((x, y))
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))
    return pts


def dilate(mask, W, H, k=2):
    """Crude box dilation to glue together hatched-stripe components."""
    out = [row[:] for row in mask]
    for _ in range(k):
        new = [[False] * W for _ in range(H)]
        for y in range(H):
            for x in range(W):
                if out[y][x]:
                    new[y][x] = True
                    if x + 1 < W: new[y][x + 1] = True
                    if x - 1 >= 0: new[y][x - 1] = True
                    if y + 1 < H: new[y + 1][x] = True
                    if y - 1 >= 0: new[y - 1][x] = True
        out = new
    return out


def erode(mask, W, H, k=1):
    """Box erosion."""
    out = [row[:] for row in mask]
    for _ in range(k):
        new = [[False] * W for _ in range(H)]
        for y in range(H):
            for x in range(W):
                if out[y][x] and (x > 0 and out[y][x-1]) and (x+1 < W and out[y][x+1]) \
                        and (y > 0 and out[y-1][x]) and (y+1 < H and out[y+1][x]):
                    new[y][x] = True
        out = new
    return out


def min_area_rect(pts):
    """Rotating-calipers minimum-area enclosing rectangle.
    Returns (cx, cy, w, h, angle_deg). Angle is the rotation of the
    rectangle's first edge from the +x axis (CW positive in image coords).
    """
    if len(pts) < 3:
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        return ((min(xs)+max(xs))/2, (min(ys)+max(ys))/2,
                max(1, max(xs)-min(xs)), max(1, max(ys)-min(ys)), 0.0)

    # Convex hull via Andrew's monotone chain
    pts_sorted = sorted(set(pts))
    if len(pts_sorted) < 3:
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        return ((min(xs)+max(xs))/2, (min(ys)+max(ys))/2,
                max(1, max(xs)-min(xs)), max(1, max(ys)-min(ys)), 0.0)

    def cross(o, a, b):
        return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])

    lower = []
    for p in pts_sorted:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(pts_sorted):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]

    best = None
    n = len(hull)
    for i in range(n):
        ax, ay = hull[i]
        bx, by = hull[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        L = math.hypot(ex, ey)
        if L < 1e-6: continue
        ux, uy = ex / L, ey / L
        vx, vy = -uy, ux
        umin = umax = (hull[0][0] - ax) * ux + (hull[0][1] - ay) * uy
        vmin = vmax = (hull[0][0] - ax) * vx + (hull[0][1] - ay) * vy
        for hx, hy in hull[1:]:
            du = (hx - ax) * ux + (hy - ay) * uy
            dv = (hx - ax) * vx + (hy - ay) * vy
            if du < umin: umin = du
            elif du > umax: umax = du
            if dv < vmin: vmin = dv
            elif dv > vmax: vmax = dv
        w = umax - umin
        h = vmax - vmin
        area = w * h
        if best is None or area < best[0]:
            cu = (umin + umax) / 2
            cv = (vmin + vmax) / 2
            cx = ax + ux * cu + vx * cv
            cy = ay + uy * cu + vy * cv
            angle = math.degrees(math.atan2(uy, ux))
            best = (area, cx, cy, w, h, angle)
    _, cx, cy, w, h, angle = best
    # Canonicalize: w is the LONGER side, angle is along it
    if w < h:
        w, h = h, w
        angle += 90.0
    angle = ((angle + 90) % 180) - 90  # in [-90, 90)
    return cx, cy, w, h, angle


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--left-crop", type=float, default=0.06,
                    help="Fraction of image width to crop from LEFT (tab label).")
    ap.add_argument("--top-crop", type=float, default=0.0)
    ap.add_argument("--right-crop", type=float, default=0.0)
    ap.add_argument("--bottom-crop", type=float, default=0.0)
    ap.add_argument("--board-in", default="60x44",
                    help="Board dimensions in inches (W x H), horizontal orientation.")
    ap.add_argument("--min-area-in", type=float, default=6.0,
                    help="Minimum piece area in square inches.")
    ap.add_argument("--debug", help="Optional debug overlay PNG path.")
    args = ap.parse_args()

    img = Image.open(args.image).convert("RGB")
    W0, H0 = img.size
    L = int(W0 * args.left_crop)
    T = int(H0 * args.top_crop)
    R = int(W0 * (1 - args.right_crop))
    B = int(H0 * (1 - args.bottom_crop))
    img = img.crop((L, T, R, B))
    W, H = img.size
    print(f"Cropped image: {W}x{H}")

    bw_in, bh_in = map(float, args.board_in.lower().split("x"))
    px_per_in = (W / bw_in + H / bh_in) / 2
    print(f"Board: {bw_in}x{bh_in} in  ->  ~{px_per_in:.1f} px/in")

    pixels = img.load()

    # Build per-class masks (downsample for speed)
    SCALE = 2
    Ws, Hs = W // SCALE, H // SCALE
    mask_low = [[False] * Ws for _ in range(Hs)]
    mask_tall = [[False] * Ws for _ in range(Hs)]
    for y in range(Hs):
        for x in range(Ws):
            cls = classify(pixels[x * SCALE, y * SCALE])
            if cls == "low":
                mask_low[y][x] = True
            elif cls == "tall":
                mask_tall[y][x] = True

    # First erode tall mask to break thin gray bridges between pieces (the
    # solid-color walls of one piece can chain into a neighbor through narrow
    # paths because they're the same gray). Then dilate to re-close hatching.
    mask_tall_e = erode(mask_tall, Ws, Hs, k=1)
    mask_tall_d = dilate(mask_tall_e, Ws, Hs, k=3)
    mask_low_d = dilate(mask_low, Ws, Hs, k=0)

    min_area_px = args.min_area_in * (px_per_in ** 2) / (SCALE ** 2)

    def extract(mask, label):
        out = []
        work = [row[:] for row in mask]
        for y in range(Hs):
            for x in range(Ws):
                if work[y][x]:
                    pts = flood(work, x, y, Ws, Hs)
                    if len(pts) < min_area_px:
                        continue
                    pts_full = [(p[0] * SCALE, p[1] * SCALE) for p in pts]
                    # rotated min-area rect
                    cx_r, cy_r, w_r, h_r, ang_r = min_area_rect(pts_full)
                    # axis-aligned bbox
                    xs = [p[0] for p in pts_full]
                    ys = [p[1] for p in pts_full]
                    xmin, xmax = min(xs), max(xs)
                    ymin, ymax = min(ys), max(ys)
                    cx_a = (xmin + xmax) / 2
                    cy_a = (ymin + ymax) / 2
                    w_a = xmax - xmin
                    h_a = ymax - ymin
                    fill_r = (len(pts) * SCALE * SCALE) / max(1, w_r * h_r)
                    # Prefer AABB when:
                    #  - rotated rect is already near-axis-aligned, OR
                    #  - the rotated rect is poorly filled (L-shape / merge),
                    #    in which case the tilt is an artifact of an empty
                    #    diagonal inside the bbox, not a real piece rotation.
                    use_aabb = (
                        abs(ang_r) < 15 or abs(ang_r) > 75
                        or abs(abs(ang_r) - 90) < 15
                        or fill_r < 0.7
                    )
                    if use_aabb:
                        cx, cy = cx_a, cy_a
                        if w_a >= h_a:
                            w, h, ang = w_a, h_a, 0.0
                        else:
                            w, h, ang = h_a, w_a, 90.0
                    else:
                        cx, cy, w, h, ang = cx_r, cy_r, w_r, h_r, ang_r
                    out.append({
                        "kind": label,
                        "cx_px": cx, "cy_px": cy,
                        "w_px": w, "h_px": h, "angle_deg": ang,
                        "area_px": len(pts) * SCALE * SCALE,
                        "fill_ratio": (len(pts) * SCALE * SCALE) / max(1, w * h),
                    })
        return out

    tall = extract(mask_tall_d, "tall")
    low = extract(mask_low_d, "low")

    # Convert to inches (px -> in)
    pieces = []
    for p in tall + low:
        pieces.append({
            "kind": p["kind"],
            "cx_in": round(p["cx_px"] / px_per_in, 2),
            "cy_in": round(p["cy_px"] / px_per_in, 2),
            "w_in": round(p["w_px"] / px_per_in, 2),
            "h_in": round(p["h_px"] / px_per_in, 2),
            "angle_deg": round(p["angle_deg"], 1),
            "fill_ratio": round(p["fill_ratio"], 2),
        })
    pieces.sort(key=lambda p: (p["cy_in"], p["cx_in"]))

    print(f"\nDetected {len(tall)} tall + {len(low)} low = {len(pieces)} pieces:")
    for i, p in enumerate(pieces):
        print(f"  [{i:2d}] {p['kind']:5s} center=({p['cx_in']:5.1f},{p['cy_in']:5.1f}) "
              f"size={p['w_in']:5.1f}x{p['h_in']:4.1f} angle={p['angle_deg']:+.1f} "
              f"fill={p['fill_ratio']}")

    if args.debug:
        out = img.copy()
        d = ImageDraw.Draw(out, "RGBA")
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
        except Exception:
            font = ImageFont.load_default()
        for i, p in enumerate(pieces):
            cx = p["cx_in"] * px_per_in
            cy = p["cy_in"] * px_per_in
            w = p["w_in"] * px_per_in / 2
            h = p["h_in"] * px_per_in / 2
            ang = math.radians(p["angle_deg"])
            cos_a, sin_a = math.cos(ang), math.sin(ang)
            corners = []
            for lx, ly in [(-w, -h), (w, -h), (w, h), (-w, h)]:
                corners.append((cx + lx * cos_a - ly * sin_a,
                                cy + lx * sin_a + ly * cos_a))
            color = (255, 200, 0, 255) if p["kind"] == "tall" else (0, 200, 255, 255)
            d.polygon(corners, outline=color, width=2)
            d.text((cx, cy), str(i), fill=(255, 255, 255), font=font, anchor="mm")
        out.save(args.debug)
        print(f"\ndebug overlay: {args.debug}")

    return pieces


if __name__ == "__main__":
    main()
