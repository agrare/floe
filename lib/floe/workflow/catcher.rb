# frozen_string_literal: true

module Floe
  class Workflow
    class Catcher
      include ErrorMatcherMixin
      include ValidationMixin

      attr_reader :error_equals, :next, :result_path, :name, :output, :assign, :query_language

      # @param query_language [String] the query language of the state this Catch belongs to
      def initialize(workflow, name, payload, query_language: "JSONPath")
        @name           = name
        @payload        = payload
        @query_language = query_language

        @error_equals = payload["ErrorEquals"]
        @next         = payload["Next"]

        if jsonata?
          invalid_field_error!("ResultPath", payload["ResultPath"], "is not allowed when QueryLanguage is \"JSONata\"") if payload.key?("ResultPath")

          @output = JsonataTemplate.new(payload["Output"], name + ["Output"]) if payload.key?("Output")
          if payload.key?("Assign")
            invalid_field_error!("Assign", payload["Assign"], "must be an object") unless payload["Assign"].kind_of?(Hash)
            @assign = JsonataTemplate.new(payload["Assign"], name + ["Assign"])
          end
        else
          %w[Output Assign].each do |field|
            invalid_field_error!(field, nil, "is not allowed when QueryLanguage is \"JSONPath\"") if payload.key?(field)
          end

          @result_path = ReferencePath.new(payload.fetch("ResultPath", "$"))
        end

        missing_field_error!("ErrorEquals") if !@error_equals.kind_of?(Array) || @error_equals.empty?
        validate_state_next!(workflow)
      end

      def jsonata?
        query_language == "JSONata"
      end

      # Calculate the output of the state when this Catch is used
      #
      # JSONPath: the error is set at ResultPath of the state input
      # JSONata:  the error is $states.errorOutput which can be replaced by Output. Assign sets variables.
      #
      # @return [Object] the output of the state
      def process_output(context, error)
        return result_path.set(context.input, error) unless jsonata?

        bindings    = context.states_bindings(context.input, :error_output => error)
        assignments = assign&.value(bindings)
        result      = output ? output.value(bindings) : error

        context.variables.merge!(assignments) if assignments
        result
      end

      private

      def validate_state_next!(workflow)
        missing_field_error!("Next") if @next.nil?
        invalid_field_error!("Next", @next, "is not found in \"States\"") if @next && !workflow.state?(@next)
      end
    end
  end
end
