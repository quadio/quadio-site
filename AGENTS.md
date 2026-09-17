# Agent instructions for quadio-site

This is an [rsites](https://github.com/Burton-Workspaces/rabun-sites) Zola + DevLab site. Follow this file when adding or changing content.

## Source of truth


If this site documents another git project, add a `[project]` table to `rsites.toml` (`url`, optional `docs_path`). Then read that repo for facts and write Zola pages here. Do not vendor the project into `themes/`. Use `rsites content add` only when the remote is already a Zola content tree.


## Layout

| Path | Meaning |
| --- | --- |
| `content/_index.md` | Home |
| `content/docs/_index.md` | Docs section |
| `content/docs/*.md` | Doc pages |
| `zola.toml` | Brand, nav, DevLab extras |
| `rsites.toml` | Theme pin, Caddy, optional `[project]` |
| `themes/` | Pinned theme. **Do not edit.** |

Overrides belong in this site's `templates/`, `sass/`, and `static/` directories.

## Page schema

Use TOML frontmatter delimited by `+++` only (not YAML `---`).

Doc page (`content/docs/**/*.md`, not `_index.md`):

```md
+++
title = "Short title"
description = "One sentence."
weight = 10
+++
```

Docs section (`content/docs/.../_index.md`): set `sort_by = "weight"`, `template = "docs.html"`, `page_template = "doc-page.html"`.

Home (`content/_index.md`): keep `[extra]` keys `home_layout`, `home_eyebrow`, `home_primary_action_label`, `home_primary_action_path`, `home_features`.

Blog post (only after Blog is enabled in `zola.toml`): `content/blog/YYYY-MM-DD-slug.md` with `title`, `description`, and `date`.

## Hard rules

- Do not edit `themes/` or `public/`.
- After content or nav changes, run `rsites check`. Preview with `rsites serve`.
- New top-level sections need a matching entry in `[extra.devlab.navigation]` in `zola.toml`.

- Zola runs Tera on Markdown bodies. Do not put raw `{%` or `{{` in a page unless wrapped in a Tera raw block.
