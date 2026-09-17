# Quad.io

Company site for [Quad.io](https://www.quad.io): clear inputs, elegant systems, clear outputs. Screenless technology on sovereign data.

This repository is an [rsites](https://github.com/Burton-Workspaces/rabun-sites) site: [Zola](https://www.getzola.org/) content, [DevLab](https://codeberg.org/RiPetitor/devlab-theme) pinned as a git submodule. The `rsites` CLI lives in **rabun-sites**.

## Layout

| Path | Role |
| --- | --- |
| `content/` | Markdown pages (TOML front matter) |
| `zola.toml` | Brand, nav, DevLab extras |
| `rsites.toml` | Theme pin, hostname, Caddy document root |
| `templates/`, `static/` | Site overlays (do not edit `themes/`) |

## Preview

```bash
git submodule update --init --recursive
rsites serve
```

That is Zola's live server. After content or nav changes run `rsites check`. `rsites build` writes `public/`.

## Brand

Palette and mark live in `static/custom.css` and `static/brand/quad.svg`. Do not edit files under `themes/`.
