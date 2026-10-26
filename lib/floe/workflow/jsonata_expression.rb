# frozen_string_literal: true

module Floe
  class Workflow
    # A JSONata expression embedded in a string as "{% expression %}"
    #
    # The jsonata gem is loaded lazily as it requires ruby >= 3.1 and is only
    # needed by workflows which use the JSONata query language.
    class JsonataExpression
      PREFIX = "{%"
      SUFFIX = "%}"

      class << self
        # @return [Boolean] true if the value is a String wrapped in {% %}
        def jsonata?(payload)
          payload.kind_of?(String) && payload.start_with?(PREFIX) && payload.end_with?(SUFFIX)
        end

        # @return [Boolean] true if the value looks like it was meant to be an expression but is malformed
        def partial?(payload)
          payload.kind_of?(String) && !jsonata?(payload) && (payload.start_with?(PREFIX) || payload.end_with?(SUFFIX))
        end
      end

      attr_reader :payload

      # @param payload [String] the expression including the {% %} delimiters
      def initialize(payload)
        raise Floe::InvalidWorkflowError, "JSONata expression must be wrapped in \"#{PREFIX} #{SUFFIX}\"" unless self.class.jsonata?(payload)

        @payload    = payload
        @expression = compile(payload[PREFIX.length..-(SUFFIX.length + 1)])
      end

      # Evaluate the expression
      #
      # @param bindings [Hash] variable bindings (e.g. "states" => {...}, "myvar" => 1)
      # @return the result of the expression, nil if undefined
      def value(bindings = {})
        @expression.evaluate(nil, bindings)
      rescue ::Jsonata::Error => err
        raise Floe::ExecutionError.new("#{payload}: #{err.message}", "States.QueryEvaluationError")
      end

      private

      def compile(expression)
        require_jsonata
        ::Jsonata.expression(expression)
      rescue ::Jsonata::Error => err
        raise Floe::InvalidWorkflowError, "Invalid JSONata expression #{payload}: #{err.message}"
      end

      def require_jsonata
        require "jsonata"
      rescue LoadError
        raise Floe::InvalidWorkflowError, "The jsonata gem (requires ruby >= 3.1) is required to use the JSONata query language"
      end
    end
  end
end
