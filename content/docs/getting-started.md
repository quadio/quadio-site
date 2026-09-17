+++
title = "Getting started"
description = "Preview the site locally with rsites."
weight = 1
+++

## Requirements

- Git
- Zola 0.23.4 or newer
- `rsites` on your PATH

## Preview

```bash
rsites serve
```

Open the address Zola prints. Production is Caddy serving `public/` after `rsites build`.