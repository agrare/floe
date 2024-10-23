shared_examples_for "WorkflowBase" do
  it "raises an exception for missing States field" do
    payload = {"StartAt" => "Missing"}
    expect { described_class.new(payload, ["Map"]) }
      .to raise_error(Floe::InvalidWorkflowError, "Map does not have required field \"States\"")
  end

  it "raises an exception for missing StartAt field" do
    payload = {"States" => {"First" => {"Type" => "Succeed"}}}
    expect { described_class.new(payload, ["Map"]) }
      .to raise_error(Floe::InvalidWorkflowError, "Map does not have required field \"StartAt\"")
  end

  it "raises an exception if StartAt isn't in States" do
    payload = {"StartAt" => "First", "States" => {"Second" => {"Type" => "Succeed"}}}
    expect { described_class.new(payload, ["Map"]) }
      .to raise_error(Floe::InvalidWorkflowError, "Map field \"StartAt\" value \"First\" is not found in \"States\"")
  end

  it "raises an exception if a Next state isn't in States" do
    payload = {"StartAt" => "First", "States" => {"First" => {"Type" => "Pass", "Next" => "Last"}}}
    expect { described_class.new(payload, ["Map"]) }
      .to raise_error(Floe::InvalidWorkflowError, "States.First field \"Next\" value \"Last\" is not found in \"States\"")
  end
end
