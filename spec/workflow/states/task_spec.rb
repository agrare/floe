RSpec.describe Floe::Workflow::States::Task do
  let(:workflow) { Floe::Workflow.load(GEM_ROOT.join("examples/workflow.asl")) }
  let(:input)    { {} }

  describe "#run" do
    let(:mock_runner) { double("Floe::Workflow::Runner") }
    let(:input)       { {"foo" => {"bar" => "baz"}, "bar" => {"baz" => "foo"}} }
    let(:state)       { described_class.new(workflow, "Task", payload) }
    let(:subject)     { state.run!(input) }

    before { allow(Floe::Workflow::Runner).to receive(:for_resource).and_return(mock_runner) }

    describe "Input" do
      context "with no InputPath" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest"} }

        it "passes the whole context to the resource" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], {"foo" => {"bar" => "baz"}, "bar" => {"baz" => "foo"}}, nil)

          subject
        end
      end

      context "with an InputPath" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "InputPath" => "$.foo"} }

        it "filters the context passed to the resource" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], {"bar" => "baz"}, nil)

          subject
        end
      end

      context "with Parameters" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "Parameters" => {"var1.$" => "$.foo.bar"}} }

        it "passes the interpolated parameters to the resource" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], {"var1" => "baz"}, nil)

          subject
        end
      end
    end

    describe "Output" do
      context "ResultSelector" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "ResultSelector" => {"ip_addrs.$" => "$.response"}} }

        it "filters the results" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], {"foo" => {"bar" => "baz"}, "bar" => {"baz" => "foo"}}, nil)
            .and_return([0, "{\"response\":[\"192.168.1.2\"],\"exit_code\":0}"])

          _, results = subject

          expect(results).to eq("foo" => {"bar" => "baz"}, "bar" => {"baz" => "foo"}, "ip_addrs" => ["192.168.1.2"])
        end
      end

      context "ResultPath" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "ResultPath" => "$.ip_addrs"} }

        it "inserts the response into the input" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_return([0, "[\"192.168.1.2\"]"])

          _, results = subject

          expect(results).to eq(
            "foo"      => {"bar" => "baz"},
            "bar"      => {"baz" => "foo"},
            "ip_addrs" => ["192.168.1.2"]
          )
        end
      end

      context "OutputPath" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "ResultPath" => "$.data.ip_addrs", "OutputPath" => output_path} }

        context "with the default '$'" do
          let(:output_path) { "$" }

          it "returns the entire input as the output" do
            expect(mock_runner)
              .to receive(:run!)
              .with(payload["Resource"], input, nil)
              .and_return([0, "[\"192.168.1.2\"]"])

            _, results = subject

            expect(results).to eq(
              "foo"  => {"bar" => "baz"},
              "bar"  => {"baz" => "foo"},
              "data" => {"ip_addrs" => ["192.168.1.2"]}
            )
          end
        end

        context "with a path" do
          let(:output_path) { "$.data" }

          it "filters the output" do
            expect(mock_runner)
              .to receive(:run!)
              .with(payload["Resource"], input, nil)
              .and_return([0, "[\"192.168.1.2\"]"])

            _, results = subject

            expect(results).to eq("ip_addrs" => ["192.168.1.2"])
          end
        end
      end
    end

    describe "Retry" do
      let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "Retry" => retriers} }
      before { allow(Kernel).to receive(:sleep).and_return(0) }

      context "with specific errors" do
        let(:retriers) { [{"ErrorEquals" => ["States.Timeout"], "MaxAttempts" => 1}] }

        it "retries if that error is raised" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_raise(RuntimeError, "States.Timeout")

          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_return([0])

          _, results = subject

          expect(results).to eq("bar" => {"baz"=>"foo"}, "foo" => {"bar"=>"baz"})
        end

        context "with multiple retriers" do
          let(:retriers) { [{"ErrorEquals" => ["States.Timeout"], "MaxAttempts" => 1}, {"ErrorEquals" => ["Exception"]}] }

          it "resets the retrier if a different exception is raised" do
            expect(mock_runner)
              .to receive(:run!)
              .with(payload["Resource"], input, nil)
              .and_raise(RuntimeError, "States.Timeout")

            expect(mock_runner)
              .to receive(:run!)
              .with(payload["Resource"], input, nil)
              .and_raise(RuntimeError, "Exception")

            expect(mock_runner)
              .to receive(:run!)
              .with(payload["Resource"], input, nil)
              .and_return([0])
            _, results = subject

            expect(results).to eq("bar" => {"baz"=>"foo"}, "foo" => {"bar"=>"baz"})
          end
        end

        it "raises if the number of retries is greater than MaxAttempts" do
          expect(mock_runner)
            .to receive(:run!)
            .twice
            .with(payload["Resource"], input, nil)
            .and_raise(RuntimeError, "States.Timeout")

          expect { subject }.to raise_error(RuntimeError, "States.Timeout")
        end

        it "raises if the exception isn't caught" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_raise(RuntimeError, "Exception")

          expect { subject }.to raise_error(RuntimeError, "Exception")
        end
      end

      context "with a States.ALL retrier" do
        let(:retriers) { [{"ErrorEquals" => ["States.Timeout"]}, {"ErrorEquals" => ["States.ALL"]}] }

        it "retries if any error is raised" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_raise(RuntimeError, "ABORT!")

          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_return([0])
          _, results = subject

          expect(results).to eq("bar" => {"baz"=>"foo"}, "foo" => {"bar"=>"baz"})
        end
      end

      context "with a Catch" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "Retry" => [{"ErrorEquals" => ["States.Timeout"]}], "Catch" => [{"ErrorEquals" => ["States.ALL"], "Next" => "FailState"}]} }

        it "retry preceeds catch" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_raise(RuntimeError, "States.Timeout")

          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_return([0])

          _, results = subject

          expect(results).to eq("bar" => {"baz"=>"foo"}, "foo" => {"bar"=>"baz"})
        end

        it "invokes the Catch if no retriers match" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_raise(RuntimeError, "Exception")

          next_state, _ = subject

          expect(next_state).to eq("FailState")
        end
      end
    end

    describe "Catch" do
      context "with specific errors" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "Catch" => [{"ErrorEquals" => ["States.Timeout"], "Next" => "FirstState"}]} }

        it "catches the exception" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_raise(RuntimeError, "States.Timeout")

          next_state, _ = subject

          expect(next_state).to eq("FirstState")
        end

        it "raises if the exception isn't caught" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_raise(RuntimeError, "Exception")

          expect { subject }.to raise_error(RuntimeError, "Exception")
        end
      end

      context "with a State.ALL catcher" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "Catch" => [{"ErrorEquals" => ["States.Timeout"], "Next" => "FirstState"}, {"ErrorEquals" => ["States.ALL"], "Next" => "FailState"}]} }

        it "catches a more specific exception" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_raise(RuntimeError, "States.Timeout")

          next_state, _ = subject

          expect(next_state).to eq("FirstState")
        end

        it "catches the exception and transits to the next state" do
          expect(mock_runner)
            .to receive(:run!)
            .with(payload["Resource"], input, nil)
            .and_raise(RuntimeError, "Exception")

          next_state, _ = subject

          expect(next_state).to eq("FailState")
        end
      end
    end
  end

  describe "#terminal?" do
    it "with a non-end state" do
      state = workflow.states_by_name["FirstState"]
      expect(state.terminal?).to be false
    end

    it "with an end state" do
      state = workflow.states_by_name["NextState"]
      expect(state.terminal?).to be true
    end
  end
end
