RSpec.describe Floe::Workflow::ChoiceRule do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  let(:workflow) { make_workflow(ctx, payload) }
  let(:choices)  { [{"Variable" => "$.foo", "StringEquals" => "foo", "Next" => "FirstMatchState"}] }
  let(:payload) do
    {
      "Choice1"         => {"Type" => "Choice", "Choices" => choices, "Default" => "Default"},
      "Default"         => {"Type" => "Succeed"},
      "FirstMatchState" => {"Type" => "Succeed"}
    }
  end

  describe "#initialize" do
    it "works with valid next" do
      workflow
    end

    context "with unknown Next" do
      let(:choices) { [{"Variable" => "$.foo", "StringEquals" => "bar", "Next" => "Missing"}] }
      it { expect { workflow }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.Data field \"Next\" value \"Missing\" is not found in \"States\"") }
    end

    context "with Variable missing" do
      let(:choices) { [{"StringEquals" => "bar", "Next" => "FirstMatchState"}] }

      it { expect { workflow }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.Data does not have required field \"Variable\"") }
    end

    context "with non-path Variable" do
      let(:choices) { [{"Variable" => "wrong", "Next" => "FirstMatchState"}] }
      it { expect { workflow }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.Data field \"Variable\" value \"wrong\" Path [wrong] must start with \"$\"") }
    end

    context "with non-path Compare Key" do
      let(:choices) { [{"Variable" => "$.foo", "StringEqualsPath" => "wrong", "Next" => "FirstMatchState"}] }
      it { expect { workflow }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.Data field \"StringEqualsPath\" value \"wrong\" Path [wrong] must start with \"$\"") }
    end

    context "with invalid Compare Key" do
      let(:choices) { [{"Variable" => "$.foo", "IntegerMatchPath" => "$.foo", "Next" => "FirstMatchState"}] }
      it { expect { workflow }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.Data requires a compare key") }
    end

    context "with second level Next (Not)" do
      let(:choices) { [{"Not" => {"Variable" => "$.foo", "StringEquals" => "bar", "Next" => "FirstMatchState"}, "Next" => "FirstMatchState"}] }

      it { expect { workflow }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.Not.0.Data field \"Next\" value \"FirstMatchState\" not allowed in a child rule") }
    end

    context "with second level Next (And)" do
      let(:choices) { [{"And" => [{"Variable" => "$.foo", "StringEquals" => "bar", "Next" => "FirstMatchState"}], "Next" => "FirstMatchState"}] }

      it { expect { workflow }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.And.0.Data field \"Next\" value \"FirstMatchState\" not allowed in a child rule") }
    end
  end

  describe "#true?" do
    let(:choice)  { workflow.states.first.choices.first }
    let(:subject) { choice.true?(context, input) }
    let(:context) { {} }

    context "with abstract top level class" do
      let(:input) { {} }
      let(:subject) { described_class.new(workflow, ["Choice1", "Choices", 1, "Data"], choices.first).true?(context, input) }

      it "is not implemented" do
        expect { subject }.to raise_exception(NotImplementedError)
      end
    end

    context "Boolean Expression" do
      context "Not" do
        let(:choices) { [{"Not" => {"Variable" => "$.foo", "StringEquals" => "bar"}, "Next" => "FirstMatchState"}] }

        context "that is not equal to 'bar'" do
          let(:input) { {"foo" => "foo"} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that is equal to 'bar'" do
          let(:input) { {"foo" => "bar"} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "And" do
        let(:input) { {"foo" => "foo", "bar" => "bar"} }

        context "with all sub-choices being true" do
          let(:choices) { [{"And" => [{"Variable" => "$.foo", "StringEquals" => "foo"}, {"Variable" => "$.bar", "StringEquals" => "bar"}], "Next" => "FirstMatchState"}] }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "with one sub-choice false" do
          let(:choices) { [{"And" => [{"Variable" => "$.foo", "StringEquals" => "foo"}, {"Variable" => "$.bar", "StringEquals" => "foo"}], "Next" => "FirstMatchState"}] }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "Or" do
        let(:input) { {"foo" => "foo", "bar" => "bar"} }

        context "with one sub-choice being true" do
          let(:choices) { [{"Or" => [{"Variable" => "$.foo", "StringEquals" => "foo"}, {"Variable" => "$.bar", "StringEquals" => "foo"}], "Next" => "FirstMatchState"}] }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "with no sub-choices being true" do
          let(:choices) { [{"Or" => [{"Variable" => "$.foo", "StringEquals" => "bar"}, {"Variable" => "$.bar", "StringEquals" => "foo"}], "Next" => "FirstMatchState"}] }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end
    end

    context "Data-Test Expression" do
      context "with a missing variable" do
        let(:choices) { [{"Variable" => "$.foo", "NumericEquals" => 1, "Next" => "FirstMatchState"}] }
        let(:input) { {} }

        it "raises an exception" do
          expect { subject }.to raise_exception(Floe::PathError, "Path [$.foo] references an invalid value")
        end
      end

      context "with a missing compare key" do
        let(:choices) { [{"Variable" => "$.foo", "Next" => "FirstMatchState"}] }
        let(:input) { {"foo" => "bar"} }

        it "raises an exception" do
          expect { subject }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.Data requires a compare key")
        end
      end

      context "with an invalid compare key" do
        let(:choices) { [{"Variable" => "$.foo", "StringBeGone" => "$.bar", "Next" => "FirstMatchState"}] }
        let(:input)   { {"foo" => 0, "bar" => 1} }

        it "fails" do
          expect { subject }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.Data requires a compare key")
        end
      end

      context "with an invalid predicate" do
        let(:choices) { [{"Variable" => "$.foo", "IsNull" => 5, "Next" => "FirstMatchState"}] }
        it "fails" do
          expect { subject }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.Data field \"IsNull\" value \"5\" required to be a Boolean")
        end
      end

      context "with IsNull" do
        let(:predicate) { true }
        let(:choices) { [{"Variable" => "$.foo", "IsNull" => predicate, "Next" => "FirstMatchState"}] }

        context "with null" do
          let(:input) { {"foo" => nil} }
          it { expect(subject).to eq(true) }
        end

        context "with non-null" do
          let(:input) { {"foo" => "bar"} }
          it { expect(subject).to eq(false) }
        end

        context "with null (false)" do
          let(:predicate) { false }
          let(:input) { {"foo" => nil} }
          it { expect(subject).to eq(false) }
        end

        context "with non-null" do
          let(:predicate) { false }
          let(:input) { {"foo" => "bar"} }
          it { expect(subject).to eq(true) }
        end
      end

      context "with IsPresent" do
        let(:predicate) { true }
        let(:choices) { [{"Variable" => "$.foo", "IsPresent" => predicate, "Next" => "FirstMatchState"}] }

        context "with null" do
          let(:input) { {"foo" => nil} }
          it { expect(subject).to eq(true) }
        end

        context "with false" do
          let(:input) { {"foo" => "bar"} }
          it { expect(subject).to eq(true) }
        end

        context "with string" do
          let(:input) { {"foo" => false} }
          it { expect(subject).to eq(true) }
        end

        context "with missing value" do
          let(:input) { {} }
          it { expect(subject).to eq(false) }
        end

        context "with null" do
          let(:predicate) { false }
          let(:input) { {"foo" => nil} }
          it { expect(subject).to eq(false) }
        end

        context "with false" do
          let(:predicate) { false }
          let(:input) { {"foo" => "bar"} }
          it { expect(subject).to eq(false) }
        end

        context "with string" do
          let(:predicate) { false }
          let(:input) { {"foo" => false} }
          it { expect(subject).to eq(false) }
        end

        context "with missing value" do
          let(:predicate) { false }
          let(:input) { {} }
          it { expect(subject).to eq(true) }
        end
      end

      context "with IsNumeric" do
        let(:predicate) { true }
        let(:choices) { [{"Variable" => "$.foo", "IsNumeric" => predicate, "Next" => "FirstMatchState"}] }

        context "with an integer" do
          let(:input) { {"foo" => 1} }
          it { expect(subject).to eq(true) }
        end

        context "with a float" do
          let(:input) { {"foo" => 1.5} }
          it { expect(subject).to eq(true) }
        end

        context "with a string" do
          let(:input) { {"foo" => "bar"} }
          it { expect(subject).to eq(false) }
        end

        context "with an integer (negative)" do
          let(:input) { {"foo" => 1} }
          let(:predicate) { false }
          it { expect(subject).to eq(false) }
        end

        context "with a float (negative)" do
          let(:input) { {"foo" => 1.5} }
          let(:predicate) { false }
          it { expect(subject).to eq(false) }
        end

        context "with a string (negative)" do
          let(:input) { {"foo" => "bar"} }
          let(:predicate) { false }
          it { expect(subject).to eq(true) }
        end
      end

      context "with IsString" do
        let(:choices) { [{"Variable" => "$.foo", "IsString" => true, "Next" => "FirstMatchState"}] }

        context "with a string" do
          let(:input) { {"foo" => "bar"} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "with a number" do
          let(:input) { {"foo" => 1} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with IsBoolean" do
        let(:choices) { [{"Variable" => "$.foo", "IsBoolean" => true, "Next" => "FirstMatchState"}] }

        context "with a boolean" do
          let(:input) { {"foo" => true} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "with a number" do
          let(:input) { {"foo" => 1} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with IsTimestamp" do
        let(:choices) { [{"Variable" => "$.foo", "IsTimestamp" => true, "Next" => "FirstMatchState"}] }

        context "with a timestamp" do
          let(:input) { {"foo" => "2016-03-14T01:59:00Z"} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "with a number" do
          let(:input) { {"foo" => 1} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end

        context "with a string that isn't a date" do
          let(:input) { {"foo" => "bar"} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end

        context "with a date that isn't in rfc3339 format" do
          let(:input) { {"foo" => "2023-01-21 16:30:32 UTC"} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with a NumericEquals" do
        let(:choices) { [{"Variable" => "$.foo", "NumericEquals" => 1, "Next" => "FirstMatchState"}] }

        context "that equals the variable" do
          let(:input) { {"foo" => 1} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that does not equal the variable" do
          let(:input) { {"foo" => 2} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with a NumericEqualsPath" do
        let(:choices) { [{"Variable" => "$.foo", "NumericEqualsPath" => "$.bar", "Next" => "FirstMatchState"}] }

        context "that equals the variable" do
          let(:input) { {"foo" => 1, "bar" => 1} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that does not equal the variable" do
          let(:input) { {"foo" => 2, "bar" => 1} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end

        context "with wrong match type on the left" do
          let(:input) { {"foo" => "abc", "bar" => 2} }
          it { expect { subject }.to raise_exception(Floe::ExecutionError, "States.Choice1.Choices.0.Data field \"Variable\" value \"$.foo\" required to point to a Numeric") }
        end

        context "with wrong match type on the right" do
          let(:input) { {"foo" => 2, "bar" => "xyz"} }
          it { expect { subject }.to raise_exception(Floe::ExecutionError, "States.Choice1.Choices.0.Data field \"NumericEqualsPath\" value \"$.bar\" required to point to a Numeric") }
        end

        context "with path not found" do
          let(:input) { {"foo" => 2} }
          it { expect { subject }.to raise_error(Floe::PathError, "Path [$.bar] references an invalid value") }
        end
      end

      context "with a NumericLessThan" do
        let(:choices) { [{"Variable" => "$.foo", "NumericLessThan" => 1, "Next" => "FirstMatchState"}] }

        context "that is true" do
          let(:input) { {"foo" => 0} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that is false" do
          let(:input) { {"foo" => 1} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with a NumericLessThanPath" do
        let(:choices) { [{"Variable" => "$.foo", "NumericLessThanPath" => "$.bar", "Next" => "FirstMatchState"}] }

        context "that is true" do
          let(:input) { {"foo" => 0, "bar" => 1} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that is false" do
          let(:input) { {"foo" => 1, "bar" => 1} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with a NumericGreaterThan" do
        let(:choices) { [{"Variable" => "$.foo", "NumericGreaterThan" => 1, "Next" => "FirstMatchState"}] }

        context "that is true" do
          let(:input) { {"foo" => 2} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that is false" do
          let(:input) { {"foo" => 1} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with a NumericGreaterThanPath" do
        let(:choices) { [{"Variable" => "$.foo", "NumericGreaterThanPath" => "$.bar", "Next" => "FirstMatchState"}] }

        context "that is true" do
          let(:input) { {"foo" => 2, "bar" => 1} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that is false" do
          let(:input) { {"foo" => 1, "bar" => 1} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end

        context "with invalid Path" do
          let(:choices) { [{"Variable" => "$.foo", "NumericGreaterThanPath" => "bogus", "Next" => "FirstMatchState"}] }
          let(:input) { {} }
          it { expect { subject }.to raise_exception(Floe::InvalidWorkflowError, "States.Choice1.Choices.0.Data field \"NumericGreaterThanPath\" value \"bogus\" Path [bogus] must start with \"$\"") }
        end
      end

      context "with a NumericLessThanEquals" do
        let(:choices) { [{"Variable" => "$.foo", "NumericLessThanEquals" => 1, "Next" => "FirstMatchState"}] }

        context "that is true" do
          let(:input) { {"foo" => 1} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that is false" do
          let(:input) { {"foo" => 2} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with a NumericLessThanEqualsPath" do
        let(:choices) { [{"Variable" => "$.foo", "NumericLessThanEqualsPath" => "$.bar", "Next" => "FirstMatchState"}] }

        context "that is true" do
          let(:input) { {"foo" => 1, "bar" => 1} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that is false" do
          let(:input) { {"foo" => 2, "bar" => 1} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with a NumericGreaterThanEquals" do
        let(:choices) { [{"Variable" => "$.foo", "NumericGreaterThanEquals" => 1, "Next" => "FirstMatchState"}] }

        context "that is true" do
          let(:input) { {"foo" => 1} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that is false" do
          let(:input) { {"foo" => 0} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with a NumericGreaterThanEqualsPath" do
        let(:choices) { [{"Variable" => "$.foo", "NumericGreaterThanEqualsPath" => "$.bar", "Next" => "FirstMatchState"}] }

        context "that is true" do
          let(:input) { {"foo" => 1, "bar" => 1} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that is false" do
          let(:input) { {"foo" => 0, "bar" => 1} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with a StringMatches" do
        let(:choices) { [{"Variable" => "$.foo", "StringMatches" => "*.log", "Next" => "FirstMatchState"}] }

        context "that is true" do
          let(:input) { {"foo" => "audit.log"} }
          it { expect(subject).to eq(true) }
        end

        context "that is false" do
          let(:input) { {"foo" => "audit"} }
          it { expect(subject).to eq(false) }
        end

        context "that does not exist" do
          let(:input) { {} }
          it { expect { subject }.to raise_exception(Floe::PathError, "Path [$.foo] references an invalid value") }
        end

        context "that references a number" do
          let(:input) { {"foo" => 5} }
          it { expect { subject }.to raise_exception(Floe::ExecutionError, "States.Choice1.Choices.0.Data field \"Variable\" value \"$.foo\" required to point to a String") }
        end
      end
    end
  end
end
