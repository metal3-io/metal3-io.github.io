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
        docker.io/python:3.12.3-bullseye@sha256:82e37316cd3f0e9c696bb9428df38a2e39a9286ee864286f8285185b685b60ee \
        /workdir/hack/pre-commit.sh "$@"
fi
