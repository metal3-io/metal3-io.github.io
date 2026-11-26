#!/bin/sh

set -eux

IS_CONTAINER="${IS_CONTAINER:-false}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-podman}"

if [ "${IS_CONTAINER}" != "false" ]; then
    git config --global --add safe.directory /workdir
    pip install pre-commit
    pre-commit run --all-files
else
    "${CONTAINER_RUNTIME}" run --rm \
        --env IS_CONTAINER=TRUE \
        --volume "${PWD}:/workdir:z" \
        --entrypoint sh \
        --workdir /workdir \
        docker.io/python:3.14-bookworm@sha256:fbaf91204f2758a70a7f7d6cf3c2871851227152a54e6a7b5b59941c4566b6b5 \
        /workdir/hack/pre-commit.sh "$@"
fi
