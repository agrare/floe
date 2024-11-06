RSpec.describe Floe::Workflow::ItemBatcher do
  let(:subject) { described_class.new(payload, ["Map", "ItemBatcher"]) }

  describe "#initialize" do
    context "with no MaxItems or MaxInputBytes" do
      let(:payload) { {} }

      it "raises an exception" do
        expect { subject }
          .to raise_error(
            Floe::InvalidWorkflowError,
            "Map.ItemBatcher must have one of \"MaxItemsPerBatch\", \"MaxItemsPerBatchPath\", \"MaxInputBytesPerBatch\", \"MaxInputBytesPerBatchPath\""
          )
      end
    end

    context "with a BatchInput field" do
      let(:payload) { {"BatchInput" => "foo", "MaxItemsPerBatch" => 10} }

      it "returns an ItemBatcher" do
        expect(subject).to be_kind_of(described_class)
      end

      it "sets the BatchInput to a PayloadTemplate" do
        expect(subject.batch_input).to be_kind_of(Floe::Workflow::PayloadTemplate)
      end
    end

    context "with MaxItemsPerBatch" do
      let(:payload) { {"MaxItemsPerBatch" => 10} }

      it "returns an ItemBatcher" do
        expect(subject).to be_kind_of(described_class)
      end

      it "sets max_items_per_batch" do
        expect(subject.max_items_per_batch).to eq(payload["MaxItemsPerBatch"])
      end

      context "that is an invalid value" do
        let(:payload) { {"MaxItemsPerBatch" => 0} }

        it "raises an exception" do
          expect { subject }.to raise_error(Floe::InvalidWorkflowError, "Map.ItemBatcher field \"MaxItemsPerBatch\" value \"0\" must be a positive integer")
        end
      end
    end

    context "with MaxInputBytesPerBatch" do
      let(:payload) { {"MaxInputBytesPerBatch" => 1_024} }

      it "returns an ItemBatcher" do
        expect(subject).to be_kind_of(described_class)
      end

      it "sets max_input_bytes_per_batch" do
        expect(subject.max_input_bytes_per_batch).to eq(payload["MaxInputBytesPerBatch"])
      end

      context "that is an invalid value" do
        let(:payload) { {"MaxInputBytesPerBatch" => 0} }

        it "raises an exception" do
          expect { subject }.to raise_error(Floe::InvalidWorkflowError, "Map.ItemBatcher field \"MaxInputBytesPerBatch\" value \"0\" must be a positive integer")
        end
      end
    end

    context "with MaxItemsPerBatchPath" do
      let(:payload) { {"MaxItemsPerBatchPath" => "$.maxBatchItems"} }

      it "returns an ItemBatcher" do
        expect(subject).to be_kind_of(described_class)
      end

      it "sets max_items_per_batch_path" do
        expect(subject.max_items_per_batch_path).to be_kind_of(Floe::Workflow::ReferencePath)
        expect(subject.max_items_per_batch_path).to have_attributes(:path => ["maxBatchItems"])
      end
    end

    context "with MaxInputBytesPerBatchPath" do
      let(:payload) { {"MaxInputBytesPerBatchPath" => "$.batchSize"} }

      it "returns an ItemBatcher" do
        expect(subject).to be_kind_of(described_class)
      end

      it "sets max_input_bytes_per_batch_path" do
        expect(subject.max_input_bytes_per_batch_path).to be_kind_of(Floe::Workflow::ReferencePath)
        expect(subject.max_input_bytes_per_batch_path).to have_attributes(:path => ["batchSize"])
      end
    end

    context "with MaxItemsPerBatch and MaxItemsPerBatchPath" do
      let(:payload) { {"MaxItemsPerBatch" => 10, "MaxItemsPerBatchPath" => "$.maxBatchItems"} }

      it "raises an exception" do
        expect { subject }.to raise_error(Floe::InvalidWorkflowError, "Map.ItemBatcher must not specify both \"MaxItemsPerBatch\" and \"MaxItemsPerBatchPath\"")
      end
    end

    context "with MaxInputBytesPerBatch and MaxInputBytesPerBatchPath" do
      let(:payload) { {"MaxInputBytesPerBatch" => 1_024, "MaxInputBytesPerBatchPath" => "$.batchSize"} }

      it "raises an exception" do
        expect { subject }.to raise_error(Floe::InvalidWorkflowError, "Map.ItemBatcher must not specify both \"MaxInputBytesPerBatch\" and \"MaxInputBytesPerBatchPath\"")
      end
    end
  end

  describe "#value" do
    let(:context) { {} }
    let(:input)   { %w[a b c d e] }

    context "with MaxItemsPerBatch" do
      let(:payload) { {"MaxItemsPerBatch" => 2} }

      it "returns in batches of 2" do
        expect(subject.value(context, input)).to eq([{"Items" => %w[a b]}, {"Items" => %w[c d]}, {"Items" => %w[e]}])
      end
    end

    context "with MaxItemsPerBatchPath" do
      let(:payload)     { {"MaxItemsPerBatchPath" => "$.batchSize"} }
      let(:state_input) { {"batchSize" => 2, "items" => input} }

      it "returns in batches of 2" do
        expect(subject.value(context, input, state_input)).to eq([{"Items" => %w[a b]}, {"Items" => %w[c d]}, {"Items" => %w[e]}])
      end

      context "with an invalid value in input" do
        let(:state_input) { {"batchSize" => 0, "items" => input} }

        it "raises an exception" do
          expect { subject.value(context, input, state_input) }
            .to raise_error(Floe::ExecutionError, "Map.ItemBatcher field \"MaxItemsPerBatchPath\" value \"0\" must be a positive integer")
        end
      end
    end

    context "with BatchInput" do
      let(:payload)     { {"BatchInput" => {"foo.$" => "$.bar"}, "MaxItemsPerBatch" => 2} }
      let(:state_input) { {"bar" => "bar", "items" => input} }

      it "merges BatchInput with payloads" do
        expect(subject.value(context, input, state_input)).to eq([{"foo" => "bar", "Items" => %w[a b]}, {"foo" => "bar", "Items" => %w[c d]}, {"foo" => "bar", "Items" => %w[e]}])
      end
    end
  end
end
