RSpec.describe Floe::Workflow::State do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  # picked a state that doesn't instantly finish
  let(:workflow) { make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "Seconds" => 1, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}}) }

  describe "#started?" do
    it "is not started yet" do
      expect(ctx.state_started?).to eq(false)
    end

    it "is started" do
      state.start(ctx)
      expect(ctx.state_started?).to eq(true)
    end

    it "is finished" do
      state.start(ctx)
      state.finish(ctx)

      expect(ctx.state_started?).to eq(true)
    end
  end

  describe "#finished?" do
    it "is not started yet" do
      expect(ctx.state_finished?).to eq(false)
    end

    it "is started" do
      state.start(ctx)
      expect(ctx.state_finished?).to eq(false)
    end

    it "is finished" do
      state.start(ctx)
      state.finish(ctx)

      expect(ctx.state_finished?).to eq(true)
    end
  end
end
