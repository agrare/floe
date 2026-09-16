#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Manual test: volumes: and command: options for Docker, Podman, and Kubernetes runners
#
# Usage:
#   bundle exec ruby spec/manual/runner_volumes.rb --runner docker|podman|kubernetes
#
#   # Named / persistent volume variant:
#   bundle exec ruby spec/manual/runner_volumes.rb --runner docker|podman|kubernetes \
#     --use-persistent-volume
#
# Prerequisites:
#   - For docker/podman: Docker or Podman running locally
#   - For kubernetes:
#     - A Kubernetes cluster reachable from the host (kubeconfig or KUBE_SERVER+KUBE_TOKEN)
#     - A MinIO instance reachable from both the host and from within the cluster
#       (only needed for the host-path variant; not required for --use-persistent-volume)
#
# --use-persistent-volume notes:
#
#   Docker / Podman:
#     Creates a named Docker/Podman volume (floe-test-<uuid>), seeds it with
#     input.txt using a one-shot busybox container, then mounts it as a named
#     volume into the test container. The volume is removed after the test.
#
#   Kubernetes:
#     Creates a PersistentVolumeClaim (floe-test-<uuid>) in the target namespace,
#     seeds it with input.txt using a one-shot pod, then passes it as a named
#     volume to run_async!. The PVC and seed pod are removed after the test.
#
#     The default storage class must support ReadWriteOnce. Override the
#     storage class with KUBE_STORAGE_CLASS=<name> if needed.
#
# Kubernetes / S3 (MinIO) notes (host-path variant only):
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

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "floe", :path => File.expand_path("../..", __dir__)
  gem "awesome_spawn", "~> 1.6"
  gem "kubeclient"
  gem "aws-sdk-s3"
end

require "logger"
require "pathname"
require "securerandom"
require "tmpdir"
require "floe"
require "floe/container_runner"
require "floe/workflow/context"

Floe.logger = Logger.new($stdout, :level => Logger::DEBUG)

#
# Argument parsing
#

RUNNER_NAME =
  if (idx = ARGV.index("--runner"))
    ARGV[idx + 1] || abort("--runner requires an argument (docker, podman, or kubernetes)")
  else
    abort("--runner is required. Usage: --runner docker|podman|kubernetes")
  end

USE_PERSISTENT_VOLUME = ARGV.include?("--use-persistent-volume")

TEST_IMAGE = ENV.fetch("TEST_IMAGE", "busybox:latest")
COMMAND    = ["cat", "/runner/input.txt"].freeze

#
# Runner construction
#

runner =
  case RUNNER_NAME
  when "docker"
    Floe::ContainerRunner::Docker.new
  when "podman"
    Floe::ContainerRunner::Podman.new
  when "kubernetes"
    kube_server   = ENV.fetch("KUBE_SERVER",   nil)
    kube_token    = ENV.fetch("KUBE_TOKEN",    nil)
    s3_endpoint   = ENV.fetch("S3_ENDPOINT",   "http://host.containers.internal:9000")
    s3_bucket     = ENV.fetch("S3_BUCKET",     "floe-inputs")
    s3_access_key = ENV.fetch("S3_ACCESS_KEY", "minioadmin")
    s3_secret_key = ENV.fetch("S3_SECRET_KEY", "minioadmin")
    init_image    = ENV.fetch("INIT_IMAGE",    "curlimages/curl:latest")

    options = {
      "s3_endpoint"   => s3_endpoint,
      "s3_bucket"     => s3_bucket,
      "s3_access_key" => s3_access_key,
      "s3_secret_key" => s3_secret_key,
      "init_image"    => init_image
    }
    options["server"] = kube_server if kube_token
    options["token"]  = kube_token  if kube_token

    Floe::ContainerRunner::Kubernetes.new(options)
  else
    abort("Unknown runner: #{RUNNER_NAME}. Use docker, podman, or kubernetes.")
  end

puts "Using runner:             #{RUNNER_NAME}"
puts "Persistent-volume mode:   #{USE_PERSISTENT_VOLUME}"
puts "Image:                    #{TEST_IMAGE}"
puts "Command:                  #{COMMAND.inspect}"

#
# Helpers: shell
#

# Runs cmd and raises on non-zero exit.
def run!(*cmd)
  puts "  + #{cmd.join(' ')}"
  AwesomeSpawn.run!(cmd.first, :params => cmd[1..]).output
end

# Runs cmd and suppresses errors (for best-effort cleanup calls).
def run(*cmd)
  puts "  + #{cmd.join(' ')}"
  AwesomeSpawn.run(cmd.first, :params => cmd[1..])
end

#
# Helpers: Docker / Podman named volumes
#

DOCKER_CMD = RUNNER_NAME == "podman" ? "podman" : "docker"

def create_docker_volume(name)
  run!(DOCKER_CMD, "volume", "create", name)
  puts "Created #{DOCKER_CMD} volume: #{name}"
end

# Seed a named Docker/Podman volume with a file by running a one-shot container.
def seed_docker_volume(volume_name, dest_path, content)
  run!(
    DOCKER_CMD, "run", "--rm",
    "-v", "#{volume_name}:#{File.dirname(dest_path)}",
    "busybox",
    "sh", "-c", "echo -n '#{content.gsub("'", "'\\''")}' > #{dest_path}"
  )
  puts "Seeded #{DOCKER_CMD} volume #{volume_name} with #{dest_path}"
end

def delete_docker_volume(name)
  run(DOCKER_CMD, "volume", "rm", name)
  puts "Deleted #{DOCKER_CMD} volume: #{name}"
end

#
# Helpers: Kubernetes PVCs
#

KUBE_NAMESPACE     = ENV.fetch("KUBE_NAMESPACE",    "default")
KUBE_SEED_IMAGE    = ENV.fetch("KUBE_SEED_IMAGE",   "busybox:latest")
KUBE_STORAGE_CLASS = ENV.fetch("KUBE_STORAGE_CLASS", nil)

def kubectl!(*args)
  run!("kubectl", "--namespace", KUBE_NAMESPACE, *args)
end

def kubectl(*args)
  run("kubectl", "--namespace", KUBE_NAMESPACE, *args)
end

def create_kube_pvc(name)
  storage_class_line = KUBE_STORAGE_CLASS ? "storageClassName: #{KUBE_STORAGE_CLASS}" : ""
  manifest = <<~YAML
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: #{name}
      namespace: #{KUBE_NAMESPACE}
    spec:
      accessModes: [ReadWriteOnce]
      #{storage_class_line}
      resources:
        requests:
          storage: 10Mi
  YAML

  Tempfile.create(["floe-pvc", ".yaml"]) do |f|
    f.write(manifest)
    f.flush
    kubectl!("apply", "-f", f.path)
  end
  puts "Created PVC: #{name}"
end

# Seed a PVC by running a one-shot pod, then waiting for it to complete.
def seed_kube_pvc(pvc_name, dest_path, content)
  pod_name = "floe-seed-#{SecureRandom.hex(4)}"
  escaped  = content.gsub("'", "'\\''")
  manifest = <<~YAML
    apiVersion: v1
    kind: Pod
    metadata:
      name: #{pod_name}
      namespace: #{KUBE_NAMESPACE}
    spec:
      restartPolicy: Never
      containers:
      - name: seed
        image: #{KUBE_SEED_IMAGE}
        command: ["sh", "-c", "mkdir -p #{File.dirname(dest_path)} && echo -n '#{escaped}' > #{dest_path}"]
        volumeMounts:
        - name: data
          mountPath: #{File.dirname(dest_path)}
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: #{pvc_name}
  YAML

  Tempfile.create(["floe-seed-pod", ".yaml"]) do |f|
    f.write(manifest)
    f.flush
    kubectl!("apply", "-f", f.path)
  end

  puts "Waiting for seed pod #{pod_name} to complete..."
  kubectl!("wait", "--for=jsonpath={.status.phase}=Succeeded", "--timeout=120s", "pod/#{pod_name}")
  puts "Seed pod completed."
ensure
  kubectl("delete", "pod", pod_name, "--ignore-not-found=true")
end

def delete_kube_pvc(name)
  kubectl("delete", "pvc", name, "--ignore-not-found=true")
  puts "Deleted PVC: #{name}"
end

#
# Main test
#

context   = Floe::Workflow::Context.new({"Execution" => {"Id" => "manual-#{RUNNER_NAME}-#{SecureRandom.uuid}"}})
volume_id = "floe-test-#{SecureRandom.hex(6)}"
rc        = nil

begin
  volumes =
    if USE_PERSISTENT_VOLUME
      case RUNNER_NAME
      when "docker", "podman"
        create_docker_volume(volume_id)
        seed_docker_volume(volume_id, "/runner/input.txt", "hello from volume")
        [{:volume_name => volume_id, :container_path => "/runner"}]
      when "kubernetes"
        create_kube_pvc(volume_id)
        seed_kube_pvc(volume_id, "/runner/input.txt", "hello from volume")
        [{:volume_name => volume_id, :container_path => "/runner"}]
      end
    else
      source_dir = Pathname(Dir.mktmpdir("floe-test-"))
      source_dir.join("input.txt").write("hello from host")
      puts "Source dir: #{source_dir}"
      [{:host_path => source_dir.to_s, :container_path => "/runner"}]
    end

  puts "Calling run_async!..."
  rc = runner.run_async!(
    "docker://#{TEST_IMAGE}",
    {},
    {},
    context,
    :volumes => volumes,
    :command => COMMAND
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

  expected = USE_PERSISTENT_VOLUME ? "hello from volume" : "hello from host"
  if output.strip == expected
    puts "\n\e[32m✓\e[0m PASS: container read the mounted file correctly"
  else
    puts "\n\e[31m✗\e[0m FAIL: unexpected output"
    exit 1
  end
ensure
  runner&.cleanup(rc) if rc
  source_dir&.rmtree

  if USE_PERSISTENT_VOLUME
    case RUNNER_NAME
    when "docker", "podman"
      delete_docker_volume(volume_id)
    when "kubernetes"
      delete_kube_pvc(volume_id)
    end
  end
end
