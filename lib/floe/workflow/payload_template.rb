# frozen_string_literal: true

module Floe
  class Workflow
    class PayloadTemplate
      def initialize(payload)
        @payload_template = parse_payload(payload)
      end

      def value(context, inputs = {})
        interpolate_value(payload_template, context, inputs)
      end

      private

      attr_reader :payload_template

      def parse_payload(value)
        case value
        when Array then parse_payload_array(value)
        when Hash  then parse_payload_hash(value)
        else value
        end
      end

      def parse_payload_array(value)
        value.map { |val| parse_payload(val) }
      end

      def parse_payload_hash(value)
        value.to_h do |key, val|
          if key.end_with?(".$")
            check_dynamic_datatype(key, val)
            check_dynamic_key_conflicts(key, value)

            [key, parse_dynamic_payload_string(key, val)]
          else
            [key, parse_payload(val)]
          end
        end
      end

      def parse_dynamic_payload_string(key, value)
        return Path.new(value)              if Path.path?(value)
        return IntrinsicFunction.new(value) if IntrinsicFunction.intrinsic_function?(value)

        raise Floe::InvalidWorkflowError, "The value for the field \"#{key}\" must be a String that contains a valid Reference Path or Intrinsic Function expression"
      end

      def check_dynamic_datatype(key, value)
        unless value.kind_of?(String)
          raise Floe::InvalidWorkflowError, "The value for the field \"#{key}\" must be a String that contains a valid Reference Path or Intrinsic Function expression"
        end
      end

      def check_dynamic_key_conflicts(key, value)
        if value.key?(key.chomp(".$"))
          raise Floe::InvalidWorkflowError, "both #{key} and #{key.chomp(".$")} present"
        end
      end

      def interpolate_value(value, context, inputs)
        case value
        when Array then interpolate_value_array(value, context, inputs)
        when Hash  then interpolate_value_hash(value, context, inputs)
        else value
        end
      end

      def interpolate_value_array(value, context, inputs)
        value.map { |val| interpolate_value(val, context, inputs) }
      end

      def interpolate_value_hash(value, context, inputs)
        value.to_h do |key, val|
          if key.end_with?(".$")
            [key.chomp(".$"), interpolate_dynamic_value(val, context, inputs)]
          else
            [key, interpolate_value(val, context, inputs)]
          end
        end
      end

      def interpolate_dynamic_value(value, context, inputs)
        # value will be a Path or IntrinsicFunction
        value.value(context, inputs)
      rescue Floe::PathError => err
        error_name = value.kind_of?(IntrinsicFunction) ? "States.IntrinsicFailure" : "States.ParameterPathFailure"
        raise Floe::ExecutionError.new(err.message, error_name)
      rescue ArgumentError => err
        raise unless value.kind_of?(IntrinsicFunction)

        raise Floe::ExecutionError.new(err.message, "States.IntrinsicFailure")
      end
    end
  end
end
