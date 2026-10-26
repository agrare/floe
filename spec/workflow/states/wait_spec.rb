RSpec.describe Floe::Workflow::States::Pass do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "Seconds" => 10, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }

  describe "#end?" do
    it "is non-terminal" do
      expect(state.end?).to eq(false)
    end
  end

  describe "#start" do
    it "sets WaitUntil" do
      state.start(ctx)

      expect(state.waiting?(ctx)).to be_truthy
    end
  end

  describe "#finish" do
    it "transitions to the next state" do
      state.start(ctx)
      state.finish(ctx)

      expect(ctx.next_state).to eq("SuccessState")
    end
  end

  shared_examples_for "Wait10Seconds" do
    context "includes Waiting" do
      it "is running before finished" do
        state.start(ctx)
        expect(state.running?(ctx)).to be_truthy
      end

      it "is not running after finished" do
        Timecop.travel(Time.now.utc - 10) do
          state.start(ctx)
        end
        expect(state.running?(ctx)).to be_falsey
      end

      it "run_nonblock marks workflow finished only after time has expired" do
        workflow.run_nonblock
        expect(workflow.end?).to eq(false)
        expect(workflow.context.state_history.size).to eq(0)

        Timecop.travel(Time.now.utc + 100) do
          workflow.run_nonblock
        end

        expect(workflow.end?).to eq(true)
        expect(workflow.context.state_history.size).to eq(2)
      end
    end
  end

  describe "#running?" do
    context "with seconds" do
      let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "Seconds" => 10, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }

      include_examples "Wait10Seconds"
    end

    context "with secondsPath" do
      let(:input)    { {"expire" => "10"} }
      let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "SecondsPath" => "$.expire", "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }

      include_examples "Wait10Seconds"
    end

    context "with Timestamp" do
      let(:expiry) { Time.now.utc + 10 }
      let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "Timestamp" => expiry.iso8601, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }

      include_examples "Wait10Seconds"
    end

    context "with TimestampPath" do
      let(:expiry) { Time.now.utc + 10 }
      let(:input) { {"expire" => expiry.iso8601} }
      let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "TimestampPath" => "$.expire", "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }

      include_examples "Wait10Seconds"
    end
  end
end

RSpec.describe Floe::Workflow::States::Wait, "with QueryLanguage JSONata" do
  let(:input)    { {"foo" => "bar", "secs" => 10} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:workflow) { make_workflow(ctx, payload) }
  let(:state)    { {"Type" => "Wait", "QueryLanguage" => "JSONata", "Seconds" => 10, "Next" => "SuccessState"} }
  let(:payload)  { {"WaitState" => state, "SuccessState" => {"Type" => "Succeed"}} }

  describe "#initialize" do
    %w[InputPath OutputPath SecondsPath TimestampPath].each do |field|
      context "with #{field}" do
        let(:state) { {"Type" => "Wait", "QueryLanguage" => "JSONata", "Next" => "SuccessState", field => "$.foo"} }

        it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.WaitState field \"#{field}\" is not allowed when QueryLanguage is \"JSONata\"") }
      end
    end

    context "with Output in a JSONPath state" do
      let(:state) { {"Type" => "Wait", "Seconds" => 1, "Next" => "SuccessState", "Output" => {}} }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.WaitState field \"Output\" is not allowed when QueryLanguage is \"JSONPath\"") }
    end
  end

  describe "#start" do
    it "waits for static Seconds" do
      workflow.start_workflow.current_state.start(ctx)

      expect(Time.parse(ctx.state["WaitUntil"])).to be_within(2).of(Time.now + 10)
    end

    context "with a Seconds expression" do
      let(:state) { {"Type" => "Wait", "QueryLanguage" => "JSONata", "Seconds" => "{% $states.input.secs * 2 %}", "Next" => "SuccessState"} }

      it "waits for the evaluated seconds" do
        workflow.start_workflow.current_state.start(ctx)

        expect(Time.parse(ctx.state["WaitUntil"])).to be_within(2).of(Time.now + 20)
      end
    end

    context "with a Seconds expression that is not a number" do
      let(:state) { {"Type" => "Wait", "QueryLanguage" => "JSONata", "Seconds" => "{% $states.input.foo %}", "Next" => "SuccessState"} }

      it "fails the workflow" do
        workflow.run_nonblock

        expect(ctx.status).to eq("failure")
        expect(ctx.output["Error"]).to eq("States.Runtime")
      end
    end

    context "with a Timestamp expression" do
      let(:expiry) { (Time.now.utc + 30).iso8601 }
      let(:input)  { {"when" => expiry} }
      let(:state)  { {"Type" => "Wait", "QueryLanguage" => "JSONata", "Timestamp" => "{% $states.input.when %}", "Next" => "SuccessState"} }

      it "waits until the evaluated timestamp" do
        workflow.start_workflow.current_state.start(ctx)

        expect(ctx.state["WaitUntil"]).to eq(expiry)
      end
    end
  end

  describe "#finish" do
    it "defaults the output to the input" do
      workflow.run_nonblock
      Timecop.travel(Time.now.utc + 100) { workflow.run_nonblock }

      expect(ctx.output).to eq(input)
      expect(ctx.status).to eq("success")
    end

    context "with Output and Assign" do
      let(:state) do
        {
          "Type"          => "Wait",
          "QueryLanguage" => "JSONata",
          "Seconds"       => 1,
          "Next"          => "SuccessState",
          "Output"        => {"foo" => "{% $states.input.foo %}"},
          "Assign"        => {"saved" => "{% $states.input.secs %}"}
        }
      end

      it "evaluates them when the wait is complete" do
        workflow.run_nonblock
        Timecop.travel(Time.now.utc + 100) { workflow.run_nonblock }

        expect(ctx.state_history.first["Output"]).to eq("foo" => "bar")
        expect(ctx.variables).to eq("saved" => 10)
      end
    end
  end
end
