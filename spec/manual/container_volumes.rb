#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Manual test: volumes: option for Docker and Podman runners
#
# Usage:
#   TEST_IMAGE=docker.io/myuser/floe-test-cat-file:latest \
#     bundle exec ruby spec/manual/container_volumes.rb [--runner docker|podman]
#
# Defaults to docker if available, then podman. Override with --runner.
#
# Prerequisites:
#   - Docker or Podman running locally
#   - Test image built and pushed via spec/manual/build_test_images.sh

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))

require "pathname"
require "tmpdir"
require "floe"
require "floe/container_runner"
require "floe/workflow/context"

# Select runner
runner_name =
  if (idx = ARGV.index("--runner"))
    ARGV[idx + 1] || abort("--runner requires an argument (docker or podman)")
  elsif system("docker info > /dev/null 2>&1")
    "docker"
  elsif system("podman info > /dev/null 2>&1")
    "podman"
  else
    abort("Neither docker nor podman is available")
  end

runner_class =
  case runner_name
  when "docker" then Floe::ContainerRunner::Docker
  when "podman" then Floe::ContainerRunner::Podman
  else               abort("Unknown runner: #{runner_name}. Use docker or podman.")
  end

puts "Using runner: #{runner_name}"

IMAGE_NAME = ENV.fetch("TEST_IMAGE") do
  abort("TEST_IMAGE is required. Build and push the test image first:\n\n" \
        "  spec/manual/build_test_images.sh\n\n" \
        "Then re-run with TEST_IMAGE=<registry>/floe-test-cat-file:latest")
end

# Run the test
source_dir = Pathname(Dir.mktmpdir("floe-test-"))

begin
  source_dir.join("input.txt").write("hello from host\n")
  puts "Source dir: #{source_dir}"

  runner  = runner_class.new
  context = Floe::Workflow::Context.new({"Execution" => {"Id" => "manual-test-#{runner_name}-volumes"}})

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
