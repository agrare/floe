# frozen_string_literal: true

module Floe
  class Workflow
    class ChoiceRule
      # A top level choice rule of a state using the JSONata query language
      #
      # {
      #   "Condition": "{% $states.input.foo > 1 %}",
      #   "Next": "NextState",
      #   "Assign": {"var": "{% $states.input.foo %}"},
      #   "Output": {"bar": "{% $states.input.bar %}"}
      # }
      #
      # Condition may also be the boolean literal true or false.
      class Jsonata < Floe::Workflow::ChoiceRule
        JSONPATH_ONLY_FIELDS = %w[Variable And Or Not].freeze

        attr_reader :condition, :assign, :output

        def initialize(workflow, name, payload)
          super

          validate_fields!

          @condition = parse_condition
          @assign    = JsonataTemplate.new(payload["Assign"], name + ["Assign"]) if payload.key?("Assign")
          @output    = JsonataTemplate.new(payload["Output"], name + ["Output"]) if payload.key?("Output")
        end

        # Evaluate whether this rule is true for the given context and input (runtime)
        #
        # @param context [Context] The workflow execution context
        # @param input [Object] The current state input
        # @return [Boolean] true if the Condition evaluates to true
        def true?(context, input)
          return condition unless condition.kind_of?(JsonataExpression)

          result = condition.value(context.states_bindings(input))
          return result if [true, false].include?(result)

          runtime_field_error!("Condition", result.inspect, "must evaluate to a boolean", :floe_error => "States.QueryEvaluationError")
        end

        # Evaluate Assign and Output for a rule which matched, and set the variables
        #
        # @return [Object] the output of the state, which defaults to the input
        def process_output(context, input)
          bindings    = context.states_bindings(input)
          assignments = assign&.value(bindings)
          result      = output ? output.value(bindings) : input

          context.variables.merge!(assignments) if assignments
          result
        end

        private

        def validate_fields!
          field = payload.keys.detect { |key| JSONPATH_ONLY_FIELDS.include?(key) || Data::TYPE_CHECK.match?(key) || Data::OPERATION.match?(key) }
          invalid_field_error!(field, nil, "is not allowed when QueryLanguage is \"JSONata\"") if field

          invalid_field_error!("Assign", payload["Assign"], "must be an object") if payload.key?("Assign") && !payload["Assign"].kind_of?(Hash)
        end

        def parse_condition
          value = payload["Condition"]

          missing_field_error!("Condition") if value.nil?
          return value if [true, false].include?(value)
          return JsonataExpression.new(value) if JsonataExpression.jsonata?(value)

          invalid_field_error!("Condition", value, "must be a boolean or a JSONata expression")
        end
      end
    end
  end
end
