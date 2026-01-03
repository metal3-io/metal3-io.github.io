# Metal3 Website - AI Agent Instructions

Instructions for AI coding agents. For content guidelines, see [GUIDELINES.md](GUIDELINES.md).

## Overview

Public-facing website for Metal3 at <https://metal3.io>. Built with
Jekyll static site generator, hosted on GitHub Pages.

## Repository Structure

| Directory | Purpose |
|-----------|---------|
| `_posts/` | Blog posts (dated markdown files) |
| `_layouts/` | Jekyll page templates |
| `_includes/` | Reusable HTML components |
| `_faqs/` | FAQ entries |
| `assets/` | Images, CSS, JS |
| `hack/` | CI scripts (markdownlint, spellcheck, shellcheck) |

## Testing Standards

CI uses GitHub Actions. Run locally before PRs:

| Command | Purpose |
|---------|---------|
| `make lint` | Run all linters |
| `make serve` | Serve locally on port 4000 |

## Pre-commit Hooks

This repository uses [pre-commit](https://pre-commit.com/) for automated checks.
Config in `.pre-commit-config.yaml`.

| Command | Purpose |
|---------|---------|
| `./hack/pre-commit.sh` | Run pre-commit in container |
| `pre-commit install` | Install hooks locally |
| `pre-commit run --all-files` | Run all hooks manually |

Hooks include: prettier (CSS/JS/JSON), black (Python), trailing whitespace,
YAML/JSON validation, and merge conflict detection.

## Code Conventions

- **Markdown**: Config in `.markdownlint-cli2.yaml`
- **Spelling**: Custom dictionary in `.cspell-config.json`
- **Links**: Checked by lychee (`.lycheeignore` for exceptions)

## Adding Content

**New blog post:** Create `_posts/YYYY-MM-DD-title.md` with frontmatter:

```yaml
---
layout: post
title: "Post Title"
date: YYYY-MM-DD
author: "Your Name"
---
```

## Code Review Guidelines

When reviewing pull requests:

1. **Visual review** - Preview locally with `make serve`
1. **Spelling** - Add technical terms to `.cspell-config.json`
1. **Links** - No broken links
1. **Images** - Place in `assets/images/POST_TITLE/`

## AI Agent Guidelines

1. Run `make lint` before committing
1. Update `.cspell-config.json` for new technical terms
1. Follow [GUIDELINES.md](GUIDELINES.md) for content style

## Related Documentation

- [Metal3 Book](https://book.metal3.io)
- [metal3-docs](https://github.com/metal3-io/metal3-docs)
