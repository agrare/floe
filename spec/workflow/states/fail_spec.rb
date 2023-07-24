RSpec.describe Floe::Workflow::States::Fail do
  let(:workflow) { Floe::Workflow.load(GEM_ROOT.join("examples/workflow.asl")) }
  let(:state)    { workflow.states_by_name["FailState"] }

  it "#terminal?" do
    expect(state.terminal?).to be true
  end
end
