RSpec.describe Floe::Workflow::States::Task do
  let(:workflow) { Floe::Workflow.load(GEM_ROOT.join("examples/workflow.asl"), context) }
  let(:context)  { Floe::Workflow::Context.new(:input => input) }
  let(:input)    { {} }

  describe "#run" do
    let(:mock_runner) { double("Floe::Workflow::Runner") }
    let(:input)       { {"foo" => {"bar" => "baz"}, "bar" => {"baz" => "foo"}} }
    let(:state)       { described_class.new(workflow, "Task", payload) }
    let(:subject)     { state.run! }
    let(:success)     { true }
    let(:output)      { nil }

    before do
      context.state["Input"] = input
      allow(Floe::Workflow::Runner).to receive(:for_resource).and_return(mock_runner)
      allow(mock_runner).to receive(:status!).and_return({})
      allow(mock_runner).to receive(:running?).and_return(false)
      allow(mock_runner).to receive(:success?).and_return(success)
      allow(mock_runner).to receive(:output).and_return(output)
      allow(mock_runner).to receive(:cleanup)
    end

    describe "Input" do
      context "with no InputPath" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest"} }

        it "passes the whole context to the resource" do
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], {"foo" => {"bar" => "baz"}, "bar" => {"baz" => "foo"}}, nil)
            .and_return(:exit_code => 0, :output => "hello, world!")

          subject
        end
      end

      context "with an InputPath" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "InputPath" => "$.foo"} }

        it "filters the context passed to the resource" do
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], {"bar" => "baz"}, nil)
            .and_return(:exit_code => 0, :output => "hello, world!")

          subject
        end
      end

      context "with Parameters" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "Parameters" => {"var1.$" => "$.foo.bar"}} }

        it "passes the interpolated parameters to the resource" do
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], {"var1" => "baz"}, nil)
            .and_return(:exit_code => 0, :output => "hello, world!")

          subject
        end
      end
    end

    describe "Output" do
      context "ResultSelector" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "ResultSelector" => {"ip_addrs.$" => "$.response"}} }

        it "filters the results" do
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], {"foo" => {"bar" => "baz"}, "bar" => {"baz" => "foo"}}, nil)
          expect(mock_runner).to receive(:output).and_return("{\"response\":[\"192.168.1.2\"],\"exit_code\":0}")

          subject

          expect(context.output).to eq("foo" => {"bar" => "baz"}, "bar" => {"baz" => "foo"}, "ip_addrs" => ["192.168.1.2"])
        end
      end

      context "ResultPath" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "ResultPath" => "$.ip_addrs"} }

        it "inserts the response into the input" do
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], input, nil)
          expect(mock_runner).to receive(:output).and_return("[\"192.168.1.2\"]")

          subject

          expect(context.output).to eq(
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
              .to receive(:run_async!)
              .with(payload["Resource"], input, nil)
            expect(mock_runner).to receive(:output).and_return("[\"192.168.1.2\"]")

            subject

            expect(context.output).to eq(
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
              .to receive(:run_async!)
              .with(payload["Resource"], input, nil)
            expect(mock_runner).to receive(:output).and_return("[\"192.168.1.2\"]")

            subject

            expect(context.output).to eq("ip_addrs" => ["192.168.1.2"])
          end
        end
      end
    end

    describe "Retry" do
      let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "Retry" => retriers} }
      before { allow(Kernel).to receive(:sleep).and_return(0) }

      context "with specific errors" do
        let(:retriers) { [{"ErrorEquals" => ["States.Timeout"], "MaxAttempts" => 1}] }
        let(:success)  { false }
        let(:output)   { "States.Timeout" }

        it "retries if that error is raised" do
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], input, nil)

          subject

          expect(context.next_state).to          eq(context.state_name)
          expect(context.state["Retrier"]).to    eq(["States.Timeout"])
          expect(context.state["RetryCount"]).to eq(1)
        end

        context "with multiple retriers" do
          let(:retriers) { [{"ErrorEquals" => ["States.Timeout"], "MaxAttempts" => 1}, {"ErrorEquals" => ["Exception"]}] }

          it "resets the retrier if a different exception is raised" do
            expect(mock_runner).to receive(:running?).and_return(false)
            expect(mock_runner).to receive(:success?).and_return(false)
            expect(mock_runner).to receive(:output).once.and_return("States.Timeout")
            expect(mock_runner)
              .to receive(:run_async!)
              .twice
              .with(payload["Resource"], input, nil)

            state.run!(input)

            expect(context.next_state).to          eq(context.state_name)
            expect(context.state["Retrier"]).to    eq(["States.Timeout"])
            expect(context.state["RetryCount"]).to eq(1)

            expect(mock_runner).to receive(:output).once.and_return("Exception")

            state.run!(input)

            expect(context.next_state).to          eq(context.state_name)
            expect(context.state["Retrier"]).to    eq(["Exception"])
            expect(context.state["RetryCount"]).to eq(1)
          end
        end

        it "raises if the number of retries is greater than MaxAttempts" do
          expect(mock_runner)
            .to receive(:run_async!)
            .twice
            .with(payload["Resource"], input, nil)

          state.run!
          expect { state.run! }.to raise_error(RuntimeError, "States.Timeout")
        end

        it "raises if the exception isn't caught" do
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], input, nil)
          expect(mock_runner).to receive(:output).once.and_return("Exception")

          expect { subject }.to raise_error(RuntimeError, "Exception")
        end
      end

      context "with a States.ALL retrier" do
        let(:retriers) { [{"ErrorEquals" => ["States.Timeout"]}, {"ErrorEquals" => ["States.ALL"]}] }

        it "retries if any error is raised" do
          expect(mock_runner)
            .to receive(:run_async!)
            .twice
            .with(payload["Resource"], input, nil)
          expect(mock_runner).to receive(:output).once.and_return("ABORT!")
          expect(mock_runner).to receive(:output).once.and_return(output)

          state.run!
          state.run!

          expect(context.output).to eq("bar" => {"baz"=>"foo"}, "foo" => {"bar"=>"baz"})
        end
      end

      context "with a Catch" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "Retry" => [{"ErrorEquals" => ["States.Timeout"]}], "Catch" => [{"ErrorEquals" => ["States.ALL"], "Next" => "FailState"}]} }
        let(:success) { false }

        it "retry preceeds catch" do
          expect(mock_runner).to receive(:output).once.and_return("States.Timeout")
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], input, nil)

          subject

          expect(context.next_state).to                  eq(context.state_name)
          expect(context.state["Retrier"]).to    eq(["States.Timeout"])
          expect(context.state["RetryCount"]).to eq(1)
        end

        it "invokes the Catch if no retriers match" do
          expect(mock_runner).to receive(:output).once.and_return("Exception")
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], input, nil)

          subject

          expect(context.next_state).to eq("FailState")
        end
      end
    end

    describe "Catch" do
      let(:success) { false }

      context "with specific errors" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "Catch" => [{"ErrorEquals" => ["States.Timeout"], "Next" => "FirstState"}]} }

        it "catches the exception" do
          expect(mock_runner).to receive(:output).and_return("States.Timeout")
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], input, nil)

          subject

          expect(context.next_state).to eq("FirstState")
        end

        it "raises if the exception isn't caught" do
          expect(mock_runner).to receive(:output).and_return("Exception")
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], input, nil)

          expect { subject }.to raise_error(RuntimeError, "Exception")
        end
      end

      context "with a State.ALL catcher" do
        let(:payload) { {"Type" => "Task", "Resource" => "docker://hello-world:latest", "Catch" => [{"ErrorEquals" => ["States.Timeout"], "Next" => "FirstState"}, {"ErrorEquals" => ["States.ALL"], "Next" => "FailState"}]} }

        it "catches a more specific exception" do
          expect(mock_runner).to receive(:output).and_return("States.Timeout")
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], input, nil)

          subject

          expect(context.next_state).to eq("FirstState")
        end

        it "catches the exception and transits to the next state" do
          expect(mock_runner).to receive(:output).and_return("Exception")
          expect(mock_runner)
            .to receive(:run_async!)
            .with(payload["Resource"], input, nil)

          subject

          expect(context.next_state).to eq("FailState")
        end
      end
    end
  end

  describe "#end?" do
    it "with a normal state" do
      state = workflow.states_by_name["FirstState"]
      expect(state.end?).to be false
    end

    it "with an end state" do
      state = workflow.states_by_name["NextState"]
      expect(state.end?).to be true
    end
  end
end
