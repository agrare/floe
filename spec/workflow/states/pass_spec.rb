RSpec.describe Floe::Workflow::States::Pass do
  let(:context)  { Floe::Workflow::Context.new(input: input) }
  let(:workflow) { Floe::Workflow.load(GEM_ROOT.join("examples/workflow.asl"), context) }
  let(:state)    { workflow.states_by_name["PassState"] }
  let(:input)    { {} }

  describe "#end?" do
    it "is non-terminal" do
      expect(state.end?).to eq(false)
    end
    # TODO: test @end
  end

  describe "#run!" do
    it "sets the result to the result path" do
      state.run!(context.input)
      expect(context.output["result"]).to include(state.result)
      expect(context.next_state).to eq("WaitState")
    end
  end
end
