RSpec.describe Floe::Workflow::ReferencePath do
  let(:subject) { described_class.new(payload) }

  describe "#initialize" do
    it "with invalid character raises an exception" do
      expect { described_class.new("$.foo@.bar") }
        .to raise_error(Floe::InvalidWorkflowError, "Invalid Reference Path")
    end

    it "inserting into Context raises an exception" do
      expect { described_class.new("$$.Execution.Id") }
        .to raise_error(Floe::InvalidWorkflowError, "Reference Path cannot start with $$")
    end

    it "with $$.Credentials" do
      expect { described_class.new("$$.Credentials.AuthToken") }.not_to raise_error
    end
  end

  describe "#get" do
    context "with a simple path" do
      let(:payload) { "$" }
      let(:input)   { {"hello" => "world"} }

      it "returns the input" do
        expect(subject.get(input)).to eq(input)
      end
    end

    context "with an array dereference" do
      let(:payload) { "$['store'][1]['book']" }
      let(:input)   { {"store" => [{"book" => "Advanced ASL"}, {"book" => "ASL For Dummies"}]} }

      it "returns the value from the array" do
        expect(subject.get(input)).to eq("ASL For Dummies")
      end

      context "with a missing value" do
        let(:input)   { {"store" => []} }

        it "returns nil" do
          expect(subject.get(input)).to be_nil
        end
      end
    end

    context "with a top-level array input" do
      let(:payload) { "$.[1].title" }
      let(:input)   { [{"title" => "Advanced ASL"}, {"title" => "ASL For Dummies"}] }

      it "returns the value from the array" do
        expect(subject.get(input)).to eq("ASL For Dummies")
      end
    end
  end

  describe "#set" do
    let(:payload) { "$" }
    let(:input) { {"old" => "key"} }

    context "with a simple path" do
      it "sets the output at the top-level" do
        expect(subject.set(input, "foo" => "bar")).to eq("foo" => "bar")
      end
    end

    context "with a top level path" do
      let(:payload) { "$.hash" }

      it "sets the output at the correct nested level" do
        expect(subject.set(input, "foo" => "bar")).to eq("old" => "key", "hash" => {"foo" => "bar"})
      end
    end

    context "with a nested path" do
      let(:payload) { "$.nested.hash" }

      it "sets the output at the correct nested level" do
        expect(subject.set(input, "foo" => "bar")).to eq("old" => "key", "nested" => {"hash" => {"foo" => "bar"}})
      end
    end

    context "with an array" do
      let(:input)   { {"master" => [{"foo" => "bar"}, {"bar" => "baz"}]} }
      let(:payload) { "$.master[1].bar" }

      it "sets the value in the array" do
        expect(subject.set(input, "hi")).to eq("master" => [{"foo" => "bar"}, {"bar" => "hi"}])
      end

      context "with an array index past the last value" do
        let(:payload) { "$.master[2].bar" }

        it "appends to the array" do
          expect(subject.set(input, "hi")).to eq("master" => [{"foo" => "bar"}, {"bar" => "baz"}, {"bar" => "hi"}])
        end
      end
    end

    context "with a top-level array" do
      let(:input)   { [{"book" => {"title" => "Advanced ASL"}}, {"book" => {"title" => "ASL for dummies"}}] }
      let(:payload) { "$.[1].book.title" }

      it "sets the value in the array" do
        expect(subject.set(input, "ASL for Dummies")).to eq([{"book" => {"title" => "Advanced ASL"}}, {"book" => {"title" => "ASL for Dummies"}}])
      end
    end

    context "with a non-empty input" do
      let(:input)   { {"master" => {"detail" => [1, 2, 3]}} }
      let(:payload) { "$.master.result.sum" }

      it "merges the result" do
        expect(subject.set(input, 6)).to eq("master" => {"detail" => [1, 2, 3], "result" => {"sum" => 6}})
      end
    end

    context "when the path cannot be applied to the input" do
      let(:payload) { "$.x" }

      [
        ["a string",  "foo"],
        ["a number",  5],
        ["a boolean", true],
        ["null",      nil],
        ["an array",  [1]]
      ].each do |description, value|
        context "with #{description} as the input" do
          let(:input) { value }

          it "raises States.ResultPathMatchFailure" do
            expect { subject.set(input, 6) }.to raise_error(Floe::ExecutionError, "Path [$.x] cannot be applied to the input") { |err| expect(err.floe_error).to eq("States.ResultPathMatchFailure") }
          end
        end
      end

      context "with an intermediate value that is not an object" do
        let(:payload) { "$.a.b" }

        [["a number", 5], ["a string", "s"], ["an array", [1]]].each do |description, value|
          context "with #{description}" do
            let(:input) { {"a" => value} }

            it "raises States.ResultPathMatchFailure" do
              expect { subject.set(input, 6) }.to raise_error(Floe::ExecutionError, "Path [$.a.b] cannot be applied to the input") { |err| expect(err.floe_error).to eq("States.ResultPathMatchFailure") }
            end
          end
        end
      end

      context "with an intermediate null value" do
        let(:payload) { "$.a.b" }
        let(:input)   { {"a" => nil} }

        it "creates the intermediate object" do
          expect(subject.set(input, 6)).to eq("a" => {"b" => 6})
        end
      end
    end
  end
end
