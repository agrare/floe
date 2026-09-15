#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Manual test: volumes: option for Docker, Podman, and Kubernetes runners
#
# Usage:
#   TEST_IMAGE=docker.io/myuser/floe-test-cat-file:latest \
#     bundle exec ruby spec/manual/runner_volumes.rb --runner docker|podman|kubernetes
#
# Prerequisites:
#   - Test image built and pushed via spec/manual/build_test_images.sh
#   - For docker/podman: Docker or Podman running locally
#   - For kubernetes:
#     - A Kubernetes cluster reachable from the host (kubeconfig or KUBE_SERVER+KUBE_TOKEN)
#     - A MinIO instance reachable from both the host and from within the cluster
#
# Kubernetes / S3 (MinIO) notes:
#
#   The S3_ENDPOINT hostname is used to generate presigned URLs, so it must
#   resolve correctly from both the host (for the initial upload) and from inside
#   cluster pods (for the init container download). Use a hostname that satisfies
#   both — for example, host.containers.internal if MinIO is running on the local
#   machine and that name is resolvable in both contexts.
#
#   One way to set this up locally (kind + MinIO on the host):
#
#     # Start a kind cluster
#     kind create cluster
#
#     # Run MinIO on the host
#     podman run -d -p 9000:9000 -p 9001:9001 \
#       -e MINIO_ROOT_USER=minioadmin \
#       -e MINIO_ROOT_PASSWORD=minioadmin \
#       quay.io/minio/minio server /data --console-address ":9001"
#
#     # Create the bucket
#     podman run --rm --entrypoint sh quay.io/minio/mc -c \
#       "mc alias set local http://host.containers.internal:9000 minioadmin minioadmin && mc mb local/floe-inputs"
#
#   Verify both sides can reach MinIO before running the test:
#
#     # From the host:
#     curl -s http://host.containers.internal:9000/minio/health/live && echo "host -> MinIO OK"
#
#     # From inside the cluster:
#     kubectl run curltest --image=curlimages/curl --restart=Never --rm -it \
#       -- curl -s http://host.containers.internal:9000/minio/health/live && echo "pod -> MinIO OK"

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))

require "pathname"
require "securerandom"
require "tmpdir"
require "floe"
require "floe/container_runner"
require "floe/workflow/context"

# --runner is required
runner_name =
  if (idx = ARGV.index("--runner"))
    ARGV[idx + 1] || abort("--runner requires an argument (docker, podman, or kubernetes)")
  else
    abort("--runner is required. Usage: --runner docker|podman|kubernetes")
  end

IMAGE_NAME = ENV.fetch("TEST_IMAGE") do
  abort("TEST_IMAGE is required. Build and push the test image first:\n\n" \
        "  spec/manual/build_test_images.sh\n\n" \
        "Then re-run with TEST_IMAGE=<registry>/floe-test-cat-file:latest")
end

runner =
  case runner_name
  when "docker"
    Floe::ContainerRunner::Docker.new
  when "podman"
    Floe::ContainerRunner::Podman.new
  when "kubernetes"
    kube_server   = ENV.fetch("KUBE_SERVER",   "https://localhost:6443")
    kube_token    = ENV.fetch("KUBE_TOKEN",    nil)
    s3_endpoint   = ENV.fetch("S3_ENDPOINT",   "http://host.containers.internal:9000")
    s3_bucket     = ENV.fetch("S3_BUCKET",     "floe-inputs")
    s3_access_key = ENV.fetch("S3_ACCESS_KEY", "minioadmin")
    s3_secret_key = ENV.fetch("S3_SECRET_KEY", "minioadmin")
    sidecar_image = ENV.fetch("SIDECAR_IMAGE", "curlimages/curl:latest")

    options = {
      "s3_endpoint"   => s3_endpoint,
      "s3_bucket"     => s3_bucket,
      "s3_access_key" => s3_access_key,
      "s3_secret_key" => s3_secret_key,
      "sidecar_image" => sidecar_image
    }
    options["server"] = kube_server if kube_token
    options["token"]  = kube_token  if kube_token

    Floe::ContainerRunner::Kubernetes.new(options)
  else
    abort("Unknown runner: #{runner_name}. Use docker, podman, or kubernetes.")
  end

puts "Using runner: #{runner_name}"

source_dir = Pathname(Dir.mktmpdir("floe-test-"))

begin
  source_dir.join("input.txt").write("hello from host\n")
  puts "Source dir: #{source_dir}"

  context = Floe::Workflow::Context.new({"Execution" => {"Id" => "manual-#{runner_name}-#{SecureRandom.uuid}"}})

  puts "Calling run_async!..."
  rc = runner.run_async!(
    "docker://#{IMAGE_NAME}",
    {},
    {},
    context,
    :volumes => [{:host_path => source_dir.to_s, :container_path => "/runner"}]
  )

  loop do
    runner.status!(rc)
    break unless runner.running?(rc)

    print "."
    sleep 0.5
  end
  puts

  puts "success? #{runner.success?(rc)}"
  output = runner.output(rc)
  puts "output:  #{output.inspect}"

  if output.strip == "hello from host"
    puts "\n\e[32m✓\e[0m PASS: container read the mounted file correctly"
  else
    puts "\n\e[31m✗\e[0m FAIL: unexpected output"
    exit 1
  end
ensure
  runner&.cleanup(rc) if rc
  source_dir.rmtree
end
