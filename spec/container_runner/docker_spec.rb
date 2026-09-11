RSpec.describe Floe::ContainerRunner::Docker do
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
      stub_good_run!("docker", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest",], :output => "#{container_id}\n")

      subject.run_async!("docker://hello-world:latest", {}, {}, context)
    end

    it "passes environment variables to docker run" do
      stub_good_run!("docker", :params => ["run", :detach, [:e, "FOO=BAR"], [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

      subject.run_async!("docker://hello-world:latest", {"FOO" => "BAR"}, {}, context)
    end

    it "passes a secrets volume to docker run" do
      stub_good_run!("docker", :params => ["run", :detach, [:e, "FOO=BAR"], [:e, "_CREDENTIALS=/run/secrets"], [:label, "execution_id=#{execution_id}"], [:v, a_string_including(":/run/secrets")], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

      subject.run_async!("docker://hello-world:latest", {"FOO" => "BAR"}, {"luggage_password" => "12345"}, context)
    end

    it "sets the container id in runner_context" do
      stub_good_run!("docker", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest",], :output => "#{container_id}\n")

      expect(subject.run_async!("docker://hello-world:latest", {}, {}, context)).to include("container_ref" => container_id)
    end

    context "with network=host" do
      let(:runner_options) { {"network" => "host"} }

      it "calls docker run with --net host" do
        stub_good_run!("docker", :params => ["run", :detach, [:net, "host"], [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"])

        subject.run_async!("docker://hello-world:latest", {}, {}, context)
      end
    end

    context "with pull-policy=always" do
      let(:runner_options) { {"pull-policy" => "always"} }

      it "calls docker run with --pull always" do
        stub_good_run!("docker", :params => ["run", :detach, [:pull, "always"], [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"])

        subject.run_async!("docker://hello-world:latest", {}, {}, context)
      end
    end

    context "with volumes" do
      it "defaults volume options to z" do
        stub_good_run!("docker", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:v, "/tmp/runner:/runner:z"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

        subject.run_async!("docker://hello-world:latest", {}, {}, context, :volumes => [{:host_path => "/tmp/runner", :container_path => "/runner"}])
      end

      it "uses caller-supplied options when provided" do
        stub_good_run!("docker", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:v, "/tmp/runner:/runner:ro"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

        subject.run_async!("docker://hello-world:latest", {}, {}, context, :volumes => [{:host_path => "/tmp/runner", :container_path => "/runner", :options => "ro"}])
      end

      it "omits options when explicitly set to nil" do
        stub_good_run!("docker", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:v, "/tmp/runner:/runner"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

        subject.run_async!("docker://hello-world:latest", {}, {}, context, :volumes => [{:host_path => "/tmp/runner", :container_path => "/runner", :options => nil}])
      end

      it "passes multiple volumes to docker run" do
        stub_good_run!("docker", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:v, "/tmp/a:/a:z"], [:v, "/tmp/b:/b:ro"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

        subject.run_async!("docker://hello-world:latest", {}, {}, context, :volumes => [{:host_path => "/tmp/a", :container_path => "/a"}, {:host_path => "/tmp/b", :container_path => "/b", :options => "ro"}])
      end

      it "passes no volumes when volumes is empty" do
        stub_good_run!("docker", :params => ["run", :detach, [:label, "execution_id=#{execution_id}"], [:name, a_string_starting_with("floe-hello-world-")], "hello-world:latest"], :output => "#{container_id}\n")

        subject.run_async!("docker://hello-world:latest", {}, {}, context, :volumes => [])
      end
    end
  end

  describe "#status!" do
    it "returns the updated container_state" do
      stub_good_run!("docker", :params => ["inspect", container_id], :output => "[{\"State\": {\"Running\": true}}]")
      runner_context = {"container_ref" => container_id}

      subject.status!(runner_context)

      expect(runner_context).to include("container_state" => {"Running" => true})
    end
  end

  describe "#running?" do
    it "returns true when running" do
      runner_context = {"container_ref" => container_id, "container_state" => {"Running" => true}}
      expect(subject.running?(runner_context)).to be_truthy
    end

    it "returns false when completed" do
      runner_context = {"container_ref" => container_id, "container_state" => {"Running" => false, "ExitCode" => 0}}
      expect(subject.running?(runner_context)).to be_falsey
    end
  end

  describe "#success?" do
    it "returns true when successful" do
      runner_context = {"container_ref" => container_id, "container_state" => {"Running" => false, "ExitCode" => 0}}
      expect(subject.success?(runner_context)).to be_truthy
    end

    it "returns false when unsuccessful" do
      runner_context = {"container_ref" => container_id, "container_state" => {"Running" => false, "ExitCode" => 1}}
      expect(subject.success?(runner_context)).to be_falsey
    end
  end

  describe "#output" do
    let(:runner_context) { {"container_ref" => container_id} }

    it "returns log output" do
      stub_good_run!("docker", :params => ["logs", container_id], :combined_output => true, :output => "hello, world!")
      expect(subject.output(runner_context)).to eq("hello, world!")
    end

    it "raises an exception when getting pod logs fails" do
      stub_bad_run!("docker", :params => ["logs", container_id], :combined_output => true)
      expect { subject.output(runner_context) }.to raise_error(AwesomeSpawn::CommandResultError, /docker exit code: 1/)
    end
  end

  describe "#cleanup" do
    let(:secrets_file) { "/tmp/secretfile" }

    it "deletes the container and secret" do
      stub_good_run!("docker", :params => ["rm", container_id, "--force"])
      allow(File).to receive(:exist?).and_call_original
      expect(File).to receive(:exist?).with(secrets_file).and_return(true)
      expect(File).to receive(:unlink).with(secrets_file)
      subject.cleanup({"container_ref" => container_id, "secrets_ref" => secrets_file})
    end

    it "doesn't delete the secret_file if not passed" do
      stub_good_run!("docker", :params => ["rm", container_id, "--force"])
      expect(File).not_to receive(:unlink).with(secrets_file)
      subject.cleanup({"container_ref" => container_id})
    end

    it "deletes the secrets file if deleting the container fails" do
      stub_bad_run!("docker", :params => ["rm", container_id, "--force"])
      allow(File).to receive(:exist?).and_call_original
      expect(File).to receive(:exist?).with(secrets_file).and_return(true)
      expect(File).to receive(:unlink).with(secrets_file)
      subject.cleanup({"container_ref" => container_id, "secrets_ref" => secrets_file})
    end
  end
end
