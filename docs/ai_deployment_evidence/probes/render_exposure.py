import json, sys
from PIL import Image, ImageDraw, ImageFont
board, expo, dst = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(board)); e = json.load(open(expo))
S = 14; W, H = 44, 60; pad_top = 70
img = Image.new("RGB", (W * S + 300, H * S + pad_top + 10), (30, 30, 30))
dr = ImageDraw.Draw(img, "RGBA")
def P(x, y): return (x * S, y * S + pad_top)
dr.rectangle([P(0, 0), P(W, H)], fill=(92, 84, 64))
for z in d["zones"]:
    c = (60, 140, 220, 40) if z["p"] == 1 else (220, 70, 70, 40)
    dr.polygon([P(*p) for p in z["pts"]], fill=c, outline=c[:3] + (200,))
for o in e["obs"]:
    x, y = P(*o); dr.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(255, 120, 120, 200))
maxs = max(1, max(c[2] for c in e["cells"]))
for c in e["cells"]:
    x, y, seen, seen15, dense, near = c
    if seen == 0: col = (30, 200, 80, 150)
    elif seen <= 3: col = (230, 220, 50, 150)
    elif seen <= 12: col = (240, 140, 40, 150)
    else: col = (230, 40, 40, 160)
    x0, y0 = P(x - 1, y - 1); x1, y1 = P(x + 1, y + 1)
    dr.rectangle([x0 + 1, y0 + 1, x1 - 1, y1 - 1], fill=col)
    if dense:
        dr.rectangle([x0 + 3, y0 + 3, x1 - 3, y1 - 3], outline=(255, 255, 255, 230), width=2)
for t in d["terrain"]:
    if len(t["pts"]) >= 3 and t["cls"] == "area":
        dr.polygon([P(*p) for p in t["pts"]], outline=(250, 230, 150, 200))
for t in d["terrain"]:
    if len(t["pts"]) >= 3 and t["cls"] != "area":
        dr.polygon([P(*p) for p in t["pts"]], fill=(15, 15, 15, 220))
for o in d["objectives"]:
    x, y = P(o["x"], o["y"]); dr.ellipse([x - 8, y - 8, x + 8, y + 8], outline=(255, 215, 0, 255), width=3)
try:
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    fs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
except Exception:
    f = fs = ImageFont.load_default()
dr.text((8, 8), "Proposed 'exposure field' for P1's zone, computed live with TerrainManager.model_visible_11e", fill=(255, 255, 255), font=f)
dr.text((8, 32), "Each 2\" cell: how many of %d enemy turn-1-reachable points (pink dots, <=10\" from enemy zone) have LoS to it. %d ms." % (e["observers"], e["ms"]), fill=(220, 220, 220), font=fs)
lx = W * S + 12; ly = pad_top
for col, k in [((30, 200, 80), "never visible (LoS shadow)"), ((230, 220, 50), "seen by 1-3 points"), ((240, 140, 40), "seen by 4-12 points"), ((230, 40, 40), "seen by 13+ points")]:
    dr.rectangle([lx, ly, lx + 14, ly + 14], fill=col); dr.text((lx + 20, ly), k, fill=(230, 230, 230), font=fs); ly += 22
dr.rectangle([lx + 2, ly + 2, lx + 12, ly + 12], outline=(255, 255, 255), width=2); dr.text((lx + 20, ly), "dense terrain cell: infantry Hidden", fill=(230, 230, 230), font=fs); ly += 16
dr.text((lx + 20, ly), "(none within 15\" of an enemy with LoS)", fill=(180, 180, 180), font=fs); ly += 30
safe = sum(1 for c in e["cells"] if c[2] == 0)
dr.text((lx, ly), "%d / %d cells are true LoS shadows" % (safe, len(e["cells"])), fill=(255, 255, 255), font=fs); ly += 18
dr.text((lx, ly), "-> park vehicles/monsters here", fill=(200, 200, 200), font=fs); ly += 18
dr.text((lx, ly), "%d dense cells -> infantry hide here" % sum(1 for c in e["cells"] if c[4]), fill=(255, 255, 255), font=fs)
img.save(dst); print("saved", dst, img.size)
