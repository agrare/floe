RSpec.describe Floe::Workflow::States::Pass do
  let(:workflow) { Floe::Workflow.load(GEM_ROOT.join("examples/workflow.asl")) }
  let(:state)    { workflow.states_by_name["WaitState"] }

  describe "#run!" do
    it "sleeps for the requested amount of time" do
      expect(state).to receive(:sleep).with(state.seconds)

      state.run!({})
    end
  end
end