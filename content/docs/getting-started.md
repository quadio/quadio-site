+++
title = "Getting started"
description = "Preview this site locally with rsites."
weight = 1
+++

You will have a local preview by the end of this page.

## Requirements

- Git
- Zola 0.23.4 or newer
- `rsites` on your PATH

## Preview

```bash
rsites serve
```

Open the address printed by Zola. Production hosting uses Caddy against the `public/` directory after `rsites build`.