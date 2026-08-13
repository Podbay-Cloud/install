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

# ── Compose file: use one next to a REAL install.sh (repo checkout), else download ────────────
# With `curl … | sh`, $0 is normally `sh`; resolving dirname($0) would incorrectly treat the
# CALLER'S current directory as the script directory and could start an unrelated compose.yaml.
# Only trust an adjacent file when this is actually being run as an install.sh file.
SELF_DIR=""
case "$0" in
  install.sh|*/install.sh) SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)" ;;
esac
mkdir -p "$DIR"
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/compose.yaml" ]; then
  cp "$SELF_DIR/compose.yaml" "$DIR/compose.yaml"; say "Using compose.yaml from $SELF_DIR"
else
  say "Fetching compose.yaml…"
  curl -fsSL "$COMPOSE_URL" -o "$DIR/compose.yaml" || die "couldn't download the compose file from $COMPOSE_URL"
fi

# ── Up (pulls images on first run) ────────────────────────────────────────────────────────────
say "Starting podbay on :$PORT (first run pulls the images — a few minutes)…"
if ( cd "$DIR" && PODBAY_PORT="$PORT" docker compose up -d ); then
  : # started
else
  # Classify the failure. The classic gotcha on a PUBLIC image is a STALE 'docker login ghcr.io':
  # Docker then presents expired/invalid credentials and the registry answers "denied" instead of
  # falling back to an anonymous pull. Detect that specifically and tell the user how to fix it.
  app_img=$(grep -oE 'ghcr\.io/[A-Za-z0-9._/-]*pod-app[A-Za-z0-9._:@/-]*' "$DIR/compose.yaml" 2>/dev/null | head -1)
  app_img="${app_img:-ghcr.io/velsa/pod-app:latest}"
  if docker pull "$app_img" 2>&1 | grep -qiE 'denied|unauthorized'; then
    die "image pull was DENIED for $app_img — but that image is public.

This almost always means a stale 'docker login ghcr.io' on THIS machine: Docker sends expired
credentials, and ghcr rejects them rather than pulling anonymously. Clear it and re-run:

    docker logout ghcr.io
    curl -fsSL ${PODBAY_COMPOSE_URL%/compose.yaml}/install.sh | sh"
  fi
  die "startup failed — see the errors above, resolve them, and re-run this installer."
fi

# Best-effort primary non-loopback IP, so a REMOTE box shows a reachable URL instead of a useless
# "localhost" (which, on a VPS, just means the VPS itself). May be a private/NAT address behind a
# load balancer — hence the "or your domain" note.
host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$host_ip" ] && host_ip=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')

say ""
say "✅ podbay is up."
say "   On this machine:   http://localhost:$PORT"
if [ -n "$host_ip" ] && [ "$host_ip" != "127.0.0.1" ]; then
  say "   From elsewhere:     http://$host_ip:$PORT   (open port $PORT in the firewall / security group)"
fi
cat <<EOF
   First visit shows a one-time owner setup (pick a password) — then it's your dashboard.

   Manage it (from ./$DIR):
     docker compose logs -f serve     # daemon / provisioning
     docker compose down              # stop   ·   down -v also wipes state
   Remote installs are experimental. Keep the dashboard private; see the public deployment guide.
   To pre-set the owner (skip the first-run setup window), set PODBAY_AUTH_PASSWORD before starting.
EOF
