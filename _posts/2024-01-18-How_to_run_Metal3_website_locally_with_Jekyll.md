---
title: "How to run Metal3 website locally with Jekyll"
date: 2024-01-18
draft: false
categories:
  ["metal3", "baremetal", "metal3-dev-env", "documentation", "development"]
author: Salima Rabiu
---

## Introduction

If you’re a developer or contributor to the Metal3 project, you may need to run the Metal3
website locally to test changes and ensure everything looks as expected before deploying
them. In this guide, we’ll walk you through the process of setting up and running Metal3’s
website locally on your machine using Jekyll.

## Prerequisites

Before we begin, make sure you have the following prerequisites installed on your system:

- Ruby: Jekyll, the static site generator used by Metal3, is built with Ruby. Install Ruby
  and its development tools by running the following command in your terminal:

    ```bash
    sudo apt install ruby-full
    ```

## Setting up Metal3’s Website

Once Ruby is installed, we can proceed to set up Metal3’s website and its dependencies.
Follow these steps:

- Clone the Metal3 website repository from GitHub. Open your terminal and navigate to the directory where you want to clone the repository, then run the following command:

    ```bash
    git clone https://github.com/metal3-io/metal3-io.github.io.git
    ```

- Change to the cloned directory:

   ```bash
   cd metal3-io.github.io
   ```

- Install the required gems and dependencies using Bundler. Run the following command:

   ```bash
    bundle install
    ```

## Running the Metal3 Website Locally

With Metal3’s website and its dependencies installed, you can now start the local
development server to view and test the website. In the terminal, navigate to the
project’s root directory (`metal3-io.github.io`) and run the following command:

   ```bash
   bundle exec jekyll serve
   ```

This command tells Jekyll to build the website and start a local server. Once the server
is running, you’ll see output indicating the local address where the Metal3 website is
being served, typically [http://localhost:4000](http://localhost:4000).

Open your web browser and enter the provided address. Congratulations! You should now see the Metal3 website running locally, allowing you to preview your changes and ensure
everything is working as expected.

## Conclusion

Running Metal3’s website locally using Jekyll is a great way to test changes and ensure the site functions properly before deploying them. By following the steps outlined in
this guide, you’ve successfully set up and run Metal3’s website locally. Feel free to
explore the Metal3 documentation and contribute to the project further.
