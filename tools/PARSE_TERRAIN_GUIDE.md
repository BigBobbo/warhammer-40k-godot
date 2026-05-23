# Terrain Layout Parsing — Workflow Guide

How to parse a GW Chapter Approved Tournament Layout reference image into
a `40k/terrain_layouts/layout_*.json` file. Written after building
`layout_parse_test.json` from `layout2_reference.jpg`.

## Tools (in `tools/`)

| Tool | Purpose |
|---|---|
| `render_layout.py` | Render a layout JSON to PNG. `--horizontal` rotates to match the source image orientation for side-by-side comparison. |
| `detect_pieces.py` | Color-segment a reference image to find piece footprints. Outputs centers/sizes/angles in inches. |
| `detect_to_json.py` | Hard-coded list of detected pieces → symmetrized JSON. Edit the `DETECTED` list at the top. |
| `align_pieces.py` | Targeted edge-alignment edits in horizontal coords; auto-propagates to the 180-degree mirror. |
| `apply_walls.py` | Hand-encodes walls per top-half tall piece, mirrors to the bottom half. Edit `WALLS_TOP_HALF` dict. |
| `detect_walls.py` | Attempted automated wall detection. Use only as a hint; the hatching defeats it on larger pieces. |

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

After the JSON looks right, prove it loads in the actual game:

```bash
# Edit tests/scenarios/visual/parse_test_terrain_screenshot.json to load
# your new layout id, then:
export DISPLAY=:99
bash 40k/tests/run_scenario.sh tests/scenarios/visual/parse_test_terrain_screenshot.json
```

Screenshot lands at `~/.local/share/godot/app_userdata/40k/test_results/scenarios/<id>_<label>.png`.

## To register a layout in the game's UI

Currently `TerrainManager._preload_layout_metadata()` only scans
`layout_1`..`layout_8`. To add a new layout to the in-game dropdown:

1. Name the file `layout_<N>.json` (or change the preload loop)
2. Add the option to `scripts/MainMenu.gd`'s terrain dropdown

For pure parse-tests (just iterating against the source), keep the name
free-form (e.g. `layout_parse_test.json`) and load it via `execute_script`
in a scenario.
