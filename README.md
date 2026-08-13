# podbay — self-hosted

**Give an AI agent a real computer — on your own machine.**

podbay runs [Claude Code](https://claude.com/claude-code) inside a private, always-on container
("a **pod**") with your project, a terminal, and tools already set up. You reach it from a web
dashboard *and* from the Claude desktop/mobile apps, and it uses **your existing Claude
subscription** — no API keys, no per-token billing.

The hosted version lives at podbay.cloud. **This is the open self-host edition**: the same engine,
running single-tenant on *your* metal — your machine, your network, your data.

---

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/podbay-cloud/install/main/install.sh | sh
```

Then open **http://localhost:8080** → **Create a pod** → sign in with your Claude account (paste the
code) → the pod reaches **"Open in Claude"** and a live terminal + app preview appear in the
cockpit. First run pulls a few container images (~a couple of minutes); after that, launching a pod
is seconds.

The installer checks your machine first and tells you exactly what's missing. Nothing builds
locally — it pulls prebuilt, multi-architecture images — so it works on an Intel or Apple-Silicon
Mac, Linux, or a VPS, and even behind a corporate VPN that would break a local `docker build`.

Prefer not to pipe a script to your shell? It's one self-contained file:

```sh
curl -fsSL https://raw.githubusercontent.com/podbay-cloud/install/main/compose.yaml -o compose.yaml
docker compose up -d
```

---

## Requirements

| Need | Why | Notes |
|---|---|---|
| **Docker Engine** or **Docker Desktop** | everything runs in containers; pods are launched as sibling containers | Desktop on macOS/Windows, Engine on Linux |
| **Docker Compose v2** (`docker compose`) | orchestrates the stack | ships with Docker Desktop; on Linux: the `docker-compose-plugin` |
| **curl** | the installer fetches the compose file | present on macOS/Linux by default |
| **~5 GB disk** + **≥ 8 GB RAM** | images + a pod running a real dev environment | more headroom is better if you run several pods |
| **A Claude subscription** | the agent signs into *your* Claude account | Pro/Max — the same one you use in the Claude apps |

The installer verifies Docker, the daemon, Compose, and curl, warns on low disk / a busy port, and
refuses with a clear message if something's missing.

---

## Where you can run it

Anything that runs Docker. podbay is single-tenant here, so "where" is just "where's your Docker."

**On your own machine (local):**
- **macOS** — Docker Desktop (Intel *or* Apple Silicon; images are multi-arch).
- **Linux** — Docker Engine.
- **Windows** — Docker Desktop with the WSL2 backend.

Open `http://localhost:8080`. This is the simplest setup and needs no domain or TLS.

**On a VM / VPS (reachable from anywhere):** any cloud host with Docker installed —
- AWS EC2 · Google Cloud · Azure · Hetzner · DigitalOcean · Linode · Vultr · Fly.io · a Raspberry Pi
  or ARM box (arm64 images work) · your own server.

On a VM you'll want a domain + HTTPS. Caddy provisions the certificate automatically, but only once
the domain actually points at the server. So, in order:

1. **A domain** you control.
2. **DNS** — add an **A record** (and **AAAA** for IPv6) pointing `podbay.example.com` → your VM's
   public IP. Automatic HTTPS *depends on this*: Caddy proves it owns the name via a challenge to
   that address, so no DNS = no cert.
3. **Open the firewall** — allow inbound **80** and **443** (the security-group / `ufw` rules), and
   publish `80:80` + `443:443` on the `proxy` service in `compose.yaml`.
4. **Point Caddy at the domain** — in the inline Caddy block in `compose.yaml`, replace `:8080` with
   `podbay.example.com`. `docker compose up -d` and Caddy fetches a certificate on first request.
5. **Gate it** (Caddy `basic_auth`, a VPN, or a tailnet) — the OSS dashboard has no built-in sign-in,
   so don't leave it open to the internet.

(Skip 1–4 for a private/dev VM: just reach it over a tunnel/tailnet on `:8080`, no domain needed.)

**Pods on a *different* machine (advanced):** the control plane can drive Docker on a remote host
over SSH — set `PODBAY_DOCKER_HOST=ssh://user@host` and pods launch there while the dashboard runs
where you are. (One brain, many machines.)

---

## What you get

- A **dashboard** to create, monitor, and delete pods.
- Each pod: **Claude Code** signed into your account, reachable from the **Claude desktop/mobile
  apps** (remote control) *and* a **web terminal** in the cockpit.
- A running **dev server preview** for the pod's project.
- Your **own Claude subscription** — no API keys, no usage billing from podbay.

## How it works (the short version)

`docker compose up` starts five things, and pods are a sixth:

| Service | Role |
|---|---|
| `proxy` (Caddy) | one front door on `:8080` — `/pods/*` terminal WebSockets → the gateway, everything else → the dashboard |
| `web` | the dashboard (Next.js, single-tenant) |
| `serve` | the daemon: terminal **gateway** + pod **provisioner** |
| `db` | Postgres (state) on a named volume |
| `migrate` | one-shot schema setup on startup |
| **pods** | your agents — **sibling containers** on your Docker host (`docker ps` shows `podbay-<id>`) |

Images are pulled from the public registry (`ghcr.io/velsa/pod-app`, `ghcr.io/velsa/pod-base`) — no
local builds. `web`/`serve` mount your Docker socket so they can launch pods; pods join a private
Docker network so the control plane reaches them by name.

---

## Configuration

Set as environment variables (or in a `.env` beside `compose.yaml`):

| Var | Default | What |
|---|---|---|
| `PODBAY_PORT` | `8080` | the port the dashboard is served on |
| `PODBAY_APP_IMAGE` | `ghcr.io/velsa/pod-app:latest` | override the app image / pin a tag |
| `PODBAY_POD_IMAGE` | `ghcr.io/velsa/pod-base:latest` | override the pod image / pin a tag |
| `PODBAY_DOCKER_HOST` | *(unset)* | `ssh://user@host` to run pods on a remote Docker |

## Day-2

```sh
docker compose logs -f serve      # daemon logs (gateway + provisioning)
docker compose pull && docker compose up -d   # update to the latest images
docker compose down               # stop (running pods keep running; remove them in the dashboard)
docker compose down -v            # stop AND wipe state (pods table, secrets vault key)
```

## Security notes

- **No dashboard auth in single-tenant mode.** Fine on localhost; on a VPS put it behind Caddy
  `basic_auth` / a VPN before exposing it.
- **Secrets** (per-pod app secrets) are encrypted at rest with a key auto-generated on first run and
  kept on the `appdata` volume.
- Pods run on **your** machine/network — the agent's fetches and tools egress from *you*, which is
  the point of self-hosting.

---

## Build from source instead

For development, an air-gapped host, or an unpublished branch (needs the private repo + a network
without HTTPS interception):

```sh
git clone https://github.com/velsa/podbay.git && cd podbay/selfhost   # (private; maintainers)
docker compose -f compose.yaml -f compose.build.yaml up -d --build
docker compose -f compose.yaml -f compose.build.yaml build podbase    # the pod image, once (~20 min)
```

## Troubleshooting

- **Pod stuck "creating"** — `docker compose logs serve`; usually the `pod-base` image is still
  pulling on first launch (`docker images | grep pod-base`).
- **Terminal won't connect** — `docker compose logs proxy serve`; the browser opens a WebSocket to
  `ws(s)://<your-origin>/pods/<id>`.
- **`no space left on device`** — free disk; the images total ~5 GB and pods add more.
- **`too many clients` from Postgres** — `docker compose restart db` (shouldn't recur; report it if it does).
- **Port already in use** — `PODBAY_PORT=<free port>` and re-run.

## What's OSS vs. cloud

The **runtime** is open here: the pod, the local Docker provider, the control-plane library, the
gateway, the dashboard. The **hosted service** adds what a single self-hoster doesn't need —
multi-tenancy, managed fleet orchestration, and the residential-egress relay network.

---

- Images: [`ghcr.io/velsa/pod-app`](https://github.com/velsa/podbay/pkgs/container/pod-app) ·
  [`ghcr.io/velsa/pod-base`](https://github.com/velsa/podbay/pkgs/container/pod-base)
- The optional **relay** (let a pod fetch pages through your machine): `npm i -g @podbay/relay`
- License: Apache-2.0
