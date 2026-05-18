#!/bin/bash
# SessionStart hook: install Godot + xvfb so windowed scenarios in
# 40k/tests/scenarios/ can be driven by the godot_mcp bridge in this
# Linux container. Mirrors the shim pattern used by
# .github/workflows/scenarios.yml so cloud sessions and CI behave
# identically.
#
# Only runs in Claude Code on the web (CLAUDE_CODE_REMOTE=true). On a
# local Mac this is a no-op — local devs already have godot in $HOME/bin.

set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="${GODOT_VERSION:-4.4.1}"
GODOT_BIN_NAME="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
GODOT_ZIP="${GODOT_BIN_NAME}.zip"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${GODOT_ZIP}"

INSTALL_DIR="$HOME/.cache/godot"
GODOT_BIN="$INSTALL_DIR/$GODOT_BIN_NAME"
SHIM="$HOME/bin/godot"

mkdir -p "$HOME/bin" "$INSTALL_DIR"

# Persist PATH for every shell the session opens. run_scenarios.sh and
# the pre-commit hook already export $HOME/bin to PATH, but interactive
# shells may not.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo 'export PATH="$HOME/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "[hook] not root and no sudo — cannot install apt packages" >&2
    exit 1
  fi
fi

# OS deps: xvfb (virtual display so capture_screenshot works), the X
# client libs Godot links against, the GL/EGL stack for opengl3.
APT_PKGS=(
  xvfb
  unzip
  curl
  ca-certificates
  x11-xserver-utils
  libxinerama1 libxcursor1 libxi6 libxrandr2
  libgl1 libglu1-mesa
  libegl1 libgles2
)

needs_install=0
for pkg in "${APT_PKGS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    needs_install=1
    break
  fi
done

if [ "$needs_install" -eq 1 ]; then
  echo "[hook] installing apt packages: ${APT_PKGS[*]}"
  # Some base images carry third-party PPAs that 403; the main Ubuntu
  # archive still refreshes, so we let update soft-fail and trust the
  # install step to surface any genuinely missing package.
  $SUDO apt-get update -qq || true
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends "${APT_PKGS[@]}"
fi

# Godot binary — download once, reuse from the container cache layer.
if [ ! -x "$GODOT_BIN" ]; then
  echo "[hook] downloading Godot ${GODOT_VERSION} from ${GODOT_URL}"
  tmp_zip="$INSTALL_DIR/$GODOT_ZIP"
  curl -fsSL -o "$tmp_zip" "$GODOT_URL"
  unzip -o -q "$tmp_zip" -d "$INSTALL_DIR"
  chmod +x "$GODOT_BIN"
  rm -f "$tmp_zip"
fi

# xvfb-run shim. Same flags as .github/workflows/scenarios.yml so the
# rendering path is identical to CI: virtual X server, opengl3 driver,
# dummy audio. The existing run_scenarios.sh calls `godot` on PATH —
# this shim makes that work transparently in the container.
cat > "$SHIM" <<EOF
#!/bin/bash
exec xvfb-run -a --server-args="-screen 0 1920x1080x24 +extension RANDR" \\
  "$GODOT_BIN" \\
  --rendering-driver opengl3 \\
  --audio-driver Dummy \\
  "\$@"
EOF
chmod +x "$SHIM"

echo "[hook] godot shim: $SHIM -> $GODOT_BIN"
"$SHIM" --version
