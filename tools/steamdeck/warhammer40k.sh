#!/usr/bin/env bash
#
# Self-updating launcher for the Warhammer 40k Godot game on Steam Deck / Linux.
#
# Add THIS script to Steam as a Non-Steam game (see tools/steamdeck/README.md).
# On every launch it:
#   1. checks the rolling "deck-latest" GitHub release for the newest commit,
#   2. downloads + installs the Linux build if it changed (or isn't installed),
#   3. launches the game.
# It plays fine offline: if GitHub is unreachable it just runs the installed
# copy. Save games live in the Godot user data dir and are never touched by an
# update, so updating never loses progress.
#
# Config via environment variables (all optional):
#   WH40K_INSTALL_DIR   where the game is installed (default: ~/Games/Warhammer40k)
#   WH40K_TOKEN_FILE    file containing a GitHub token, for a PRIVATE repo
#                       (default: ~/.config/warhammer40k/token)
#   WH40K_SKIP_UPDATE=1 skip the update check for this launch (play offline fast)
#
set -uo pipefail

REPO="BigBobbo/warhammer-40k-godot"
TAG="deck-latest"
ASSET="warhammer40k-linux.tar.gz"
BIN="40k-game.x86_64"

INSTALL_DIR="${WH40K_INSTALL_DIR:-$HOME/Games/Warhammer40k}"
BIN_PATH="$INSTALL_DIR/$BIN"
LOCAL_SHA_FILE="$INSTALL_DIR/BUILD_SHA"
BASE_URL="https://github.com/$REPO/releases/download/$TAG"

log() { echo "[wh40k-launcher] $*" >&2; }

mkdir -p "$INSTALL_DIR"

# Optional auth for a private repo: put a GitHub token (repo:read) in TOKEN_FILE.
TOKEN_FILE="${WH40K_TOKEN_FILE:-$HOME/.config/warhammer40k/token}"
AUTH=()
if [ -f "$TOKEN_FILE" ]; then
	AUTH=(-H "Authorization: Bearer $(tr -d '[:space:]' < "$TOKEN_FILE")")
fi

local_sha=""
[ -f "$LOCAL_SHA_FILE" ] && local_sha="$(tr -d '[:space:]' < "$LOCAL_SHA_FILE" 2>/dev/null || true)"

if [ "${WH40K_SKIP_UPDATE:-0}" != "1" ]; then
	# The BUILD_SHA asset is a tiny text file naming the newest commit; fetching
	# it first means we only pull the ~tens-of-MB tarball when something changed.
	remote_sha=""
	if remote_sha="$(curl -fsSL "${AUTH[@]}" "$BASE_URL/BUILD_SHA" 2>/dev/null | tr -d '[:space:]')" && [ -n "$remote_sha" ]; then
		log "installed=${local_sha:-none} latest=${remote_sha}"
		if [ ! -x "$BIN_PATH" ] || [ "$remote_sha" != "$local_sha" ]; then
			log "downloading update…"
			# Stage inside INSTALL_DIR so the final move is on the same filesystem
			# (atomic) and a failed/corrupt download never clobbers a working copy.
			tmp="$(mktemp -d "$INSTALL_DIR/.update.XXXXXX")"
			if curl -fSL "${AUTH[@]}" -o "$tmp/$ASSET" "$BASE_URL/$ASSET" \
				&& tar -xzf "$tmp/$ASSET" -C "$tmp" \
				&& [ -f "$tmp/$BIN" ]; then
				mv -f "$tmp/$BIN" "$BIN_PATH"
				chmod +x "$BIN_PATH"
				if [ -f "$tmp/BUILD_SHA" ]; then
					mv -f "$tmp/BUILD_SHA" "$LOCAL_SHA_FILE"
				else
					printf '%s\n' "$remote_sha" > "$LOCAL_SHA_FILE"
				fi
				log "updated to ${remote_sha}"
			else
				log "update download failed — keeping the current install"
			fi
			rm -rf "$tmp"
		else
			log "already up to date"
		fi
	else
		log "GitHub unreachable (offline?) — running the installed build if present"
	fi
fi

if [ ! -x "$BIN_PATH" ]; then
	log "ERROR: no build installed and nothing to download. Connect to the internet and launch again."
	exit 1
fi

log "launching $BIN_PATH"
exec "$BIN_PATH" "$@"
