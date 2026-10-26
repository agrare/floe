# frozen_string_literal: true

module Floe
  class Workflow
    # A payload (Hash, Array or scalar) which may contain JSONata expressions ("{% ... %}")
    # in any string value, at any depth. Used for Arguments, Output, Assign, etc. when
    # the QueryLanguage is JSONata.
    #
    # Unlike a PayloadTemplate, there is no ".$" key suffix: every key is a plain key.
    #
    # NOTE: an expression which is undefined or evaluates to JSON null is returned as nil.
    class JsonataTemplate
      include ValidationMixin

      attr_reader :name

      # @param payload the template
      # @param name [Array<String>] the location of the template for error messages
      def initialize(payload, name = nil)
        @name             = name || []
        @payload_template = parse_payload(payload)
      end

      # @param bindings [Hash] see Context#states_bindings
      def value(bindings)
        interpolate_value(@payload_template, bindings)
      end

      private

      def parse_payload(value)
        case value
        when Array  then value.map { |val| parse_payload(val) }
        when Hash   then value.transform_values { |val| parse_payload(val) }
        when String then parse_string(value)
        else value
        end
      end

      def parse_string(value)
        if JsonataExpression.jsonata?(value)
          JsonataExpression.new(value)
        elsif JsonataExpression.partial?(value)
          parser_error!("value \"#{value}\" is not a valid JSONata expression: it must start with \"#{JsonataExpression::PREFIX}\" and end with \"#{JsonataExpression::SUFFIX}\"")
        else
          value
        end
      end

      def interpolate_value(value, bindings)
        case value
        when JsonataExpression then value.value(bindings)
        when Array             then value.map { |val| interpolate_value(val, bindings) }
        when Hash              then value.transform_values { |val| interpolate_value(val, bindings) }
        else value
        end
      end
    end
  end
end
