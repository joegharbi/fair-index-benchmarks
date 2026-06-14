#!/usr/bin/env bash
# Build both fair index images and push them to a registry the GMT cloud can pull.
# Usage:
#   GHCR_USER=joegharbi TAG=v1 ./scripts/build_and_push.sh           # build + push to ghcr.io
#   PUSH=0 ./scripts/build_and_push.sh                               # build only (local tags)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load local configuration (registry namespace, tag) if present — see .env.example.
if [ -f "$HERE/.env" ]; then set -a; . "$HERE/.env"; set +a; fi

REGISTRY="${REGISTRY:-ghcr.io}"
GHCR_USER="${GHCR_USER:-joegharbi}"
TAG="${TAG:-v1}"
PUSH="${PUSH:-1}"

build_one () {
  local name="$1" dir="$2"
  if [[ "$PUSH" == "1" ]]; then
    local image="${REGISTRY}/${GHCR_USER}/${name}:${TAG}"
  else
    local image="${name}"   # local tag for local GMT / framework runs
  fi
  echo ">>> Building ${image}"
  docker build -t "${image}" "${dir}"
  if [[ "$PUSH" == "1" ]]; then
    echo ">>> Pushing ${image}"
    docker push "${image}"
  fi
}

build_one fair-erlang-index   "${HERE}/servers/erlang-index"
build_one fair-elixir-index   "${HERE}/servers/elixir-index"
build_one fair-erlang-dynamic   "${HERE}/servers/erlang-dynamic"
build_one fair-elixir-dynamic   "${HERE}/servers/elixir-dynamic"
build_one fair-erlang-websocket "${HERE}/servers/erlang-websocket"
build_one fair-elixir-websocket "${HERE}/servers/elixir-websocket"

if [[ "$PUSH" == "1" ]]; then
  echo "Done. In GitHub > your profile > Packages, set both packages to PUBLIC so the"
  echo "GMT cloud workers can pull them (or give Green Coding private pull credentials)."
else
  echo "Done. Local images: fair-{erlang,elixir}-{index,dynamic,websocket}"
fi
