# Terrain Layout Parsing — Workflow Guide

How to parse a GW Chapter Approved Tournament Layout reference image into
a `40k/terrain_layouts/layout_*.json` file. Written after building
`layout_parse_test.json` from `layout2_reference.jpg`.

## Tools (in `tools/`)

### Catalog-based pipeline (preferred — use this for new layouts)

| Tool | Purpose |
|---|---|
| `catalog.py` | Defines the canonical set of 18 pieces every layout uses. |
| `detect_pieces_precise.py` | Background-segmentation blob detector. Calibrates px/inch from board pixel dimensions. Emits clean JSON with `--json-out`. |
| `match_to_catalog.py` | Snaps each detected blob to a canonical piece. Filters annotations by score/edge/fill. Merges fragments. Fills gaps via 180-deg symmetry. Pairs adjacent (8x6 + 4x6) and (6.5x5 + 3.5x5). Relabels lows by pairing. |
| `matches_to_json.py` | Snaps paired pieces to share their canonical edge, converts to vertical board coords, applies walls per slot. Outputs a complete layout JSON. |
| `render_layout.py` | Renders a layout JSON to PNG. `--horizontal` rotates to match the source. |

### Legacy / supplementary

| Tool | Purpose |
|---|---|
| `detect_pieces.py` | Older color-segmentation detector (kept for reference). |
| `detect_to_json.py` | Older hand-coded DETECTED list → JSON. Useful when you want to override the matcher's auto-output. |
| `align_pieces.py` | Targeted edge-alignment edits with auto 180-mirror propagation. |
| `apply_walls.py` | Hand-encodes walls per piece. Use this when you want non-canonical wall layouts (e.g. partial walls). |
| `detect_walls.py` | Attempted automated wall detection — defeated by hatching on larger pieces. Kept for reference. |

## The canonical catalog (every layout uses these 18 pieces)

| Slot | Height | Size | Count | Wall style | Paired with |
|---|---|---|---|---|---|
| `low_6x4` | low | 6×4 | 6 | none | standalone |
| `tall_12x6_C` | tall | 12×6 | 2 | C-shape (long base + 2 arms) | standalone |
| `tall_12x6_L` | tall | 12×6 | 2 | L-shape (2 perpendicular walls) | standalone |
| `tall_8x6` | tall | 8×6 | 2 | L-shape | `low_4x6` (shared 6″ edge → combined 12×6) |
| `low_4x6` | low | 6×4 | 2 | none | `tall_8x6` |
| `tall_6.5x5` | tall | 6.5×5 | 2 | L-shape | `low_3.5x5` (shared 5″ edge → combined 10×5) |
| `low_3.5x5` | low | 5×3.5 | 2 | none | `tall_6.5x5` |

Per layout: 8 tall + 10 low = 18 pieces in 9 symmetric pairs.

## Catalog-based workflow (the new way)

```bash
# 1. Save source image
cp /path/to/layout_X.png 40k/terrain_layouts/source/layoutX_reference.png

# 2. Detect blobs
python3 tools/detect_pieces_precise.py \
    40k/terrain_layouts/source/layoutX_reference.png \
    --json-out /tmp/blobs.json --out /tmp/detect_debug.png

# 3. Match blobs to canonical pieces
python3 tools/match_to_catalog.py /tmp/blobs.json > /tmp/matches.json 2>&1

# 4. Convert to layout JSON
python3 tools/matches_to_json.py /tmp/matches.json \
    40k/terrain_layouts/layout_parse_test_X.json \
    --id layout_parse_test_X --name "Layout X"

# 5. Render and compare
python3 tools/render_layout.py \
    40k/terrain_layouts/layout_parse_test_X.json \
    /tmp/render.png --horizontal

# 6. Iterate: if blobs are wrong, refine match_to_catalog.py thresholds.
#    If walls are wrong, override in matches_to_json.py's make_walls()
#    or use the legacy apply_walls.py to hand-encode.
```

Why this is dramatically better than the old eyeball workflow:
- Sizes are EXACTLY canonical (12×6, 8×6, etc.) — not noisy AABB measurements.
- Rotation is inferred deterministically: square AABB → 45-deg rotated rect; otherwise axis-aligned.
- Walls applied automatically by slot, no hand-encoding.
- Paired pieces snap to their canonical shared edge (no drift).
- Per-layout effort: ~5 minutes vs ~1 hour of iteration.

### What you still might need to override

- **Wall style for the four 12×6 tall pieces**: matcher defaults all to C. The catalog says 2 are C and 2 are L. Look at the source and edit the slot of two pieces from `tall_12x6_C` → `tall_12x6_L` in the matcher output before the JSON conversion (or post-edit the JSON directly).
- **Wall orientation**: `make_walls()` produces walls in a canonical orientation (e.g. C facing south). The bottom-half mirrors may need 180-rotated walls. Easiest fix: post-edit individual pieces if their walls look wrong in the comparison render.

## Coordinate Systems

## Coordinate Systems (these MUST stay straight)

- **Source image (horizontal)**: 60" wide × 44" tall, x right, y down. Centre `(30, 22)`.
  The image has a "TERRAIN LAYOUT N" tab on the left taking ~6% of the width — crop it.
  Each fine grid square on the source = 1 inch.
- **Game board (vertical)**: 44" wide × 60" tall. Centre `(22, 30)`.
- **Conversion** horizontal → vertical (90° CCW image rotation):
  - `x_v = y_h`
  - `y_v = 60 - x_h`
  - `rotation_v = (rotation_h + 90) mod 180`  *(rectangles are 180-invariant)*
- **Inverse** vertical → horizontal: `x_h = 60 - y_v`, `y_h = x_v`.

## Piece-local frame (for walls)

- Origin = piece centre. Local `+x` = the `size[0]` direction (long axis if `size[0] >= size[1]`).
- Local `+y` = the `size[1]` direction.
- Local edges:
  - north: `y = -size[1]/2`
  - south: `y = +size[1]/2`
  - west:  `x = -size[0]/2`
  - east:  `x = +size[0]/2`
- A wall is `{"local_start": [x,y], "local_end": [x,y], "type": "solid", "blocks_los": true}`.

## World-direction lookup (depends on `rotation` in HORIZONTAL view)

Mapping table — **memorise this**:

| `rot_h` | local north | local south | local east | local west |
|---|---|---|---|---|
|  0° | world UP    | world DOWN  | world RIGHT | world LEFT  |
| 90° | world RIGHT | world LEFT  | world DOWN  | world UP    |
| -90° | world LEFT  | world RIGHT | world UP    | world DOWN  |
| 42° (diagonals) | world upper-right | world lower-left | world lower-right | world upper-left |

The JSON stores `rotation_v`. To get `rot_h`: `rot_h = rotation_v - 90`. So a JSON
`rotation: 0` piece has `rot_h = -90` (vertical orientation in source) — use the
`-90°` row above when reading walls.

## Symmetry rule

The maps have **180° rotational symmetry** around the board centre.
NOT mirror reflection.

- Every piece at `(x, y)` has a counterpart at `(44-x, 60-y)`, same size, same rotation
  (rectangles are 180-invariant so `rot + 180 ≡ rot`).
- Tilted pieces (the two centre diagonals) tilt the **same way** — they are NOT mirror images.
- Wall mirrors: a wall on local north of piece A becomes a wall on local south of piece B
  (the 180-mirror). `(x_local, y_local) → (-x_local, -y_local)` under 180° rotation in local frame.

## Workflow

### 1. Get the source image on disk

If the user pasted an image into chat, it's base64-encoded in the session log:

```bash
ls /root/.claude/projects/-home-user-warhammer-40k-godot/*.jsonl
```

The user-pasted image is in line 1, `message.content[]`, type `image`, `source.data`
is base64. Decode it to `40k/terrain_layouts/source/<name>.jpg`.

### 2. Detect piece footprints

```bash
python3 tools/detect_pieces.py 40k/terrain_layouts/source/<name>.jpg \
    --left-crop 0.06 --board-in 60x44 --debug /tmp/detect_debug.png
```

Look at `/tmp/detect_debug.png`. If pieces are merged or fragmented:
- Tighten color thresholds in `is_wall_pixel` / `classify` for your image
- Adjust erosion `k=2` and dilation `k=3` in the `extract()` loops
- The minimum component area is 6 in² by default — raise if there are noise blobs

Expected output: a list of `(kind, cx_h, cy_h, w_long, h_short, angle_h_deg)`.

### 3. Symmetrise and emit JSON

Copy the detected-piece list into `tools/detect_to_json.py`'s `DETECTED` array,
then run:

```bash
python3 tools/detect_to_json.py 40k/terrain_layouts/layout_<name>.json
```

This pairs each piece with its 180-mirror, averages positions/sizes for exact
symmetry, and writes the JSON.

### 4. Render and compare side-by-side

```bash
python3 tools/render_layout.py 40k/terrain_layouts/layout_<name>.json \
    /tmp/render.png --horizontal
```

Then build a comparison image (see `compare_*.png` examples for the pattern):
source on the left, my render on the right, both scaled to the same height.
Send to the user.

### 5. Apply targeted alignment fixes

For specific edge-alignment / touching corrections, edit `tools/align_pieces.py`
to add `update(piece_id, position=..., size=...)` calls. The script propagates
each change to the 180-mirror automatically and verifies symmetry.

### 6. Encode walls — DO THIS PER PIECE

Walls are too noisy to auto-detect. Do it manually but precisely:

**A. Zoom into each tall piece individually**, aligned so its long axis is horizontal:

```python
# In a quick python script:
from PIL import Image
img = Image.open('...source.jpg').convert('RGB')
img = img.crop((int(img.width*0.06), 0, img.width, img.height))

# For each piece: crop around it, rotate by ang_deg, upscale 5-6x
# (see iter6 commit for the extract_aligned() helper)
```

**B. Read the walls visually**, noting:
- Which edge(s) have walls (top / bottom / left / right of the aligned image)
- For each wall, is it full-length or partial?
- For partial walls, which corner does it start at?
- For C/U shapes: are the arms inset from the ends?

**C. Convert "aligned edges" → "piece-local edges"**

This is the part where I keep making mistakes. The image rotation to align maps:
- aligned UP / DOWN ↔ piece-local short axis edges
- aligned LEFT / RIGHT ↔ piece-local long axis edges

But the specific N/S/E/W mapping depends on the rotation direction and the piece's
`rot_h`. **The safest way is to check by rendering and asking the user to verify**.

**D. Edit `tools/apply_walls.py`** — add an entry to `WALLS_TOP_HALF` for each top-half
tall piece, plus an entry in `ROT180` and `make_wall_mirror` if you introduce a new
wall edge type.

### 7. Common wall shapes I've seen

- **Single edge wall**: 1 wall along one edge. Easy.
- **L-shape** (e.g., tall_01 in Layout 2): two full-length walls on adjacent edges,
  meeting at one corner. Mirror flips the corner across both axes.
- **Asymmetric L** (tall_03, tall_05): one full + one partial perpendicular wall,
  hinging on a specific corner.
- **C-shape on orthogonal piece** (NOT what tall_01 turned out to be): long base
  + two short arms perpendicular at both ends.
- **C-shape on diagonal piece** (tall_07/08): same as above BUT the long base does
  NOT extend to the corners — it runs only between the arms. Arms are inset 1.5"
  from each end and extend 3" into the piece.

### 8. After every change

- Re-render with `--horizontal`
- Build side-by-side comparison
- Send to user for verification
- Wait for specific feedback before guessing what's next

## Gotchas I hit

1. **PIL rotate direction**: `Image.rotate(+90)` is CCW. For a vertical piece in
   source, rotating the image by `+ang_deg` (where `ang_deg = 90` for that piece's
   world angle) aligns the long axis horizontally. Don't confuse this with the
   piece's local frame, which is intrinsic and unchanged.

2. **Hatching defeats color-based wall detection**: at 13 px/inch the JPEG
   compression blurs hatching stripes into "darkish" pixels everywhere. The
   wall mask detected almost the whole piece interior. Hand-encoding walls is
   faster than trying to fix the detector.

3. **"Symmetric" tilted pieces tilt the SAME way**: under 180° rotation a rectangle
   is invariant, so `rot 42°` and `rot 42° + 180° = 222°` look identical. The
   centre diagonals in Layout 2 are both tilted at `+42°` (in horizontal coords),
   NOT mirror images of each other.

4. **The "TERRAIN LAYOUT N" tab on the left is NOT part of the board**.
   Crop it (`--left-crop 0.06` is right for the GW images I had).

5. **Mission objectives (red bullseyes) are NOT terrain**. Don't include them
   in the layout JSON — they're placed at deployment time.

6. **Don't trust the detector's rotation for L-shaped pieces**: an L-shaped
   footprint's min-area-rect is tilted (because the L has empty space inside its
   bounding box). The fill-ratio check in `detect_pieces.py` falls back to the
   axis-aligned bbox for these cases.

## In-game verification

NOTE: parser outputs are no longer committed — the legacy hand-made layouts
(`layout_1`..`layout_8`, `layout_parse_test*`) and their visual scenario were
removed from the repo; the converted official 11e layouts
(`index_11e.json` + per-matchup files) are the only committed terrain. The
tools in this guide still work for iterating on a parse locally; render the
result without Godot via:

```bash
python3 tools/render_layout.py 40k/terrain_layouts/<your_layout>.json out.png
```

or load it in a running game with the MCP bridge
(`execute_script`: `TerrainManager.load_terrain_layout("<your_layout>")`) and
`capture_screenshot`.

## To register a layout in the game's UI

The in-game dropdown is driven by the official 11e layout registry:
`TerrainManager._preload_11e_layout_index()` reads
`40k/terrain_layouts/index_11e.json`, and the main menu offers the current
Force-Disposition matchup's variants (see
`MainMenu._refresh_matchup_terrain_options`). To ship a new layout, add its
JSON to `40k/terrain_layouts/` and register it in `index_11e.json` with a
`mission_matchup_id` + `variant`.

For pure parse-tests (just iterating against the source), keep the name
free-form and load it via `execute_script` — unregistered layout JSONs still
load by filename through `TerrainManager.load_terrain_layout()`.
