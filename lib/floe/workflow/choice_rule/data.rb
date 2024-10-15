# frozen_string_literal: true

module Floe
  class Workflow
    class ChoiceRule
      class Data < Floe::Workflow::ChoiceRule
        TYPES      = ["String", "Numeric", "Boolean", "Timestamp", "Present", "Null"].freeze
        COMPARES   = ["Equals", "LessThan", "GreaterThan", "LessThanEquals", "GreaterThanEquals", "Matches"].freeze
        # e.g.: (Is)(String), (Is)(Present)
        TYPE_CHECK = /^(Is)(#{TYPES.join("|")})$/.freeze
        # e.g.: (String)(LessThan)(Path), (Numeric)(GreaterThanEquals)()
        OPERATION  = /^(#{(TYPES - %w[Null Present]).join("|")})(#{COMPARES.join("|")})(Path)?$/.freeze

        attr_reader :variable, :compare_key, :operation, :type, :compare_predicate, :path

        def initialize(_workflow, _name, payload)
          super

          @variable = parse_path("Variable")
          parse_compare_key
        end

        def true?(context, input)
          return presence_check(context, input) if compare_key == "IsPresent"

          lhs = variable_value(context, input)
          rhs = compare_value(context, input)
          send(operation, lhs, rhs)
        end

        private

        def presence_check(context, input)
          # Get the right hand side for {"Variable": "$.foo", "IsPresent": true} i.e.: true
          # If true  then return true when present.
          # If false then return true when not present.
          predicate = compare_value(context, input)
          # Don't need the variable_value, just need to see if the path finds the value.
          variable_value(context, input)

          # The variable_value is present
          # If predicate is true, then presence check was successful, return true.
          predicate
        rescue Floe::PathError
          # variable_value is not present. (the path lookup threw an error)
          # If predicate is false, then it successfully wasn't present, return true.
          !predicate
        end

        # rubocop:disable Naming/PredicateName
        # rubocop:disable Style/OptionalBooleanParameter
        def is_null?(value, predicate = true)
          value.nil? == predicate
        end

        def is_present?(value, predicate = true)
          !value.nil? == predicate
        end

        def is_numeric?(value, predicate = true)
          value.kind_of?(Numeric) == predicate
        end

        def is_string?(value, predicate = true)
          value.kind_of?(String) == predicate
        end

        def is_boolean?(value, predicate = true)
          [true, false].include?(value) == predicate
        end

        def is_timestamp?(value, predicate = true)
          require "date"

          DateTime.rfc3339(value)
          predicate
        rescue TypeError, Date::Error
          !predicate
        end
        # rubocop:enable Naming/PredicateName
        # rubocop:enable Style/OptionalBooleanParameter

        def equals?(lhs, rhs)
          lhs == rhs
        end

        def lessthan?(lhs, rhs)
          lhs < rhs
        end

        def greaterthan?(lhs, rhs)
          lhs > rhs
        end

        def lessthanequals?(lhs, rhs)
          lhs <= rhs
        end

        def greaterthanequals?(lhs, rhs)
          lhs >= rhs
        end

        def matches?(lhs, rhs)
          lhs.match?(Regexp.escape(rhs).gsub('\*', '.*?'))
        end

        # parse the compare key at initialization time
        def parse_compare_key
          payload.each_key do |key|
            # e.g. (String)(GreaterThan)(Path)
            if (match_values = OPERATION.match(key))
              @compare_key = key
              @type, operator, @path = match_values.captures
              @operation = "#{operator.downcase}?".to_sym
              @compare_predicate = parse_predicate(type)
              break
            end
            # e.g. (Is)(String)
            if (match_value = TYPE_CHECK.match(key))
              @compare_key = key
              _operator, type = match_value.captures
              # type: nil means no runtime type checking.
              @type = @path = nil
              @operation = "is_#{type.downcase}?".to_sym
              @compare_predicate = parse_predicate("Boolean")
              break
            end
          end
          parser_error!("requires a compare key") if compare_key.nil? || operation.nil?
        end

        # parse predicate at initilization time
        # @return the right predicate attached to the compare key
        def parse_predicate(data_type)
          path ? parse_path(compare_key) : parse_field(compare_key, data_type)
        end

        # @return right hand predicate - input path or static payload value)
        def compare_value(context, input)
          path ? fetch_path(compare_key, compare_predicate, context, input) : compare_predicate
        end

        # feth the variable value at runtime
        # @return variable value (left hand side )
        def variable_value(context, input)
          fetch_path("Variable", variable, context, input)
        end

        # parse path at initilization time
        # helper method to parse a path from the payload
        def parse_path(field_name)
          value = payload[field_name]
          missing_field_error!(field_name) unless value
          wrap_parser_error(field_name, value) { Path.new(value) }
        end

        # parse predicate field at initialization time
        def parse_field(field_name, data_type)
          value = payload[field_name]
          return value if correct_type?(value, data_type)

          invalid_field_error!(field_name, value, "required to be a #{data_type}")
        end

        # fetch a path at runtime
        def fetch_path(field_name, field_path, context, input)
          value = field_path.value(context, input)
          return value if type.nil? || correct_type?(value, type)

          runtime_field_error!(field_name, field_path.to_s, "required to point to a #{type}")
        end

        # if we have runtime checking, check against that type
        #   otherwise assume checking a TYPE_CHECK predicate and check against Boolean
        def correct_type?(value, data_type)
          send("is_#{data_type.downcase}?".to_sym, value)
        end
      end
    end
  end
end
