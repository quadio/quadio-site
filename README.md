# Quad.io

Company site for [Quad.io](https://www.quad.io): clear inputs, elegant systems, clear outputs. Screenless technology on sovereign data. Production URL: [https://www.quad.io](https://www.quad.io).

This repository is an [rsites](https://github.com/Burton-Workspaces/rabun-sites) site: [Zola](https://www.getzola.org/) content, [DevLab](https://codeberg.org/RiPetitor/devlab-theme) pinned as a git submodule, and [Caddy](https://caddyserver.com/) for production. The `rsites` CLI lives in **rabun-sites** (`rabun-sites` the crate, `rsites` on PATH).

## Layout

| Path | Role |
| --- | --- |
| `content/` | Markdown pages (TOML front matter) |
| `zola.toml` | Brand, nav, DevLab extras |
| `rsites.toml` | Theme pin, hostname, Caddy document root |
| `templates/`, `static/` | Site overlays (do not edit `themes/`) |
| `deploy/ubuntu/` | Bare-metal Ubuntu install (`push.sh --pack`) |
| `deploy/digitalocean/` | Droplet install and Caddy virtual host |

## Requirements

- Git
- [Zola](https://www.getzola.org/) **0.23.4** or newer
- [`rsites`](https://github.com/Burton-Workspaces/rabun-sites) on PATH

From a rabun-sites checkout:

```bash
cargo build --release
./target/release/rsites setup-shell
rsites zola install
rsites doctor
```

## Preview

```bash
git submodule update --init --recursive
rsites serve
```

That is Zola's live server (not Caddy). After content or nav changes run `rsites check`. `rsites build` writes `public/`.

## Brand

Palette and mark live in `static/custom.css` and `static/brand/quad.svg`. Do not edit files under `themes/`.

## Caddy

Caddy serves the built `public/` tree in production. Hostname and document root come from `rsites.toml` (`www.quad.io`, `/var/www/quadio-site`).

```bash
rsites caddy render
rsites caddy render --snippet
rsites caddy render --out /etc/caddy/sites-enabled/quadio-site.caddy
```

The checked-in snippet [`deploy/digitalocean/quadio-site.caddy`](deploy/digitalocean/quadio-site.caddy) matches that www block and redirects `quad.io` to `https://www.quad.io`. Import it from the host Caddyfile (`import /etc/caddy/sites-enabled/*`) so this virtual host can share a droplet with other Caddy sites.

## DigitalOcean droplet

Same pattern as burton-site: the droplet never clones this repo. A laptop or GitHub Actions builds `public/`, copies a tarball over SSH, and Caddy `file_server`s `/var/www/quadio-site`.

```
Internet → www.quad.io     → Caddy :443 → /var/www/quadio-site
        → quad.io          → Caddy :443 → redirect to www
        → (sibling hostnames) → Caddy :443 → other site files
```

Bootstrap writes `/etc/caddy/sites-enabled/quadio-site.caddy` and adds `import /etc/caddy/sites-enabled/*` if that line is missing. It does **not** replace an existing Caddyfile that already has other sites.

### 1. Create the droplet

Ubuntu 24.04 LTS. Point A records for **www.quad.io** and **quad.io** at the droplet IPv4. Firewall: 22, 80, and 443.

### 2. Bootstrap (once)

```bash
rsites build
tar -C public -czf /tmp/quadio-site.tar.gz .
./deploy/digitalocean/push.sh --archive /tmp/quadio-site.tar.gz --bootstrap root@DROPLET_IP
```

`--domain` defaults to `www.quad.io`. Or Actions → **Site** → Run workflow → enable **bootstrap**.

### 3. GitHub Actions

Create a GitHub **Environment** named `production` and add:

| Secret | Required | Example |
| --- | --- | --- |
| `DROPLET_HOST` | yes | `203.0.113.10` or `www.quad.io` |
| `DROPLET_USER` | yes | `root` |
| `DROPLET_SSH_KEY` | yes | **Private** key that can SSH as that user |
| `DROPLET_SSH_PORT` | no | `22` |
| `DROPLET_SSH_KNOWN_HOSTS` | no | `ssh-keyscan -H HOST` output |

`DROPLET_SSH_KEY` must be the private key (including `BEGIN`/`END` lines), not the `.pub` file. Empty passphrase. The deploy job **skips** (green) when those secrets are unset.

Pushes to `master` build the site and deploy when secrets are set. Pull requests only build.

Local refresh after bootstrap:

```bash
rsites build
tar -C public -czf /tmp/quadio-site.tar.gz .
./deploy/digitalocean/push.sh --archive /tmp/quadio-site.tar.gz root@DROPLET_IP
```

### Layout on the droplet

| Path | Role |
| --- | --- |
| `/var/www/quadio-site` | published `public/` tree |
| `/etc/caddy/sites-enabled/quadio-site.caddy` | www + apex virtual hosts |
| `/etc/caddy/Caddyfile` | `import /etc/caddy/sites-enabled/*` plus any sites you already had |
| `/etc/quadio-site/site.env` | health-check URL and `Host` header |

Logs: `journalctl -u caddy -f`. Do not wipe `/var/lib/caddy` (ACME store).

## Ubuntu (bare metal)

Same archive on an x86_64 Ubuntu host that may already run other Caddy sites. The server never talks to GitHub. Bootstrap does not replace an existing Caddyfile, does not enable ufw unless it is already active (or `SITE_ENABLE_UFW=1`), and refuses a `--domain` that another Caddy snippet already serves.

This is the sibling of the DigitalOcean droplet path above. Production auto-deploys after a push to `master`. Ubuntu does **not** — use `deploy/ubuntu/push.sh --pack`.

```
Internet → Caddy :443 (optional, site snippet only) → /var/www/quadio-site
                                                    → :8080 when no domain is set
```

### 1. Server

Ubuntu 24.04 LTS (or 26.04), x86_64. SSH as `root` or a sudoer. From a laptop, `push.sh` allocates a TTY so sudo can prompt for a password.

### 2. Bootstrap (once)

```bash
./deploy/ubuntu/push.sh --pack --bootstrap --domain www.quad.io user@HOST
```

Omit `--domain` to listen on **:8080**. On a LAN hostname that cannot use Let's Encrypt:

```bash
./deploy/ubuntu/push.sh --pack --bootstrap --domain damascus --tls lan user@192.168.0.18
```

Trust `/etc/quadio-site/tls/lan-root.crt` on each device, then open `https://damascus`. On a fresh box with no firewall yet:

```bash
SITE_ENABLE_UFW=1 ./deploy/ubuntu/push.sh --pack --bootstrap user@HOST
```

Do **not** `curl | bash` the bootstrap script from `raw.githubusercontent.com`.

### 3. Later updates

```bash
./deploy/ubuntu/push.sh --pack user@HOST
```

Two-step (inspect the archive first):

```bash
./deploy/ubuntu/pack.sh
# dist/quadio-site.tar.gz
./deploy/ubuntu/push.sh --archive dist/quadio-site.tar.gz user@HOST
```

### Layout on the server

| Path | Role |
| --- | --- |
| `/var/www/quadio-site` | published `public/` tree |
| `/etc/caddy/sites-enabled/quadio-site.caddy` | Caddy site snippet |
| `/etc/caddy/Caddyfile` | `import /etc/caddy/sites-enabled/*` plus any sites you already had |
| `/etc/quadio-site/site.env` | health-check URL, hostname, optional `SITE_TLS` |
| `/etc/quadio-site/tls/lan-root.crt` | Caddy local CA when `--tls lan` |

Logs: `journalctl -u caddy -f`. Do not wipe `/var/lib/caddy` (ACME store).
