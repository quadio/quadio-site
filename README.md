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
