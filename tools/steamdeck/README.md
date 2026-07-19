# Play on Steam Deck (auto-updating, full controller support)

This is the easiest way to run the game on a Steam Deck and **always get the
newest build** — no itch.io app required.

**How it works**

1. GitHub Actions builds a native **Linux** binary on every push to `main`
   (`.github/workflows/steamdeck-build.yml`) and publishes it to a single,
   rolling GitHub Release tagged **`deck-latest`**.
2. On the Deck you run a tiny launcher script (`warhammer40k.sh`) that, on every
   launch, checks that release, downloads the new build if the commit changed,
   then starts the game. First launch installs it; every launch after that
   self-updates.
3. You add that **launcher** to Steam as a *Non-Steam game*. That gives you
   Steam Input (the Deck's sticks/buttons/trackpads), the Steam overlay, and the
   Steam on-screen keyboard — and the game already has full native gamepad
   support, so it reads the Deck as an Xbox controller and just works.

Because it's a native Linux build you do **not** need Proton/compatibility.

---

## One-time setup (in Desktop Mode)

Hold the **power button → Switch to Desktop**, then open **Konsole** (the
terminal) and run:

```bash
mkdir -p ~/Games/Warhammer40k
curl -fSL -o ~/Games/Warhammer40k/warhammer40k.sh \
  https://raw.githubusercontent.com/BigBobbo/warhammer-40k-godot/main/tools/steamdeck/warhammer40k.sh
chmod +x ~/Games/Warhammer40k/warhammer40k.sh
```

(You can run it once from the terminal to do the first download and confirm it
launches: `~/Games/Warhammer40k/warhammer40k.sh`)

### Add it to Steam

1. In **Steam** (Desktop Mode) → **Games → Add a Non-Steam Game to My Library**.
2. Click **Browse…**, navigate to `~/Games/Warhammer40k/`, switch the file
   filter to **All Files**, pick **`warhammer40k.sh`**, and **Add Selected
   Programs**.
3. In your library, right-click the new entry → **Properties**:
   - Rename it to **Warhammer 40k**.
   - Confirm **Start In** is `~/Games/Warhammer40k/` (Steam usually fills this in).
   - Optional: set nice artwork (grab from SteamGridDB later).

That's it. Switch back to **Game Mode** and launch it like any other game.

### Pick a controller layout

The first time you open it in Game Mode, press **Steam (⋯) → Controller
Settings** and choose a template:

- **Gamepad with Mouse Trackpad** *(recommended)* — the game's whole scheme
  works from the sticks/buttons, and the **right trackpad becomes a real mouse**
  as a 100% fallback for anything fiddly.
- **Gamepad** — pure controller, no trackpad mouse.

Both work; the game adapts its on-screen button hints to whatever you're using.

---

## In-game controls (native gamepad scheme)

| Input | What it does |
|---|---|
| **Left stick** | Virtual cursor (click/drag anything); while a model is "picked up", steer it |
| **Right stick** | Pan the battle camera |
| **LT / RT** | Zoom out / in |
| **LB / RB** | Cycle units ◀ ▶ (and cycle targets once an attack is armed); rotate a carried model |
| **A** | Select / confirm / left-click / drop a carried model |
| **B** | Cancel / back / right out of a menu |
| **X** | Skip the current unit / secondary action / undo last placed model |
| **Y** | Open the highlighted unit's datasheet |
| **D-pad** | Move focus into and around the side panels; hop between models in a unit |
| **Menu (≡)** | End phase / confirm the unit's move (asks to confirm) |
| **View (⧉)** | Controls / shortcut overlay |

A hint bar along the bottom always shows what the buttons do right now. The
whole game is reachable with the stick's virtual cursor even where a native
shortcut doesn't exist yet.

### Typing (multiplayer address, save names, etc.)

For the few text fields, press **Steam (⋯) + X** to bring up the Steam on-screen
keyboard, then type with the touchscreen or trackpads. (An in-game controller
keyboard is on the roadmap; until then the Steam OSK covers it.)

---

## Updating

**Automatic.** Every time you launch from Game Mode, the launcher grabs the
newest `main` build before starting. When you push new code to GitHub, the next
launch on the Deck has it.

- Want to launch instantly without the update check (e.g. no Wi-Fi)? Set
  `WH40K_SKIP_UPDATE=1` — in Steam **Properties → Launch Options**:
  `WH40K_SKIP_UPDATE=1 %command%`.
- Your **saves are safe across updates** — they live in Godot's user-data
  directory (`~/.local/share/godot/app_userdata/40k/`), which the launcher never
  touches. Only the game binary is replaced.

---

## Troubleshooting

- **"no build installed and nothing to download"** — you launched offline before
  the first successful install. Connect to Wi-Fi and launch once.
- **Nothing happens / need logs** — run the launcher from Konsole to see its
  output: `~/Games/Warhammer40k/warhammer40k.sh`. Game logs are under
  `~/.local/share/godot/app_userdata/40k/logs/`.
- **Force a clean reinstall** — delete the install dir and relaunch:
  `rm -rf ~/Games/Warhammer40k/40k-game.x86_64 ~/Games/Warhammer40k/BUILD_SHA`.
- **Private repo?** This repo is public, so no token is needed. If it ever goes
  private, create a fine-grained token with *Contents: read* and save it to
  `~/.config/warhammer40k/token`; the launcher will use it automatically.
- **Change where it installs** — set `WH40K_INSTALL_DIR` (e.g. to the SD card):
  `WH40K_INSTALL_DIR=/run/media/mmcblk0p1/wh40k %command%` in Launch Options.

---

## Config reference (launcher environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `WH40K_INSTALL_DIR` | `~/Games/Warhammer40k` | Where the game installs |
| `WH40K_SKIP_UPDATE` | `0` | `1` = skip the update check this launch |
| `WH40K_TOKEN_FILE` | `~/.config/warhammer40k/token` | GitHub token file (private repo only) |
