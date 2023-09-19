RSpec.describe Floe::Workflow::States::Succeed do
  let(:context)  { Floe::Workflow::Context.new(input: input) }
  let(:workflow) { Floe::Workflow.load(GEM_ROOT.join("examples/workflow.asl"), context) }
  let(:state)    { workflow.states_by_name["SuccessState"] }
  let(:input)    { {} }

  it "#end?" do
    expect(state.end?).to be true
  end

  describe "#run!" do
    it "has no next" do
      state.run!()
      expect(context.next_state).to eq(nil)
    end
  end
end
