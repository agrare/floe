#!/usr/bin/env bash
# frozen_string_literal: false
#
# Build and push the container images required by the floe manual volume tests.
#
# Usage:
#   spec/manual/build_test_images.sh [--registry REGISTRY] [--tag TAG]
#
# Options:
#   --registry  Registry prefix (default: docker.io/<current-user>)
#   --tag       Image tag       (default: latest)
#
# The script pushes the following images:
#
#   <registry>/floe-test-cat-file:<tag>
#     FROM alpine — CMD ["cat", "/runner/input.txt"]
#     Used by: container_volumes.rb, kubernetes_volumes.rb
#
# After pushing, the script prints the fully-qualified image name.
# Set the TEST_IMAGE env var to that value when running the manual tests:
#
#   TEST_IMAGE=docker.io/myuser/floe-test-cat-file:latest \
#     bundle exec ruby spec/manual/container_volumes.rb
#
#   TEST_IMAGE=docker.io/myuser/floe-test-cat-file:latest \
#     S3_ENDPOINT=http://host.containers.internal:9000 \
#     bundle exec ruby spec/manual/kubernetes_volumes.rb

set -euo pipefail

REGISTRY="${REGISTRY:-docker.io/$(id -un)}"
TAG="latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --tag)      TAG="$2";      shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="$(mktemp -d)"
trap 'rm -rf "$BUILD_ROOT"' EXIT

build_and_push() {
  local name="$1"
  local full="${REGISTRY}/${name}:${TAG}"

  echo "==> Building ${full}"
  docker build -q -t "$full" "${BUILD_ROOT}/${name}"

  echo "==> Pushing ${full}"
  docker push "$full"

  echo ""
  echo "    TEST_IMAGE=${full}"
  echo ""
}

# ── floe-test-cat-file ────────────────────────────────────────────────────────
mkdir -p "${BUILD_ROOT}/floe-test-cat-file"
cat > "${BUILD_ROOT}/floe-test-cat-file/Dockerfile" <<'DOCKERFILE'
FROM alpine:latest
CMD ["cat", "/runner/input.txt"]
DOCKERFILE

build_and_push "floe-test-cat-file"
