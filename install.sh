#!/bin/sh
# podbay self-host installer — one command:
#   curl -fsSL <public-url>/install.sh | sh
# Checks Docker, drops a self-contained compose.yaml into ./podbay, pulls + starts everything,
# prints the URL. No repo clone, no build. Override: PODBAY_PORT, PODBAY_DIR, PODBAY_COMPOSE_URL.
set -eu

PORT="${PODBAY_PORT:-8080}"
DIR="${PODBAY_DIR:-podbay}"
COMPOSE_URL="${PODBAY_COMPOSE_URL:-https://raw.githubusercontent.com/podbay-cloud/install/main/compose.yaml}"

say() { printf '%s\n' "$*"; }
die() { printf '\n✗ %s\n' "$*" >&2; exit 1; }

# --- Prereqs (an installer can DETECT these but not install Docker for you) ---
command -v docker >/dev/null 2>&1 || die "Docker isn't installed → https://docs.docker.com/get-docker/"
docker info >/dev/null 2>&1 || die "Docker is installed but not running — start it and re-run."
docker compose version >/dev/null 2>&1 || die "The Docker Compose plugin is missing (update Docker Desktop / install docker-compose-plugin)."

# --- Compose file: use one sitting next to this script (repo checkout), else download ---
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
mkdir -p "$DIR"
if [ -f "$SELF_DIR/compose.yaml" ]; then
  cp "$SELF_DIR/compose.yaml" "$DIR/compose.yaml"
  say "Using compose.yaml from $SELF_DIR"
else
  say "Fetching compose.yaml…"
  curl -fsSL "$COMPOSE_URL" -o "$DIR/compose.yaml" || die "couldn't download the compose file from $COMPOSE_URL"
fi

# --- Up (pulls images on first run) ---
say "Starting podbay on :$PORT (first run pulls the images)…"
( cd "$DIR" && PODBAY_PORT="$PORT" docker compose up -d )

cat <<EOF

✅ podbay is up → http://localhost:$PORT
   Create a pod, sign in with your Claude account, and you're in.

   Manage it (from ./$DIR):
     docker compose logs -f serve     # daemon / provisioning
     docker compose down              # stop   ·   down -v also wipes state
   VPS: put it behind your domain (edit the Caddy block in compose.yaml) + a login gate.
EOF
