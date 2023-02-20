RSpec.describe ManageIQ::Floe::Workflow::Path do
  describe "#value" do
    context "referencing the global context" do
      it "with a missing value" do
        expect(described_class.new("$$.foo").value({})).to be_nil
      end

      it "with a single value" do
        expect(described_class.new("$$.foo").value({"foo" => "bar"})).to eq("bar")
      end

      it "with a nested hash" do
        expect(described_class.new("$$.foo.bar").value({"foo" => {"bar" => "baz"}})).to eq("baz")
      end

      it "with an array" do
        expect(described_class.new("$$.foo[0].bar").value({"foo" => [{"bar" => "baz"}, {"bar" => "foo"}]})).to eq("baz")
      end

      it "returning multiple values" do
        expect(described_class.new("$$.foo[*].bar").value({"foo" => [{"bar" => "baz"}, {"bar" => "foo"}]})).to eq(["baz", "foo"])
      end
    end

    context "referencing the inputs" do
      it "with a missing value" do
        expect(described_class.new("$.foo").value({"foo" => "bar"})).to be_nil
      end

      it "with a single value" do
        expect(described_class.new("$.foo").value({}, {"foo" => "bar"})).to eq("bar")
      end

      it "with a nested hash" do
        expect(described_class.new("$.foo.bar").value({}, {"foo" => {"bar" => "baz"}})).to eq("baz")
      end

      it "with an array" do
        expect(described_class.new("$.foo[0].bar").value({}, {"foo" => [{"bar" => "baz"}]})).to eq("baz")
      end
    end
  end
end
