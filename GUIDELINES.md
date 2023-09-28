# Contents Guidelines

This document describes a set of guidelines for generating content for [metal3.io](https://metal3.io), exceptions can be made if and when it makes sense, but please try to follow this guide as much as possible.

## General contents guidelines

Please use the following as general guidelines on any kind of content generated for this site:

### Technical setup

- Install `pre-commit` in your system and from the repository folder run `pre-commit install` so that the git hook is in place.
  - It will avoid commits to the `source` and `master` branch
  - It will spell-check articles before the commit can be performed
  - Adjust some formatting in markdown like tables, spaces before and after headings, etc (via prettifier)
  - If you're using `npm` you can also add pre-commit as a dependency for development so that it incorporates the `pre-commit` hook and it also spellchecks before you submit to CI and risk getting a failure in build. To do so, use: `npm install --save-dev pre-commit`
- For each spellcheck failure or duplicate word, adjust `.yaspellerrc`, try to sort the word file and check for duplicates reported by yaspeller on run.

### Content

- Follow [Kramdown Quick Reference](https://kramdown.gettalong.org/quickref.html) for syntax reference
- Split the contents into sections using the different levels of headers that Markdown offers
  - Keep in mind that once rendered, the title you set in the Front Matter data will use _H1_, so start your sections from _H2_
- Closing section, the same way we can add a brief opening section describing what the contents are about, it's very important to add a closing section with thoughts, upcoming work on the topic discussed, encourage readers to test something and share their findings/thoughts, joining the community, ... keep in mind that this will probably be the last thing the reader will read
- [Code blocks](https://kramdown.gettalong.org/syntax.html#code-blocks), use them for:
  - code snippets
  - file contents
  - console commands
  - ...
  - Use the proper tag to let the renderer know what type of contents your including in the block for syntax highlighting
- Consistency is important, makes it easier for the reader to follow along, for instance:
  - If you're writing about something running on OCP, use `oc` consistently, don't mix it up with `kubectl`
  - If you add your shell prompt to your console blocks, add it always or don't, but don't do half/half
- Use backticks (`) when mentioning commands on your text, like we do in this document
- Use _emphasis/italics_ for non-English words such as technologies, projects, programming language keywords...
- Use bullet points, these are a great way to clearly express ideas through a series of short and concise messages
  - Express clear benefit. Think of bullets as mini-headlines
  - Keep your bullets symmetrical. 1-2 lines each
  - Avoid bullet clutter. Don’t write paragraphs in bullets
  - Remember bullets are not sentences. They’re just like headlines
- Use of images
  - Images are another great way to express information, for instance, instead of trying to describe your way around a UI, just add a snippet of the UI, readers will understand it easier and quicker
  - Avoid large images, if you have to try to resize them, otherwise the image will be wider than the writing when your contents is rendered
  - Linking or HTTP references
    - Linking externally can be problematic, some time after the publication of your contents, try linking to the repositories or directories, website's front page rather than to a page, etc.
    - For linking internally use [Jekyll's tags](https://jekyllrb.com/docs/liquid/tags/#links)
      - For blog posts
        - Use macro `{% post_url FILENAME.WITHOUT.EXTENSION %}` instead of regular URI
      - For pages, collections, assets, etc
        - For document linking: `{% link _collection/name-of-document.md %}` instead of regular URI
        - For file linking: `{% link /assets/files/doc.pdf %}` instead of regular URI

## Contents types

### Blog Posts

All Blog posts are located in the [blog/\_posts](blog/_posts/) directory, and all FAQ posts in the [faqs/\_posts](faqs_posts), on them, each entry is a Markdown file with extension _.md_ or _.markdown_. For creating a blog post for [metal3.io ](https://metal3.io), you need to complete the following steps.

- Create a markdown file with the _YYYY-MM-DD-TITLE.markdown_ naming convention
- For the [Front Matter](https://jekyllrb.com/docs/front-matter/), you need to add the following:

  ```yaml
  ---
  layout: post
  author: Your Name
  title: Title of Blog Post
  description: Excerpt of the Blog Post
  navbar_active: Blogs
  pub-date: June 20
  pub-year: 2019
  category: news
  comments: true
  ---

  ```

  - **layout**: Defines style settings for different types of contents. All blog posts use the _posts_ layout
  - **author**: Sets the author's name, will publicly appear on the post. As a rule of thumb, use your GitHub username, Twitter handler or any other identifier known in the community
  - **title**: The title for your blog post
  - **description**: Short extract of the blog post
  - **navbar_active**: Defines settings for the navigation bar, type _Blogs_ is the only choice available
  - **pub-date**: Month and day, together with _pub-year_ form the date that will be shown in the blog post as the date it was published, must match the date on the file name
  - **pub-year**: Blog post publication year, must match the year in the file name
  - **category**: Array of categories for your blog post, some common ones are community, news and releases, as last resort, use uncategorized. If you'd like to add multiple categories, used _categories_ instead of _category_ and a [YAML list](https://en.wikipedia.org/wiki/YAML#Basic_components)
  - **comments**: This enables comments your blog post. Please consider setting this to _true_ and allow discussion around the topic you're writing, otherwise skip the field or set it to false

- Blog post contents recommendation:

  - Title is a very important piece of your blog post, a catchy title will likely have more readers, write a bad title and no matter how good the contents is, you'll likely get less readers
  - After the title, write a brief introduction of what you're going to be writing about, which will help the reader to get a grasp on the topic
  - Closing section, the same way we can add a brief introduction of what the blog post is about, it's very important to add a closing section with thoughts, upcoming work on the topic discussed, encourage readers to test something and share their findings, joining the community, ...

  * For big images, you can use photoswipe to show a miniature that is zoomable, to do so, insert code like this:

    ```html
    <div class="my-gallery" itemscope itemtype="http://schema.org/ImageGallery">
      <figure
        itemprop="associatedMedia"
        itemscope
        itemtype="http://schema.org/ImageObject"
      >
        <a
          href="/assets/images/kubevirt-skydive-vm-to-vm.png"
          itemprop="contentUrl"
          data-size="2496x2269"
        >
          <img
            src="/assets/images/kubevirt-skydive-vm-to-vm.png"
            width="249"
            height="226"
            itemprop="thumbnail"
            alt="VM to VM"
          />
        </a>
        <figcaption itemprop="caption description">VM to VM</figcaption>
      </figure>
    </div>
    ```

    It's very important to define the original image size in `data-size` to match the current image size and adjust the `<img>` fields `width` and `height` to the miniature you want to use.

    If there's more than one image, that you want to be shown together, leave the `<div>` and add another `<figure>` entry within it.

    Do not change the name of the div class. You can use the `figcaption` inner text to show as title for the image.

### Pages

The _[Pages](https://jekyllrb.com/docs/pages/)_ are located at the [pages](/pages/) directory, to create one follow these steps:

- Create the markdown file, _filename.md_, in [pages](/pages/) directory
- _Pages_ also use [Front Matter](https://jekyllrb.com/docs/front-matter/), here's an example:

  ```yaml
  ---
  layout: default
  title: Introduction
  permalink: /docs/
  navbar_active: Docs
  ---

  ```

- The fields have the same function as for blog posts, but some values are different, as we're producing different contents.

  - **permalink** tells _Jekyll_ what the output path for your page will be, it's useful for linking and web indexers
  - **navbar_active** will add your page to the navigation bar you specify as value, commonly used values are _Docs_ or _Videos_
  - **layout**, just use _default_ as value, it'll include all the necessary parts when your page is generated

- As for the contents, follow the general guidelines above

### Labs

The Labs are usually a set of directed exercises with the objective of teaching something by practising it, e.g. metal3 101, which would introduce metal3 to new and potential users through a series of easy (101!) exercises. They are composed of a [Landing page](https://en.wikipedia.org/wiki/Landing_page) and the actual exercises.

#### Lab landing page

[Landing pages](https://en.wikipedia.org/wiki/Landing_page) are the book cover for your lab, for creating it, please follow these steps:

- Use the following Front Matter block includes data for the for your lab's [landing page](https://en.wikipedia.org/wiki/Landing_page), replacing the values by your own:

```yaml
---
layout: labs
title: Metal3 101 Lab
order: 1
permalink: labs/metal3101.html
navbar_active: Labs
---

```

- Modify **title** and **permalink**, and leave the rest as shown in the example
- For the contents, some recommendations:
  - Describe the lab objectives clearly.
  - Clearly state the requirements if any, e.g. laptop, cloud account, ...
  - Describe what anyone would learn when taking the lab.
  - Add references to documentation, projects, ...

#### Lab pages

These are the pages containing actual lab, exercises, documentations, etc... and each of them has to include a similar Front Matter block to the one that follows:

```yaml
---
layout: labs
title: Installing metal3
permalink: /labs/metal3/lab01
lab: metal3 101 Lab
order: 1
```

This time we've got a new field, _lab_, which matches the lab _title_ from the Front Matter block on the landing page above, this is used to build the table of contents. Both _order_ and _layout_ should stay as they are in the example and just adjust the _title_ and _permalink_.

Again use the concepts from the general guidelines section and apply the following suggestions when it makes sense:

- When asking to execute a command that'll produce output, add the output on the lab so the user knows what to expect.
- When working through labs that work on documented features, link to the official documentation either through out the lab or in a _reference_ section in the landing page.
- Be mindful about using files from remote Git repositories or similar, especially if they're not under your control, they might be gone after a while.
