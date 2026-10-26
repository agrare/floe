RSpec.describe Floe::Workflow::States::Choice do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  let(:workflow) { make_workflow(ctx, payload) }
  let(:choices) do
    [
      {"Variable" => "$.foo", "NumericEquals" => 1, "Next" => "FirstMatchState"},
      {"Variable" => "$.foo", "NumericEquals" => 2, "Next" => "SecondMatchState"},
    ]
  end

  let(:payload) do
    {
      "Choice1"          => {"Type" => "Choice", "Choices" => choices, "Default" => "DefaultState"},
      "FirstMatchState"  => {"Type" => "Succeed"},
      "SecondMatchState" => {"Type" => "Succeed"},
      "DefaultState"     => {"Type" => "Succeed"}
    }
  end

  context "with missing Choices" do
    let(:payload) { {"Choice1" => {"Type" => "Choice", "Default" => "DefaultState"}, "DefaultState" => {"type" => "Succeed"}} }
    it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.Choice1 does not have required field \"Choices\"") }
  end

  context "with non-array Choices" do
    let(:choices) { {} }
    it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.Choice1 field \"Choices\" must be a non-empty array") }
  end

  context "with an empty Choices array" do
    let(:choices) { [] }
    it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.Choice1 field \"Choices\" must be a non-empty array") }
  end

  context "with an invalid Default" do
    let(:payload) { {"Choice1" => {"Type" => "Choice", "Choices" => choices, "Default" => "MissingState"}, "FirstMatchState" => {"Type" => "Succeed"}, "SecondMatchState" => {"Type" => "Succeed"}} }
    it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.Choice1 field \"Default\" value \"MissingState\" is not found in \"States\"") }
  end

  it "#end?" do
    expect(state.end?).to eq(false)
  end

  describe "#run_nonblock!" do
    context "with a missing variable" do
      it "shows error" do
        workflow.run_nonblock
        expect(ctx.failed?).to eq(true)
        expect(ctx.output).to eq(
          {
            "Cause" => "Path [$.foo] references an invalid value",
            "Error" => "States.Runtime"
          }
        )
      end
    end

    context "with an input value matching a condition" do
      let(:input) { {"foo" => 1} }

      it "returns the next state" do
        state.run_nonblock!(ctx)
        expect(ctx.next_state).to eq("FirstMatchState")
      end
    end

    context "with an input value not matching any condition" do
      let(:input) { {"foo" => 4} }

      it "returns the default state" do
        state.run_nonblock!(ctx)
        expect(ctx.next_state).to eq("DefaultState")
      end
    end

    context "with no default" do
      let(:payload) do
        {
          "Choice1"          => {"Type" => "Choice", "Choices" => choices},
          "FirstMatchState"  => {"Type" => "Succeed"},
          "SecondMatchState" => {"Type" => "Succeed"}
        }
      end

      context "with an input value matching a condition" do
        let(:input) { {"foo" => 1} }

        it "returns the next state" do
          state.run_nonblock!(ctx)
          expect(ctx.next_state).to eq("FirstMatchState")
        end
      end

      context "with an input value not matching a condition" do
        let(:input) { {"foo" => 3} }

        it "throws error when not found" do
          workflow.run_nonblock
          expect(ctx.failed?).to eq(true)
          expect(ctx.output["Error"]).to eq("States.NoChoiceMatched")
          expect(ctx.output["Cause"]).to eq("States.Choice1 field \"Default\" not defined and no match found")
        end
      end
    end
  end
end

RSpec.describe Floe::Workflow::States::Choice, "with QueryLanguage JSONata" do
  let(:input)    { {"foo" => 1, "bar" => "baz"} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:workflow) { make_workflow(ctx, payload) }
  let(:default)  { "DefaultState" }
  let(:choices) do
    [
      {"Condition" => "{% $states.input.foo = 1 %}", "Next" => "FirstMatchState"},
      {"Condition" => "{% $states.input.foo = 2 %}", "Next" => "SecondMatchState"}
    ]
  end
  let(:choice) { {"Type" => "Choice", "QueryLanguage" => "JSONata", "Choices" => choices, "Default" => default}.compact }
  let(:payload) do
    {
      "Choice1"          => choice,
      "FirstMatchState"  => {"Type" => "Succeed"},
      "SecondMatchState" => {"Type" => "Succeed"},
      "DefaultState"     => {"Type" => "Succeed"}
    }
  end

  describe "#initialize" do
    %w[InputPath OutputPath].each do |field|
      context "with #{field}" do
        before { choice[field] = "$" }

        it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.Choice1 field \"#{field}\" is not allowed when QueryLanguage is \"JSONata\"") }
      end
    end

    context "with an unknown Next" do
      let(:choices) { [{"Condition" => "{% true %}", "Next" => "Missing"}] }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "Next" value "Missing" is not found in "States"/) }
    end

    context "with a missing Next" do
      let(:choices) { [{"Condition" => "{% true %}"}] }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /does not have required field "Next"/) }
    end

    context "with a JSONPath style rule" do
      let(:choices) { [{"Variable" => "$.foo", "NumericEquals" => 1, "Next" => "FirstMatchState"}] }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "Variable" is not allowed when QueryLanguage is "JSONata"/) }
    end

    context "with a JSONPath style comparison without a Variable" do
      let(:choices) { [{"NumericEquals" => 1, "Next" => "FirstMatchState"}] }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "NumericEquals" is not allowed/) }
    end

    %w[And Or Not].each do |op|
      context "with #{op}" do
        let(:choices) { [{op => [{"Condition" => "{% true %}"}], "Next" => "FirstMatchState"}] }

        it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "#{op}" is not allowed/) }
      end
    end

    context "with a missing Condition" do
      let(:choices) { [{"Next" => "FirstMatchState"}] }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /does not have required field "Condition"/) }
    end

    context "with a Condition that is not an expression" do
      let(:choices) { [{"Condition" => "$.foo", "Next" => "FirstMatchState"}] }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "Condition" value "\$.foo" must be a boolean or a JSONata expression/) }
    end

    context "with an invalid Condition expression" do
      let(:choices) { [{"Condition" => "{% 1 = %}", "Next" => "FirstMatchState"}] }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /Invalid JSONata expression/) }
    end

    context "with a boolean literal Condition" do
      let(:choices) { [{"Condition" => true, "Next" => "FirstMatchState"}] }

      it { expect { workflow }.not_to raise_error }
    end

    context "with Assign that is not an object" do
      let(:choices) { [{"Condition" => true, "Next" => "FirstMatchState", "Assign" => "x"}] }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "Assign".*must be an object/) }
    end

    context "with Output and Assign in a JSONPath rule" do
      let(:choice) { {"Type" => "Choice", "Choices" => [{"Variable" => "$.foo", "NumericEquals" => 1, "Next" => "FirstMatchState", "Output" => {}}], "Default" => default} }

      it "ignores the field as it does for any unknown key" do
        expect { workflow }.not_to raise_error
      end
    end
  end

  describe "#finish" do
    it "chooses the first matching rule" do
      workflow.run_nonblock

      expect(ctx.state_history.first["NextState"]).to eq("FirstMatchState")
      expect(ctx.state_history.first["Output"]).to eq(input)
    end

    context "when a later rule matches" do
      let(:input) { {"foo" => 2} }

      it "chooses that rule" do
        workflow.run_nonblock

        expect(ctx.state_history.first["NextState"]).to eq("SecondMatchState")
      end
    end

    context "when no rule matches" do
      let(:input) { {"foo" => 3} }

      it "chooses the Default" do
        workflow.run_nonblock

        expect(ctx.state_history.first["NextState"]).to eq("DefaultState")
        expect(ctx.state_history.first["Output"]).to eq(input)
      end

      context "without a Default" do
        let(:default) { nil }

        it "fails with States.NoChoiceMatched" do
          workflow.run_nonblock

          expect(ctx.status).to eq("failure")
          expect(ctx.output["Error"]).to eq("States.NoChoiceMatched")
        end
      end
    end

    context "with a Condition that is not a boolean" do
      let(:choices) { [{"Condition" => "{% $states.input.bar %}", "Next" => "FirstMatchState"}] }

      it "fails with States.QueryEvaluationError" do
        workflow.run_nonblock

        expect(ctx.status).to eq("failure")
        expect(ctx.output["Error"]).to eq("States.QueryEvaluationError")
        expect(ctx.output["Cause"]).to include("must evaluate to a boolean")
      end
    end

    context "with a Condition that is undefined" do
      let(:choices) { [{"Condition" => "{% $states.input.missing %}", "Next" => "FirstMatchState"}] }

      it "fails with States.QueryEvaluationError" do
        workflow.run_nonblock

        expect(ctx.output["Error"]).to eq("States.QueryEvaluationError")
      end
    end

    context "with a literal boolean Condition" do
      let(:choices) { [{"Condition" => false, "Next" => "FirstMatchState"}, {"Condition" => true, "Next" => "SecondMatchState"}] }

      it "uses the literal" do
        workflow.run_nonblock

        expect(ctx.state_history.first["NextState"]).to eq("SecondMatchState")
      end
    end

    context "with a Condition that uses a variable" do
      let(:choices) { [{"Condition" => "{% $states.input.foo = $expected %}", "Next" => "FirstMatchState"}] }

      before { ctx.variables["expected"] = 1 }

      it "can read the variable" do
        workflow.run_nonblock

        expect(ctx.state_history.first["NextState"]).to eq("FirstMatchState")
      end
    end

    context "with Output and Assign on the matching rule" do
      let(:choices) do
        [
          {"Condition" => "{% $states.input.foo = 2 %}", "Next" => "SecondMatchState", "Assign" => {"nope" => true}, "Output" => "nope"},
          {
            "Condition" => "{% $states.input.foo = 1 %}",
            "Next"      => "FirstMatchState",
            "Assign"    => {"saved" => "{% $states.input.bar %}"},
            "Output"    => {"bar" => "{% $states.input.bar %}"}
          }
        ]
      end

      it "only evaluates them for the matched rule" do
        workflow.run_nonblock

        expect(ctx.state_history.first["NextState"]).to eq("FirstMatchState")
        expect(ctx.state_history.first["Output"]).to eq("bar" => "baz")
        expect(ctx.variables).to eq("saved" => "baz")
      end
    end

    context "with a rule that matches nothing but has Assign" do
      let(:input) { {"foo" => 3} }
      let(:choices) { [{"Condition" => "{% $states.input.foo = 1 %}", "Next" => "FirstMatchState", "Assign" => {"a" => 1}}] }

      it "does not assign" do
        workflow.run_nonblock

        expect(ctx.variables).to eq({})
      end
    end

    context "with an Output expression that fails" do
      let(:choices) { [{"Condition" => true, "Next" => "FirstMatchState", "Output" => "{% $number('x') %}", "Assign" => {"a" => 1}}] }

      it "fails the state without assigning" do
        workflow.run_nonblock

        expect(ctx.output["Error"]).to eq("States.QueryEvaluationError")
        expect(ctx.variables).to eq({})
      end
    end
  end
end
