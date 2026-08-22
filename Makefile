CONTAINER_RUNTIME ?= $(shell if command -v podman >/dev/null 2>&1; then echo podman; else echo docker; fi)
IMAGE_NAME ?= ruby
IMAGE_TAG ?= bullseye
HOST_PORT ?= 4000

.PHONY: serve
serve: # Serve the website on localhost:3000
	$(CONTAINER_RUNTIME) run \
	--rm -it --name metal3-io \
	-w /srv/jekyll \
	-v "$$(pwd):/srv/jekyll:Z" \
	-p $(HOST_PORT):4000 \
	$(IMAGE_NAME):$(IMAGE_TAG) \
	sh -c "bundle install && bundle exec jekyll serve --future --watch --host 0.0.0.0 --port $(HOST_PORT)"

## ------------------------------------
## Linting and testing
## ------------------------------------

.PHONY: lint
lint: markdownlint spellcheck shellcheck pre-commit # Run all linting tools

.PHONY: markdownlint
markdownlint: # Run markdownlint
	CONTAINER_RUNTIME=$(CONTAINER_RUNTIME) ./hack/markdownlint.sh

.PHONY: spellcheck
spellcheck: # Run spellcheck
	CONTAINER_RUNTIME=$(CONTAINER_RUNTIME) ./hack/spellcheck.sh

.PHONY: shellcheck
shellcheck: # Run shellcheck
	CONTAINER_RUNTIME=$(CONTAINER_RUNTIME) ./hack/shellcheck.sh

.PHONY: pre-commit
pre-commit: # Run pre-commit hooks
	CONTAINER_RUNTIME=$(CONTAINER_RUNTIME) ./hack/pre-commit.sh
