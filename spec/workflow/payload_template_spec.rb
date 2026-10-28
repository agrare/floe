RSpec.describe Floe::Workflow::PayloadTemplate do
  let(:subject) { described_class.new(payload) }

  describe "#value" do
    context "with static array" do
      let(:payload) { ["a", 2] }
      let(:context) { {} }

      it "returns the original value" do
        expect(subject.value(context)).to eq(["a", 2])
      end
    end

    context "with static values" do
      let(:payload) { {"foo" => "bar", "bar" => "$.baz", "baz" => 3} }
      let(:context) { {} }

      it "returns the original value" do
        expect(subject.value(context)).to eq({"foo" => "bar", "bar" => "$.baz", "baz" => 3})
      end
    end

    context "with intrinsic functions" do
      let(:payload) { {"uuid.$" => "States.UUID()"} }
      let(:context) { {} }
      let(:inputs)  { {} }

      it "calls the UUID intrinsic function" do
        expect(subject.value(context, inputs)).to include("uuid" => a_string_matching(/^\h{8}-\h{4}-\h{4}-\h{4}-\h{12}$/))
      end
    end

    context "with dynamic values" do
      let(:payload) { {"foo.$" => "$.foo", "bar.$" => "$$.bar"} }
      let(:context) { {"bar" => "baz"} }
      let(:inputs)  { {"foo" => "bar"} }

      it "returns the value from the inputs" do
        expect(subject.value(context, inputs)).to eq({"foo" => "bar", "bar" => "baz"})
      end

      context "with key conflicts" do
        let(:payload) { {"foo.$" => "$.foo", "foo" => "bar"} }

        it "raises an exception" do
          expect { subject }.to raise_error(Floe::InvalidWorkflowError, "both foo.$ and foo present")
        end
      end

      context "with invalid value data type" do
        context "of Integer" do
          let(:payload) { {"foo.$" => 123} }

          it "raises an exception" do
            expect { subject }.to raise_error(Floe::InvalidWorkflowError, "The value for the field \"foo.$\" must be a String that contains a valid Reference Path or Intrinsic Function expression")
          end
        end

        context "of Array" do
          let(:payload) { {"foo.$" => ["foo"]} }

          it "raises an exception" do
            expect { subject }.to raise_error(Floe::InvalidWorkflowError, "The value for the field \"foo.$\" must be a String that contains a valid Reference Path or Intrinsic Function expression")
          end
        end

        context "of Hash" do
          let(:payload) { {"foo.$" => {"foo" => "bar"}} }

          it "raises an exception" do
            expect { subject }.to raise_error(Floe::InvalidWorkflowError, "The value for the field \"foo.$\" must be a String that contains a valid Reference Path or Intrinsic Function expression")
          end
        end
      end

      context "with invalid value string" do
        let(:payload) { {"foo.$" => "foo"} }

        it "raises an exception" do
          expect { subject }.to raise_error(Floe::InvalidWorkflowError, "The value for the field \"foo.$\" must be a String that contains a valid Reference Path or Intrinsic Function expression")
        end
      end

      context "that are deeply nested Paths" do
        let(:payload) { {"foo" => {"bar" => {"baz.$" => "$.baz"}}} }
        let(:context) { {} }
        let(:inputs)  { {"baz" => 123} }

        it "returns the value from the inputs" do
          expect(subject.value(context, inputs)).to eq({"foo" => {"bar" => {"baz" => 123}}})
        end
      end

      context "that are deeply nested Intrinsic Functions" do
        let(:payload) { {"foo" => {"bar" => {"baz.$" => "States.UUID()"}}} }
        let(:context) { {} }

        it "returns the value from the inputs" do
          expect(subject.value(context, inputs)).to match({"foo" => {"bar" => {"baz" => a_string_matching(/^\h{8}-\h{4}-\h{4}-\h{4}-\h{12}$/)}}})
        end
      end
    end

    context "with errors" do
      let(:context) { {} }
      let(:inputs)  { {"foo" => "bar", "arr" => [1]} }

      def expect_error(error_name, message = nil)
        expect { subject.value(context, inputs) }.to raise_error(Floe::ExecutionError, message) { |err| expect(err.floe_error).to eq(error_name) }
      end

      context "with a Path that references a missing value" do
        let(:payload) { {"foo.$" => "$.missing"} }

        it "raises States.ParameterPathFailure" do
          expect_error("States.ParameterPathFailure", "Path [$.missing] references an invalid value")
        end
      end

      context "with a nested Path that references a missing value" do
        let(:payload) { {"foo" => {"bar" => [{"baz.$" => "$.missing"}]}} }

        it "raises States.ParameterPathFailure" do
          expect_error("States.ParameterPathFailure")
        end
      end

      context "with an Intrinsic Function with an argument of the wrong type" do
        let(:payload) { {"foo.$" => "States.MathAdd($.foo, 1)"} }

        it "raises States.IntrinsicFailure" do
          expect_error("States.IntrinsicFailure", "wrong type for argument 1 to States.MathAdd (given String, expected Integer)")
        end
      end

      context "with an Intrinsic Function with the wrong number of arguments" do
        let(:payload) { {"foo.$" => "States.MathAdd(1)"} }

        it "raises States.IntrinsicFailure" do
          expect_error("States.IntrinsicFailure", "wrong number of arguments to States.MathAdd (given 1, expected 2)")
        end
      end

      context "with an Intrinsic Function with an invalid value" do
        let(:payload) { {"foo.$" => "States.StringToJson($.foo)"} }

        it "raises States.IntrinsicFailure" do
          expect_error("States.IntrinsicFailure")
        end
      end

      context "with an Intrinsic Function with a Path argument that references a missing value" do
        let(:payload) { {"foo.$" => "States.Array($.missing)"} }

        it "raises States.IntrinsicFailure" do
          expect_error("States.IntrinsicFailure", "Path [$.missing] references an invalid value")
        end
      end
    end
  end
end
