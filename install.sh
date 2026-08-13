#!/bin/sh
# podbay self-host installer — one command:
#   curl -fsSL <public-url>/install.sh | sh
# Checks your machine has what it needs, drops a self-contained compose.yaml into ./podbay, pulls +
# starts everything, and prints the URL. No repo clone, no build.
# Override: PODBAY_PORT (default 8080), PODBAY_DIR, PODBAY_COMPOSE_URL.
set -eu

PORT="${PODBAY_PORT:-8080}"
DIR="${PODBAY_DIR:-podbay}"
COMPOSE_URL="${PODBAY_COMPOSE_URL:-https://raw.githubusercontent.com/podbay-cloud/install/main/compose.yaml}"

say()  { printf '%s\n' "$*"; }
die()  { printf '\n✗ %s\n' "$*" >&2; exit 1; }

# ── Requirements check — report EVERYTHING that's missing, not just the first ─────────────────
say "Checking requirements…"
missing=0
need() { # label  test-command  fix-hint
  if eval "$2" >/dev/null 2>&1; then printf '  ✓ %s\n' "$1"
  else printf '  ✗ %s — %s\n' "$1" "$3"; missing=1; fi
}
need "Docker installed"      "command -v docker"          "get it at https://docs.docker.com/get-docker/"
need "Docker running"        "docker info"                "start Docker Desktop (or the daemon) and re-run"
need "Docker Compose v2"     "docker compose version"     "update Docker Desktop, or install the docker-compose-plugin"
need "curl"                  "command -v curl"            "install curl (or set PODBAY_COMPOSE_URL + fetch manually)"
[ "$missing" -eq 0 ] || die "install the requirements above, then re-run this script."

# ── Soft warnings (non-fatal) ─────────────────────────────────────────────────────────────────
avail_gb=$(df -Pk "$PWD" 2>/dev/null | awk 'NR==2 { printf "%d", $4/1024/1024 }' || echo "")
if [ -n "$avail_gb" ] && [ "$avail_gb" -lt 6 ]; then
  say "  ⚠ only ${avail_gb} GB free here — the images need ~5 GB (plus room for pods); free some space or you may hit 'no space left'."
fi
if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  die "port $PORT is already in use. Set PODBAY_PORT=<a free port> and re-run (or free it)."
fi

# ── Compose file: use one next to this script (repo checkout), else download ──────────────────
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
mkdir -p "$DIR"
if [ -f "$SELF_DIR/compose.yaml" ]; then
  cp "$SELF_DIR/compose.yaml" "$DIR/compose.yaml"; say "Using compose.yaml from $SELF_DIR"
else
  say "Fetching compose.yaml…"
  curl -fsSL "$COMPOSE_URL" -o "$DIR/compose.yaml" || die "couldn't download the compose file from $COMPOSE_URL"
fi

# ── Up (pulls images on first run) ────────────────────────────────────────────────────────────
say "Starting podbay on :$PORT (first run pulls the images — a few minutes)…"
( cd "$DIR" && PODBAY_PORT="$PORT" docker compose up -d )

cat <<EOF

✅ podbay is up → http://localhost:$PORT
   Create a pod, sign in with your Claude account, and you're in.

   Manage it (from ./$DIR):
     docker compose logs -f serve     # daemon / provisioning
     docker compose down              # stop   ·   down -v also wipes state
   VPS: put it behind your domain (edit the Caddy block in compose.yaml) + a login gate.
EOF
