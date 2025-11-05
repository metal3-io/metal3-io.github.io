# Metal3 Website - AI Coding Assistant Instructions

## Project Overview

Public-facing website for the Metal3 project at <https://metal3.io>.
Built with Hugo static site generator. Provides project overview,
getting started guides, community information, and links to detailed
documentation.

## Structure

- `content/` - Website content (Markdown)
   - `en/` - English content
      - `_index.md` - Homepage
      - `about/` - About Metal3
      - `blog/` - Blog posts
      - `community/` - Community information
- `static/` - Static assets (images, CSS, JS)
- `layouts/` - Hugo layout templates
- `config.toml` - Hugo site configuration

## Local Development

```bash
# Install Hugo extended version
# Ubuntu: sudo snap install hugo --channel=extended
# macOS: brew install hugo

# Serve site locally
hugo serve

# Build for production
hugo

# Output in public/
```

## Adding Content

**New Blog Post:**

```bash
hugo new blog/my-post-title.md
```

Edit with frontmatter:

```yaml
---
title: "My Post Title"
date: 2024-11-05
author: "Your Name"
---
```

**Update Homepage:**
Edit `content/en/_index.md`

## Deployment

- Site automatically builds and deploys via GitHub Pages
- Pushes to main branch trigger deployment
- Published to <https://metal3.io>

## Common Pitfalls

1. **Hugo Version** - Ensure using extended Hugo version for SCSS
   support
2. **Base URL** - Check `config.toml` baseURL for production builds
3. **Image Paths** - Use `/images/` prefix for static images
4. **Draft Posts** - Remove `draft: true` from frontmatter to publish

Website changes should be visually reviewed locally before submitting
PRs. This is the public face of Metal3, so content should be polished
and professional.
