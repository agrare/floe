# frozen_string_literal: true

module Floe
  class Workflow
    module States
      # Behavior shared by states which support the JSONata query language
      # Arguments, Output and Assign fields.
      module JsonataMixin
        attr_reader :arguments, :output, :assign

        private

        # Parse the Arguments, Output and Assign fields of a JSONata state.
        #
        # @param arguments [Boolean] whether this state supports the Arguments field
        def parse_jsonata_fields(payload, arguments: false)
          @arguments = JsonataTemplate.new(payload["Arguments"], name + ["Arguments"]) if arguments && payload.key?("Arguments")
          @output    = JsonataTemplate.new(payload["Output"], name + ["Output"]) if payload.key?("Output")

          return unless payload.key?("Assign")

          invalid_field_error!("Assign", payload["Assign"], "must be an object") unless payload["Assign"].kind_of?(Hash)
          @assign = JsonataTemplate.new(payload["Assign"], name + ["Assign"])
        end

        # Compile a field which, in a JSONata state, may be a "{% %}" expression
        #
        # @return [JsonataExpression, Object] the expression, or the unchanged value
        def parse_jsonata_value(value)
          jsonata? && JsonataExpression.jsonata?(value) ? JsonataExpression.new(value) : value
        end

        # Evaluate a value which was parsed with parse_jsonata_value
        def evaluate_jsonata_value(context, value)
          value.kind_of?(JsonataExpression) ? value.value(jsonata_bindings(context)) : value
        end

        def jsonata_bindings(context, options = {})
          context.states_bindings(context.input, **options)
        end

        # Evaluate Assign and Output.
        #
        # Both are evaluated before any variable is set, so assignments
        # cannot see each other nor the output of the same state.
        #
        # @param default_output [Object] the output when the Output field is not given
        # @param options [Hash] extra $states fields, e.g. :result or :error_output
        # @return [Object] the output of the state
        def process_output_jsonata(context, default_output, options = {})
          bindings    = jsonata_bindings(context, options)
          assignments = assign&.value(bindings)
          result      = output ? output.value(bindings) : default_output

          context.variables.merge!(assignments) if assignments
          result
        end
      end
    end
  end
end
