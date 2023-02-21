RSpec.describe Floe::Workflow::ChoiceRule do
  describe "#true?" do
    let(:subject) { described_class.true?(payload, context, input) }
    let(:context) { {} }

    context "Boolean Expression" do
      context "Not" do
        let(:payload) { {"Not" => {"Variable" => "$.foo", "StringEquals" => "bar"}, "Next" => "FirstMatchState"} }

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
          let(:payload) { {"And" => [{"Variable" => "$.foo", "StringEquals" => "foo"}, {"Variable" => "$.bar", "StringEquals" => "bar"}], "Next" => "FirstMatchState"} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "with one sub-choice false" do
          let(:payload) { {"And" => [{"Variable" => "$.foo", "StringEquals" => "foo"}, {"Variable" => "$.bar", "StringEquals" => "foo"}], "Next" => "FirstMatchState"} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "Or" do
        let(:input) { {"foo" => "foo", "bar" => "bar"} }

        context "with one sub-choice being true" do
          let(:payload) { {"Or" => [{"Variable" => "$.foo", "StringEquals" => "foo"}, {"Variable" => "$.bar", "StringEquals" => "foo"}], "Next" => "FirstMatchState"} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "with no sub-choices being true" do
          let(:payload) { {"Or" => [{"Variable" => "$.foo", "StringEquals" => "bar"}, {"Variable" => "$.bar", "StringEquals" => "foo"}], "Next" => "FirstMatchState"} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end
    end

    context "Data-Test Expression" do
      context "with a missing variable" do
        let(:payload) { {"Variable" => "$.foo", "NumericEquals" => 1, "Next" => "FirstMatchState" } }
        let(:input) { {} }

        it "raises an exception" do
          expect { subject }.to raise_exception(RuntimeError, "No such variable [$.foo]")
        end
      end

      context "with IsNull" do
        let(:payload) { {"Variable" => "$.foo", "IsNull" => true} }

        context "with null" do
          let(:input) { {"foo" => nil} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "with non-null" do
          let(:input) { {"foo" => "bar"} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with IsPresent" do
        let(:payload) { {"Variable" => "$.foo", "IsPresent" => true} }

        context "with null" do
          let(:input) { {"foo" => nil} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end

        context "with non-null" do
          let(:input) { {"foo" => "bar"} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end
      end

      context "with IsNumeric" do
        let(:payload) { {"Variable" => "$.foo", "IsNumeric" => true} }

        context "with an integer" do
          let(:input) { {"foo" => 1} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "with a float" do
          let(:input) { {"foo" => 1.5} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "with a string" do
          let(:input) { {"foo" => "bar"} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end

      context "with IsString" do
        let(:payload) { {"Variable" => "$.foo", "IsString" => true} }

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
        let(:payload) { {"Variable" => "$.foo", "IsBoolean" => true} }

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
        let(:payload) { {"Variable" => "$.foo", "IsTimestamp" => true} }

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
        let(:payload) { {"Variable" => "$.foo", "NumericEquals" => 1, "Next" => "FirstMatchState" } }

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
        let(:payload) { {"Variable" => "$.foo", "NumericEqualsPath" => "$.bar", "Next" => "FirstMatchState" } }

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
      end

      context "with a NumericLessThan" do
        let(:payload) { {"Variable" => "$.foo", "NumericLessThan" => 1, "Next" => "FirstMatchState" } }

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
        let(:payload) { {"Variable" => "$.foo", "NumericLessThanPath" => "$.bar", "Next" => "FirstMatchState" } }

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
        let(:payload) { {"Variable" => "$.foo", "NumericGreaterThan" => 1, "Next" => "FirstMatchState" } }

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
        let(:payload) { {"Variable" => "$.foo", "NumericGreaterThanPath" => "$.bar", "Next" => "FirstMatchState" } }

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
      end

      context "with a NumericLessThanEquals" do
        let(:payload) { {"Variable" => "$.foo", "NumericLessThanEquals" => 1, "Next" => "FirstMatchState" } }

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
        let(:payload) { {"Variable" => "$.foo", "NumericLessThanEqualsPath" => "$.bar", "Next" => "FirstMatchState" } }

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
        let(:payload) { {"Variable" => "$.foo", "NumericGreaterThanEquals" => 1, "Next" => "FirstMatchState" } }

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
        let(:payload) { {"Variable" => "$.foo", "NumericGreaterThanEqualsPath" => "$.bar", "Next" => "FirstMatchState" } }

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
        let(:payload) { {"Variable" => "$.foo", "StringMatches" => "*.log", "Next" => "FirstMatchState" } }

        context "that is true" do
          let(:input) { {"foo" => "audit.log"} }

          it "returns true" do
            expect(subject).to eq(true)
          end
        end

        context "that is false" do
          let(:input) { {"foo" => "audit"} }

          it "returns false" do
            expect(subject).to eq(false)
          end
        end
      end
    end
  end

  describe "#to_dot_label" do
    let(:subject) { described_class.build(payload) }

    context "Boolean Expression" do
      it "Not" do
        payload = {"Not" => {"Variable" => "$.foo", "StringEquals" => "bar"}, "Next" => "FirstMatchState"}
        expect(described_class.build(payload).to_dot_label).to eq("!($.foo == \"bar\")")
      end

      it "And" do
        payload = {"And" => [{"Variable" => "$.foo", "StringEquals" => "foo"}, {"Variable" => "$.bar", "StringEquals" => "bar"}], "Next" => "FirstMatchState"}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo == \"foo\" && $.bar == \"bar\"")
      end

      it "Or" do
        payload = {"Or" => [{"Variable" => "$.foo", "StringEquals" => "foo"}, {"Variable" => "$.bar", "StringEquals" => "foo"}], "Next" => "FirstMatchState"}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo == \"foo\" || $.bar == \"foo\"")
      end
    end

    context "Data-Test Expression" do
      it "IsNull" do
        payload = {"Variable" => "$.foo", "IsNull" => true}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo IsNull true")
      end

      it "IsPresent" do
        payload = {"Variable" => "$.foo", "IsPresent" => true}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo IsPresent true")
      end

      it "IsNumeric" do
        payload = {"Variable" => "$.foo", "IsNumeric" => true}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo IsNumeric true")
      end

      it "IsString" do
        payload = {"Variable" => "$.foo", "IsString" => true}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo IsString true")
      end

      it "IsBoolean" do
        payload = {"Variable" => "$.foo", "IsBoolean" => true}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo IsBoolean true")
      end

      it "IsTimestamp" do
        payload = {"Variable" => "$.foo", "IsTimestamp" => true}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo IsTimestamp true")
      end

      it "StringEquals" do
        payload = {"Variable" => "$.foo", "StringEquals" => "bar"}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo == \"bar\"")
      end

      it "StringEqualsPath" do
        payload = {"Variable" => "$.foo", "StringEquals" => "$.bar"}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo == \"$.bar\"")
      end

      it "NumericLessThan" do
        payload = {"Variable" => "$.foo", "NumericLessThan" => 1}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo < 1")
      end

      it "NumericLessThanPath" do
        payload = {"Variable" => "$.foo", "NumericLessThanPath" => "$.bar"}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo < \"$.bar\"")
      end

      it "NumericGreaterThan" do
        payload = {"Variable" => "$.foo", "NumericGreaterThan" => 1}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo > 1")
      end

      it "NumericGreaterThanPath" do
        payload = {"Variable" => "$.foo", "NumericGreaterThanPath" => "$.bar"}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo > \"$.bar\"")
      end

      it "NumericLessThanEquals" do
        payload = {"Variable" => "$.foo", "NumericLessThanEquals" => 1}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo <= 1")
      end

      it "NumericLessThanEqualsPath" do
        payload = {"Variable" => "$.foo", "NumericLessThanEqualsPath" => "$.bar"}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo <= \"$.bar\"")
      end

      it "NumericGreaterThanEquals" do
        payload = {"Variable" => "$.foo", "NumericGreaterThanEquals" => 1}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo >= 1")
      end

      it "NumericGreaterThanEqualsPath" do
        payload = {"Variable" => "$.foo", "NumericGreaterThanEqualsPath" => "$.bar"}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo >= \"$.bar\"")
      end

      it "StringMatches" do
        payload = {"Variable" => "$.foo", "StringMatches" => "bar"}
        expect(described_class.build(payload).to_dot_label).to eq("$.foo matches \"bar\"")
      end
    end
  end
end
