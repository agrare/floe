RSpec.describe Floe::Workflow::States::Fail do
  let(:context)  { Floe::Workflow::Context.new(input: {}) }
  let(:workflow) { Floe::Workflow.load(GEM_ROOT.join("examples/workflow.asl")) }
  let(:state)    { workflow.states_by_name["FailState"] }

  it "#end?" do
    expect(state.end?).to be true
  end

  it "#run!" do
    state.run!()
    expect(context.next_state).to eq(nil)
  end
end
