import json, sys
from PIL import Image, ImageDraw, ImageFont
src, dst, title = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(src))
S = 14  # px per inch
W, H = 44, 60
pad_top = 70
img = Image.new("RGB", (W * S + 260, H * S + pad_top + 10), (30, 30, 30))
dr = ImageDraw.Draw(img, "RGBA")
def P(x, y): return (x * S, y * S + pad_top)
dr.rectangle([P(0, 0), P(W, H)], fill=(92, 84, 64))
zc = {1: (60, 140, 220, 60), 2: (220, 70, 70, 60)}
for z in d["zones"]:
    dr.polygon([P(*p) for p in z["pts"]], fill=zc[z["p"]], outline=zc[z["p"]][:3] + (200,))
catc = {"dense": (40, 40, 40, 170), "light": (120, 120, 120, 120), "exposed": (160, 150, 120, 90)}
for t in d["terrain"]:
    if len(t["pts"]) < 3: continue
    if t["cls"] == "area":
        dr.polygon([P(*p) for p in t["pts"]], fill=catc.get(t["cat"], (100, 100, 100, 100)), outline=(250, 230, 150, 160))
for t in d["terrain"]:
    if len(t["pts"]) < 3: continue
    if t["cls"] != "area":
        dr.polygon([P(*p) for p in t["pts"]], fill=(15, 15, 15, 230))
for o in d["objectives"]:
    x, y = P(o["x"], o["y"])
    dr.ellipse([x - 8, y - 8, x + 8, y + 8], outline=(255, 215, 0, 255), width=3)
# models
counts = {}
for u in d["models"]:
    if u["all_hidden"]:
        col = (40, 220, 90, 255); k = "fully hidden"
    elif u["any_hidden"]:
        col = (250, 200, 40, 255); k = "partly hidden (unit still visible)"
    elif u["inf"]:
        col = (240, 60, 60, 255); k = "infantry in the open"
    else:
        col = (190, 120, 255, 255); k = "non-infantry (can't be hidden)"
    counts.setdefault((u["p"], k), 0); counts[(u["p"], k)] += 1
    for m in u["ms"]:
        x, y = P(m["x"], m["y"])
        if m["bt"] == "oval" and m["bw"] > 0:
            hw, hl = m["bl"] * S / 2, m["bw"] * S / 2
        else:
            hw = hl = max(2.5, m["r"] * S)
        outline = (255, 255, 255, 255) if u["p"] == 1 else (0, 0, 0, 255)
        dr.ellipse([x - hw, y - hl, x + hw, y + hl], fill=col, outline=outline, width=1)
try:
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    fs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
except Exception:
    f = fs = ImageFont.load_default()
dr.text((8, 8), title, fill=(255, 255, 255), font=f)
dr.text((8, 32), "blue zone = P1 (white outline), red zone = P2 (black outline); dark = dense terrain area, black = walls; gold rings = objectives", fill=(220, 220, 220), font=fs)
lx = W * S + 12; ly = pad_top
legend = [((40, 220, 90), "fully hidden"), ((250, 200, 40), "partly hidden (unit still visible)"), ((240, 60, 60), "infantry in the open"), ((190, 120, 255), "non-infantry (can't be hidden)")]
for c, k in legend:
    dr.rectangle([lx, ly, lx + 14, ly + 14], fill=c)
    dr.text((lx + 20, ly), k, fill=(230, 230, 230), font=fs)
    ly += 22
ly += 10
for p in (1, 2):
    dr.text((lx, ly), f"P{p} units on table:", fill=(255, 255, 255), font=fs); ly += 18
    for c, k in legend:
        dr.text((lx + 8, ly), f"{counts.get((p, k), 0)} {k.split(' (')[0]}", fill=c, font=fs); ly += 16
    ly += 10
img.save(dst)
print("saved", dst, img.size)
