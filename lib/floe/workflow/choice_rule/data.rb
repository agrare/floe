# frozen_string_literal: true

module Floe
  class Workflow
    class ChoiceRule
      class Data < Floe::Workflow::ChoiceRule
        def true?(context, input)

          lhs = variable_value(context, input)
          rhs = compare_value(context, input)

          validate!(lhs)

          case compare_key
          when "IsNull"; is_null?(lhs)
          when "IsPresent"; is_present?(lhs)
          when "IsNumeric"; is_numeric?(lhs)
          when "IsString"; is_string?(lhs)
          when "IsBoolean"; is_boolean?(lhs)
          when "IsTimestamp"; is_timestamp?(lhs)
          when "StringEquals", "StringEqualsPath",
               "NumericEquals", "NumericEqualsPath",
               "BooleanEquals", "BooleanEqualsPath",
               "TimestampEquals", "TimestampEqualsPath"
            lhs == rhs
          when "StringLessThan", "StringLessThanPath",
               "NumericLessThan", "NumericLessThanPath",
               "TimestampLessThan", "TimestampLessThanPath"
            lhs < rhs
          when "StringGreaterThan", "StringGreaterThanPath",
               "NumericGreaterThan", "NumericGreaterThanPath",
               "TimestampGreaterThan", "TimestampGreaterThanPath"
            lhs > rhs
          when "StringLessThanEquals", "StringLessThanEqualsPath",
               "NumericLessThanEquals", "NumericLessThanEqualsPath",
               "TimestampLessThanEquals", "TimestampLessThanEqualsPath"
            lhs <= rhs
          when "StringGreaterThanEquals", "StringGreaterThanEqualsPath",
               "NumericGreaterThanEquals", "NumericGreaterThanEqualsPath",
               "TimestampGreaterThanEquals", "TimestampGreaterThanEqualsPath"
            lhs >= rhs
          when "StringMatches"
            lhs.match?(Regexp.escape(rhs).gsub('\*','.*?'))
          else
            raise Floe::InvalidWorkflowError, "Invalid choice [#{compare_key}]"
          end
        end

        def to_dot_label
          operator =
            case compare_key
            when "IsNull", "IsPresent", "IsNumeric",
                "IsString", "IsBoolean", "IsTimestamp"
              compare_key
            when "StringEquals", "StringEqualsPath",
                "NumericEquals", "NumericEqualsPath",
                "BooleanEquals", "BooleanEqualsPath",
                "TimestampEquals", "TimestampEqualsPath"
              "=="
            when "StringLessThan", "StringLessThanPath",
                "NumericLessThan", "NumericLessThanPath",
                "TimestampLessThan", "TimestampLessThanPath"
              "<"
            when "StringGreaterThan", "StringGreaterThanPath",
                "NumericGreaterThan", "NumericGreaterThanPath",
                "TimestampGreaterThan", "TimestampGreaterThanPath"
              ">"
            when "StringLessThanEquals", "StringLessThanEqualsPath",
                "NumericLessThanEquals", "NumericLessThanEqualsPath",
                "TimestampLessThanEquals", "TimestampLessThanEqualsPath"
              "<="
            when "StringGreaterThanEquals", "StringGreaterThanEqualsPath",
                "NumericGreaterThanEquals", "NumericGreaterThanEqualsPath",
                "TimestampGreaterThanEquals", "TimestampGreaterThanEqualsPath"
              ">="
            when "StringMatches"
              "matches"
            end

          [variable, operator, payload[compare_key]&.inspect].compact.join(" ")
        end

        private

        def validate!(value)
          raise RuntimeError, "No such variable [#{variable}]" if value.nil? && !%w[IsNull IsPresent].include?(compare_key)
        end

        def is_null?(value)
          value.nil?
        end

        def is_present?(value)
          !value.nil?
        end

        def is_numeric?(value)
          value.kind_of?(Integer) || value.kind_of?(Float)
        end

        def is_string?(value)
          value.kind_of?(String)
        end

        def is_boolean?(value)
          [true, false].include?(value)
        end

        def is_timestamp?(value)
          require "date"

          DateTime.rfc3339(value)
          true
        rescue TypeError, Date::Error
          false
        end

        def compare_key
          @compare_key ||= payload.keys.detect { |key| key.match?(/^(IsNull|IsPresent|IsNumeric|IsString|IsBoolean|IsTimestamp|String|Numeric|Boolean|Timestamp)/) }
        end

        def compare_value(context, input)
          compare_key.end_with?("Path") ? Path.value(payload[compare_key], context, input) : payload[compare_key]
        end
      end
    end
  end
end
