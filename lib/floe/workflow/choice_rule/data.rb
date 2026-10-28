# frozen_string_literal: true

module Floe
  class Workflow
    class ChoiceRule
      class Data < Floe::Workflow::ChoiceRule
        TYPES      = ["String", "Numeric", "Boolean", "Timestamp", "Present", "Null"].freeze
        COMPARES   = ["Equals", "LessThan", "GreaterThan", "LessThanEquals", "GreaterThanEquals", "Matches"].freeze
        OPERATIONS = TYPES.each_with_object({}) { |dt, a| a[dt] = :"is_#{dt.downcase}?" }
                          .merge(COMPARES.each_with_object({}) { |op, a| a[op] = :"op_#{op.downcase}?" }).freeze
        # e.g.: (Is)(String), (Is)(Present)
        TYPE_CHECK = /^Is(#{Regexp.union(TYPES)})$/
        # e.g.: (String)(LessThan)(Path), (Numeric)(GreaterThanEquals)()
        OPERATION  = /^(#{Regexp.union(TYPES - %w[Null Present])})(#{Regexp.union(COMPARES)})(Path)?$/

        attr_reader :variable, :compare_key, :operator, :type, :compare_predicate, :path

        def initialize(_workflow, _name, payload)
          super

          @variable = parse_path("Variable")
          parse_compare_key
        end

        # Evaluate whether this rule is true for the given context and input (runtime)
        #
        # @param context [Context] The workflow execution context
        # @param input [Hash] The current state input
        # @return [Boolean] true if the rule evaluate to true
        def true?(context, input)
          # Payload pattern is: {"Variable": $lhs, $operator: $rhs}
          # Example:
          #
          #   {"Variable": "$.foo", "IsNumeric": true}
          #     lhs = input["$.foo"]
          #     rhs = true
          #     is_numeric?(lhs, rhs)
          #
          #   {"Variable": "$.foo", "GreaterThanString": "aaa"}
          #     lhs = input["$.foo"]
          #     rhs = "aaa"
          #     op_greaterthan?(lhs, rhs)
          #
          #   {"Variable": "$.foo", "GreaterThanNumericPath": "$.bar"}
          #     lhs = input["$.foo"]
          #     rhs = input["$.bar"]
          #     op_greaterthan?(lhs, rhs)
          #
          # NOTE: IsPresent works a little differently as lhs might raise a PathError.
          #       See the exception handler below. This is why we process the rhs before the lhs.
          rhs = compare_value(context, input)
          lhs = variable_value(context, input)
          lhs, rhs = parse_timestamps(lhs, rhs) if timestamp_comparison?
          send(OPERATIONS[operator], lhs, rhs)
        rescue Floe::PathError
          # For IsPresent, we can expect the lhs to not be present in some cases,
          #                This throws a PathError. We handle that special case here.
          # Example:
          #
          #   {"Variable": "$.foo", "IsPresent": false}
          #     lhs = input["$.foo"], but variable is not present. (The variable lookup threw PathError)
          #     rhs = false
          return is_present?(:not_present, rhs) if operator == "Present"

          # for non "IsPresent" checks, share that lhs or rhs is not found.
          raise
        end

        private

        # rubocop:disable Naming/PredicateName
        # rubocop:disable Style/OptionalBooleanParameter
        def is_null?(value, expectation)
          value.nil? == expectation
        end

        def is_present?(value, expectation)
          (value != :not_present) == expectation
        end

        def is_numeric?(value, expectation)
          value.kind_of?(Numeric) == expectation
        end

        def is_string?(value, expectation)
          value.kind_of?(String) == expectation
        end

        def is_boolean?(value, expectation)
          [true, false].include?(value) == expectation
        end

        def is_timestamp?(value, expectation)
          require "date"

          DateTime.rfc3339(value)
          expectation
        rescue TypeError, Date::Error
          !expectation
        end
        # rubocop:enable Naming/PredicateName
        # rubocop:enable Style/OptionalBooleanParameter

        def op_equals?(lhs, rhs)
          lhs == rhs
        end

        def op_lessthan?(lhs, rhs)
          lhs < rhs
        end

        def op_greaterthan?(lhs, rhs)
          lhs > rhs
        end

        def op_lessthanequals?(lhs, rhs)
          lhs <= rhs
        end

        def op_greaterthanequals?(lhs, rhs)
          lhs >= rhs
        end

        def op_matches?(value, pattern)
          string_matches_regexp(pattern).match?(value)
        end

        # Convert a StringMatches pattern to an anchored Regexp.
        #
        # An asterisk matches zero or more characters, a backslash followed by an
        # asterisk is a literal asterisk, and two backslashes are a literal backslash.
        # No other characters have special meaning.
        def string_matches_regexp(pattern)
          regexp = +""
          chars  = pattern.each_char

          loop do
            char = chars.next
            case char
            when "*"
              regexp << ".*"
            when "\\"
              escaped = begin
                chars.next
              rescue StopIteration
                runtime_field_error!(compare_key, pattern, "must not end with an open escape character (\\)")
              end
              regexp << Regexp.escape(escaped)
            else
              regexp << Regexp.escape(char)
            end
          end

          Regexp.new("\\A#{regexp}\\z", Regexp::MULTILINE)
        end

        def timestamp_comparison?
          type == "Timestamp"
        end

        # Timestamps must be compared as points in time, not as strings, since
        # the same instant can be written with different offsets.
        def parse_timestamps(*values)
          require "date"

          values.map { |value| DateTime.rfc3339(value) }
        end

        # parse the compare key at initialization time
        def parse_compare_key
          payload.each_key do |key|
            # e.g. (String)(GreaterThan)(Path)
            if (match_values = OPERATION.match(key))
              @compare_key = key
              @type, @operator, @path = match_values.captures
              @compare_predicate = parse_predicate(type)
              break
            # e.g. (Is)(String)
            elsif (match_value = TYPE_CHECK.match(key))
              @compare_key = key
              @operator = match_value.captures.first
              # type: nil means no runtime type checking.
              @type = @path = nil
              @compare_predicate = parse_predicate("Boolean")
              break
            end
          end
          parser_error!("requires a compare key") if compare_key.nil? || operator.nil?
        end

        # parse predicate at initialization time
        # @param data_type [String] the data type of the variable
        #                  When parsing operations (IntegerGreaterThan), this will be the operation data type (e.g.: Integer)
        #                  When parsing type checks (IsString), this will always be a Boolean
        # @return the right predicate attached to the compare key
        def parse_predicate(data_type)
          path ? parse_path(compare_key) : parse_field(compare_key, data_type)
        end

        # @return right hand predicate - input path or static payload value)
        def compare_value(context, input)
          path ? fetch_path(compare_key, compare_predicate, context, input) : compare_predicate
        end

        # fetch the variable value at runtime
        # @return variable value (left hand side)
        def variable_value(context, input)
          fetch_path("Variable", variable, context, input)
        end

        # parse path at initialization time
        # helper method to parse a path from the payload
        def parse_path(field_name)
          value = payload[field_name]
          missing_field_error!(field_name) unless value
          wrap_parser_error(field_name, value) { Path.new(value) }
        end

        # parse predicate field at initialization time
        # @param field_name [String] the compare key
        # @param data_type [String] the data type of the variable
        #                  When parsing operations (IntegerGreaterThan), this will be the operation data type (e.g.: Integer)
        #                  When parsing type checks (IsString), this will always be a Boolean
        def parse_field(field_name, data_type)
          value = payload[field_name]
          return value if correct_type?(value, data_type)

          invalid_field_error!(field_name, value, "required to be a #{data_type}")
        end

        # fetch a path at runtime
        def fetch_path(field_name, field_path, context, input)
          value = field_path.value(context, input)
          # if this is an operation (GreaterThanPath), ensure the value is the correct type
          return value if type.nil? || correct_type?(value, type)

          runtime_field_error!(field_name, field_path.to_s, "required to point to a #{type}")
        end

        # if we have runtime checking, check against that type
        #   otherwise assume checking a TYPE_CHECK predicate and check against Boolean
        def correct_type?(value, data_type)
          send(OPERATIONS[data_type], value, true)
        end
      end
    end
  end
end
