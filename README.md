# metal3.io Website

[![Deploy via Jekyll on GitHub pages](https://github.com/metal3-io/metal3-io.github.io/actions/workflows/jekyll.yml/badge.svg?branch=source)](https://github.com/metal3-io/metal3-io.github.io/actions/workflows/jekyll.yml)

lorem ipsum this shhould be detectted by yaspelller

## Contributing content

We more than welcome contributions in the form of blog posts, pages and/or labs, reach out if you happen to have an idea or find an issue with our content! [Here's our guideline for content](GUIDELINES.md).

## Test your changes in a local container

### Run a Jekyll container

- On an SELinux-enabled OS:

  ```console
  cd metal3-io.github.io
  mkdir .jekyll-cache
  podman run -d --name metal3io -p 4000:4000 -v $(pwd):/srv/jekyll:Z jekyll/jekyll jekyll serve --future --watch
  ```

  **NOTE**: Make sure you are in the _metal3-io.github.io_ directory before running the above command as the Z at the end of the volume (-v) will relabel its contents so it can be written from within the container, like running `chcon -Rt svirt_sandbox_file_t -l s0:c1,c2` yourself.

- On an OS without SELinux:

  ```console
  cd metal3-io.github.io
  mkdir .jekyll-cache
  sudo docker run -d --name metal3io -p 4000:4000 -v $(pwd):/srv/jekyll jekyll/jekyll jekyll serve --future --watch
  ```

### View the site

Visit `http://0.0.0.0:4000` in your local browser.
The Metal3.io website is a Jekyll site, hosted with GitHub Pages.

All pages are located under `/pages`. Each section of the site is broken out into their respective folders - `/blogs` for the various Blog pages, `/docs` for the Documentation and `/videos` for the videos that are shared.

All site images are located under `/assets/images`. Please do not edit these images.

Images that relate to blog entries are located under `/assets/images/BLOG_POST_TITLE`. The **BLOG_POST_TITLE** should match the name of the markdown file that you added under `/_posts`.
