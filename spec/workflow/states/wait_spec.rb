RSpec.describe Floe::Workflow::States::Pass do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "Seconds" => 1, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }

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

  describe "#running?" do
    context "with seconds" do
      let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "Seconds" => 1, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }
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
    end

    context "with secondsPath" do
      let(:input)    { {"expire" => "1"} }
      let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "SecondsPath" => "$.expire", "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }
      it "is running? before finished" do
        state.start(ctx)
        expect(state.running?(ctx)).to be_truthy
      end

      it "is not running after finished" do
        Timecop.travel(Time.now.utc - 10) do
          state.start(ctx)
        end
        expect(state.running?(ctx)).to be_falsey
      end
    end

    context "with timestamp" do
      let(:expiry) { Time.now.utc + 1 }
      let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "Timestamp" => expiry.iso8601, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }
      it "is running? before finished" do
        state.start(ctx)
        expect(state.running?(ctx)).to be_truthy
      end

      it "is not running after finished" do
        Timecop.travel(Time.now.utc - 10) do
          state.start(ctx)
        end
        expect(state.running?(ctx)).to be_falsey
      end
    end

    context "with timestamp" do
      let(:expiry) { Time.now.utc + 1 }
      let(:input) { {"expire" => expiry.iso8601} }
      let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "TimestampPath" => "$.expire", "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }
      it "is running? before finished" do
        state.start(ctx)
        expect(state.running?(ctx)).to be_truthy
      end

      it "is not running after finished" do
        Timecop.travel(Time.now.utc - 10) do
          state.start(ctx)
        end
        expect(state.running?(ctx)).to be_falsey
      end

      it "runs" do
        workflow.run_nonblock
        expect(workflow.end?).to eq(false)
        expect(workflow.context.state_history.size).to eq(0)

        Timecop.travel(Time.now.utc + 10) do
          workflow.run_nonblock
        end

        expect(workflow.end?).to eq(true)
        expect(workflow.context.state_history.size).to eq(2)
      end
    end
  end
end
