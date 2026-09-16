#!/usr/bin/env bats
#
# Bats test suite for spec/manual/runner_volumes.rb
#
# Runs all six combinations:
#   --runner docker
#   --runner docker   --use-persistent-volume
#   --runner podman
#   --runner podman   --use-persistent-volume
#   --runner kubernetes
#   --runner kubernetes --use-persistent-volume
#
# Prerequisites:
#   - TEST_IMAGE must be set (see spec/manual/build_test_images.sh)
#   - Docker / Podman must be running locally for those runners
#   - Kubernetes tests require a reachable cluster; they are skipped when
#     `kubectl cluster-info` fails
#   - The host-path Kubernetes test also requires MinIO (S3_ENDPOINT etc.)
#
# Usage:
#   TEST_IMAGE=docker.io/myuser/floe-test-cat-file:latest \
#     bats spec/manual/runner_volumes.bats

SCRIPT="$(dirname "$BATS_TEST_FILENAME")/runner_volumes.rb"

#
# Helpers
#

require_test_image() {
  if [[ -z "${TEST_IMAGE:-}" ]]; then
    skip "TEST_IMAGE is not set — build and push the test image first via spec/manual/build_test_images.sh"
  fi
}

require_docker() {
  if ! docker info &>/dev/null; then
    skip "Docker daemon is not reachable"
  fi
}

require_podman() {
  if ! podman info &>/dev/null; then
    skip "Podman daemon is not reachable"
  fi
}

require_kubernetes() {
  if ! kubectl cluster-info &>/dev/null; then
    skip "Kubernetes cluster is not reachable (kubectl cluster-info failed)"
  fi
}

assert_pass() {
  local plain
  plain="$(sed 's/\x1b\[[0-9;]*m//g' <<< "$output")"
  [[ "$plain" == *"✓ PASS"* ]]
}

#
# Tests
#

@test "docker: host-path volume" {
  require_test_image
  require_docker
  run ruby "$SCRIPT" --runner docker
  echo "$output"
  [ "$status" -eq 0 ]
  assert_pass
}

@test "docker: persistent volume" {
  require_test_image
  require_docker
  run ruby "$SCRIPT" --runner docker --use-persistent-volume
  echo "$output"
  [ "$status" -eq 0 ]
  assert_pass
}

@test "podman: host-path volume" {
  require_test_image
  require_podman
  run ruby "$SCRIPT" --runner podman
  echo "$output"
  [ "$status" -eq 0 ]
  assert_pass
}

@test "podman: persistent volume" {
  require_test_image
  require_podman
  run ruby "$SCRIPT" --runner podman --use-persistent-volume
  echo "$output"
  [ "$status" -eq 0 ]
  assert_pass
}

@test "kubernetes: host-path volume" {
  require_test_image
  require_kubernetes
  run ruby "$SCRIPT" --runner kubernetes
  echo "$output"
  [ "$status" -eq 0 ]
  assert_pass
}

@test "kubernetes: persistent volume" {
  require_test_image
  require_kubernetes
  run ruby "$SCRIPT" --runner kubernetes --use-persistent-volume
  echo "$output"
  [ "$status" -eq 0 ]
  assert_pass
}
