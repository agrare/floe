RSpec.describe Floe::Workflow::ItemReader do
  let(:subject) { described_class.new(payload, ["Map", "ItemReader"]) }

  describe "#initialize" do
    let(:payload) { {"Resource" => "docker://item_reader:latest"} }

    it "returns an ItemReader instance" do
      expect(subject).to be_kind_of(described_class)
    end

    context "Missing a \"Resource\" field" do
      let(:payload) { {} }

      it "raises an exception" do
        expect { subject }.to raise_error(Floe::InvalidWorkflowError, "Map.ItemReader does not have required field \"Resource\"")
      end
    end

    context "with an invalid ReaderConfig" do
      let(:payload) { {"Resource" => "docker://item_reader:latest", "ReaderConfig" => {"MaxItems" => -1}} }

      it "raises an exception" do
        expect { subject }.to raise_error(Floe::InvalidWorkflowError, "Map.ItemReader field \"ReaderConfig.MaxItems\" value \"-1\" must be positive")
      end
    end
  end
end
