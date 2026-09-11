RSpec.describe Floe::ContainerRunner::Podman do
  require "securerandom"

  let(:subject)        { described_class.new(runner_options) }
  let(:execution_id)   { SecureRandom.uuid }
  let(:context)        { Floe::Workflow::Context.new({"Execution" => {"Id" => execution_id}}) }
  let(:runner_options) { {} }
  let(:container_id)   { SecureRandom.hex }

  describe "#run_async!" do
    it "raises an exception without a resource" do
      expect { subject.run_async!(nil, {}, {}, context) }.to raise_error(ArgumentError, "Invalid resource")
    end

    it "raises an exception for an invalid resource uri" do
      expect { subject.run_async!("arn:abcd:efgh", {}, {}, context) }.to raise_error(ArgumentError, "Invalid resource")
    end

    it "calls docker run with the image name" do
      stub_good_run!("podman", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

      subject.run_async!("docker://hello-world:latest", {}, {}, context)
    end

    it "passes environment variables to podman run" do
      stub_good_run!("podman", :params => ["run", :detach, [:e, "FOO=BAR"], [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

      subject.run_async!("docker://hello-world:latest", {"FOO" => "BAR"}, {}, context)
    end

    it "sets the container id in runner_context" do
      stub_good_run!("podman", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

      expect(subject.run_async!("docker://hello-world:latest", {}, {}, context)).to include("container_ref" => container_id)
    end

    it "passes a secrets volume to podman run" do
      stub_good_run!("podman", :params => ["secret", "create", anything, "-"], :in_data => {"luggage_password" => "12345"}.to_json)
      stub_good_run!("podman", :params => ["run", :detach, [:e, "FOO=BAR"], [:e, a_string_including("_CREDENTIALS=")], [:label, "execution_id=#{execution_id}"], [:secret, anything], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

      subject.run_async!("docker://hello-world:latest", {"FOO" => "BAR"}, {"luggage_password" => "12345"}, context)
    end

    it "deletes the secret if running the container fails" do
      stub_good_run!("podman", :params => ["secret", "create", anything, "-"], :in_data => {"luggage_password" => "12345"}.to_json)
      stub_bad_run!("podman", :params => ["run", :detach, [:e, "FOO=BAR"], [:e, a_string_including("_CREDENTIALS=")], [:label, "execution_id=#{execution_id}"], [:secret, anything], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"])
      stub_good_run!("podman", :params => ["secret", "rm", anything])

      expect(subject.run_async!("docker://hello-world:latest", {"FOO" => "BAR"}, {"luggage_password" => "12345"}, context))
        .to eq({"Error" => "States.TaskFailed", "Cause" => "podman exit code: 1 error was: Failure"})
    end
  end

  describe "#status!" do
    let(:runner_context) { {"container_ref" => container_id} }

    it "returns the updated container_state" do
      stub_good_run!("podman", :params => ["inspect", container_id], :output => "[{\"State\": {\"Running\": true}}]")

      subject.status!(runner_context)

      expect(runner_context).to include("container_state" => {"Running" => true})
    end
  end

  describe "#running?" do
    it "retuns true when running" do
      runner_context = {"container_ref" => container_id, "container_state" => {"Running" => true}}
      expect(subject.running?(runner_context)).to be_truthy
    end

    it "retuns false when not running" do
      runner_context = {"container_ref" => container_id, "container_state" => {"Running" => false, "ExitCode" => 0}}
      expect(subject.running?(runner_context)).to be_falsey
    end
  end

  describe "#success?" do
    it "retuns true when successful" do
      runner_context = {"container_ref" => container_id, "container_state" => {"Running" => false, "ExitCode" => 0}}
      expect(subject.success?(runner_context)).to be_truthy
    end

    it "retuns false when not successful" do
      runner_context = {"container_ref" => container_id, "container_state" => {"Running" => false, "ExitCode" => 1}}
      expect(subject.success?(runner_context)).to be_falsey
    end
  end

  describe "#output" do
    let(:runner_context) { {"container_ref" => container_id} }

    it "returns log output" do
      stub_good_run!("podman", :params => ["logs", container_id], :combined_output => true, :output => "hello, world!")
      expect(subject.output(runner_context)).to eq("hello, world!")
    end
  end

  describe "#cleanup" do
    it "deletes the container and secret" do
      stub_good_run!("podman", :params => ["secret", "rm", "my-secret"])
      stub_good_run!("podman", :params => ["rm", container_id, "--force"])

      subject.cleanup({"container_ref" => container_id, "secrets_ref" => "my-secret"})
    end

    it "doesn't delete the secret if one isn't passed in" do
      stub_good_run!("podman", :params => ["rm", container_id, "--force"])

      subject.cleanup({"container_ref" => container_id})
    end

    it "deletes the secret if deleting the pod fails" do
      stub_good_run!("podman", :params => ["secret", "rm", "my-secret"])
      stub_bad_run!("podman", :params => ["rm", container_id, "--force"])

      subject.cleanup({"container_ref" => container_id, "secrets_ref" => "my-secret"})
    end
  end

  context "run_async! parameters" do
    context "with volumes" do
      it "defaults volume options to z" do
        stub_good_run!("podman", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:v, "/tmp/runner:/runner:z"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

        subject.run_async!("docker://hello-world:latest", {}, {}, context, :volumes => [{:host_path => "/tmp/runner", :container_path => "/runner"}])
      end

      it "uses caller-supplied options when provided" do
        stub_good_run!("podman", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:v, "/tmp/runner:/runner:ro"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

        subject.run_async!("docker://hello-world:latest", {}, {}, context, :volumes => [{:host_path => "/tmp/runner", :container_path => "/runner", :options => "ro"}])
      end

      it "passes multiple volumes to podman run" do
        stub_good_run!("podman", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:v, "/tmp/a:/a:z"], [:v, "/tmp/b:/b:ro"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

        subject.run_async!("docker://hello-world:latest", {}, {}, context, :volumes => [{:host_path => "/tmp/a", :container_path => "/a"}, {:host_path => "/tmp/b", :container_path => "/b", :options => "ro"}])
      end
    end

    context "with docker runner options" do
      context "with --identity" do
        let(:runner_options) { {"identity" => ".ssh/id_rsa.pub"} }

        it "calls docker run with --identity .ssh/id_rsa.pub" do
          stub_good_run!("podman", :params => [[:identity, ".ssh/id_rsa.pub"], "run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

          subject.run_async!("docker://hello-world:latest", {}, {}, context)
        end
      end

      context "with --log-level" do
        let(:runner_options) { {"log-level" => "debug"} }

        it "calls docker run with --log-level debug" do
          stub_good_run!("podman", :params => [[:"log-level", "debug"], "run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

          subject.run_async!("docker://hello-world:latest", {}, {}, context)
        end
      end

      context "with --network" do
        let(:runner_options) { {"network" => "host"} }

        it "calls docker run with --net host" do
          stub_good_run!("podman", :params => ["run", :detach, [:net, "host"], [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

          subject.run_async!("docker://hello-world:latest", {}, {}, context)
        end
      end

      context "with --noout" do
        let(:runner_options) { {"noout" => "true"} }

        it "calls docker run with --noout" do
          stub_good_run!("podman", :params => [:noout, "run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

          subject.run_async!("docker://hello-world:latest", {}, {}, context)
        end
      end

      context "with pull-policy=newer" do
        let(:runner_options) { {"pull-policy" => "newer"} }

        it "calls podman run with --noout" do
          stub_good_run!("podman", :params => ["run", :detach, [:pull, "newer"], [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

          subject.run_async!("docker://hello-world:latest", {}, {}, context)
        end
      end

      context "with --root" do
        let(:runner_options) { {"root" => "/run/containers/storage"} }

        it "calls docker run with --root /run/containers/storage" do
          stub_good_run!("podman", :params => [[:root, "/run/containers/storage"], "run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

          subject.run_async!("docker://hello-world:latest", {}, {}, context)
        end
      end

      context "with --runroot" do
        let(:runner_options) { {"runroot" => "/run/containers/runtime"} }

        it "calls docker run with --runroot /run/containers/runtime" do
          stub_good_run!("podman", :params => [[:runroot, "/run/containers/runtime"], "run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

          subject.run_async!("docker://hello-world:latest", {}, {}, context)
        end
      end

      context "with --runtime-flag" do
        let(:runner_options) { {"runtime-flag" => "'log debug'"} }

        it "calls docker run with --runtime-flag 'log debug'" do
          stub_good_run!("podman", :params => [[:"runtime-flag", "'log debug'"], "run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

          subject.run_async!("docker://hello-world:latest", {}, {}, context)
        end
      end

      context "with --storage-driver" do
        let(:runner_options) { {"storage-driver" => "overlay"} }

        it "calls docker run with --storage-driver overlay" do
          stub_good_run!("podman", :params => [[:"storage-driver", "overlay"], "run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

          subject.run_async!("docker://hello-world:latest", {}, {}, context)
        end
      end

      context "with --storage-opt" do
        let(:runner_options) { {"storage-opt" => "ignore_chown_errors=true"} }

        it "calls docker run with --storage-driver overlay" do
          stub_good_run!("podman", :params => [[:"storage-opt", "ignore_chown_errors=true"], "run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

          subject.run_async!("docker://hello-world:latest", {}, {}, context)
        end
      end
    end
  end
end
