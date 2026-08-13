# podbay self-host

Run podbay on your own machine or VPS: the dashboard, the terminal, and pods as local Docker
containers — your own Claude subscription, your own metal.

## Quickstart

Requirements: Docker (Desktop on macOS/Windows, Engine on Linux) with ≥8 GB RAM available.

One command:

```sh
curl -fsSL https://raw.githubusercontent.com/podbay-cloud/install/main/install.sh | sh
```

Prefer no piped script? The compose file is self-contained (Caddy config inlined), so it's one fetch:

```sh
curl -fsSL https://raw.githubusercontent.com/podbay-cloud/install/main/compose.yaml -o compose.yaml
docker compose up -d
```

Open **http://localhost:8080** → Create a pod → sign in with your Claude account (paste the code)
→ the pod reaches "Open in Claude" and the web terminal works in the cockpit. Nothing builds — no
20-minute wait, and it works even on an SSL-inspecting network (VPN/corp) where local builds fail.

> These `raw.githubusercontent.com` URLs resolve only once this repo (or a public distribution repo)
> is public. The container images on ghcr are already public; the install files are the last piece.

Override: `PODBAY_PORT=…` (default 8080), `PODBAY_APP_IMAGE=…`, `PODBAY_POD_IMAGE=…`.

Override the images if needed: `PODBAY_APP_IMAGE=…`, `PODBAY_POD_IMAGE=…`.

### Build from source instead

For local development or an air-gapped host (needs the repo + a clean, non-intercepting network):

```sh
git clone https://github.com/velsa/podbay.git && cd podbay/selfhost  # (private; maintainers)
docker compose -f compose.yaml -f compose.build.yaml up -d --build
docker compose -f compose.yaml -f compose.build.yaml build podbase   # the pod image, once (~20 min)
```

## What's running

| Service   | Role                                                                    |
| --------- | ----------------------------------------------------------------------- |
| `proxy`   | Caddy on :8080 — one origin: `/pods/*` (terminal WS) → serve, rest → web |
| `web`     | The dashboard (Next.js, single-tenant OSS edition)                       |
| `serve`   | The daemon: terminal gateway + pod provisioner                           |
| `db`      | Postgres 16 (state), on a named volume                                   |
| `migrate` | One-shot schema migration on startup                                     |
| `podbase` | Build-only: bakes `podbay/pod-base:local`, the image pods boot from      |

Pods run as **sibling containers** on your Docker host (`docker ps` shows `podbay-<id>`), get
`/pods` network access from the control plane by container name, and publish their preview
(`:3000`) and agent (`:8080`) ports on the host.

## Day-2

```sh
docker compose logs -f serve      # daemon logs (gateway + provisioning)
docker compose up -d --build      # update after a git pull
docker compose down               # stop (pods keep running; remove them from the dashboard)
docker compose down -v            # stop AND wipe state (pods table, secrets vault key)
```

## VPS notes

- Edit the inline **Caddy block** in `compose.yaml` (the `configs: caddyfile:` content): replace
  `:8080` with your domain and publish `80:80` + `443:443` on the `proxy` service — Caddy provisions
  HTTPS automatically.
- Pod **preview links** currently point at `127.0.0.1:<port>` (the host mapping) — correct on a
  laptop, not yet proxied for remote visitors on a VPS. Roadmap: previews through the same origin.
- The dashboard has **no authentication** in OSS single-tenant mode: on a VPS, put it behind
  Caddy `basic_auth` (or a VPN/tailnet) before exposing it.

## Troubleshooting

- **Pod stuck "creating"** — `docker compose logs serve` (the provisioner); most often the
  `podbay/pod-base:local` image is still building or missing (`docker images | grep pod-base`).
- **Terminal won't connect** — `docker compose logs proxy serve`; the browser should open a
  WebSocket to `ws(s)://<your-origin>/pods/<id>`.
- **`too many clients` from Postgres** — `docker compose restart db` clears leaked connections
  (shouldn't happen since the pool is bounded; report it if it recurs).

## Publishing the images (maintainers)

Users pull; maintainers publish. Two ways to build the multi-arch images (`pod-app`, `pod-base`):

- **GitHub Actions** — run the `selfhost-images` workflow (native amd64 + arm64 runners, no
  emulation). Then flip both ghcr packages to **Public** once.
- **Locally** — `docker login ghcr.io -u <you>` then `./build-images.sh` (needs buildx; an
  M-series Mac does arm64 native + amd64 emulated). Build `pod-base` on a non-SSL-inspecting network.
