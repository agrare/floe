# frozen_string_literal: true

require 'time'

module Floe
  class Workflow
    module States
      class Wait < Floe::Workflow::State
        include JsonataMixin
        include NonTerminalMixin

        attr_reader :end, :input_path, :next, :seconds, :seconds_path, :timestamp, :timestamp_path, :output_path

        def initialize(workflow, name, payload)
          super

          validate_query_language_fields!(
            :jsonpath_only => %w[InputPath OutputPath SecondsPath TimestampPath],
            :jsonata_only  => %w[Output Assign]
          )

          @next           = payload["Next"]
          @end            = !!payload["End"]

          if jsonata?
            @seconds   = parse_jsonata_value(payload["Seconds"])
            @timestamp = parse_jsonata_value(payload["Timestamp"])
            parse_jsonata_fields(payload)
          else
            @seconds        = payload["Seconds"]&.to_i
            @timestamp      = payload["Timestamp"]
            @timestamp_path = Path.new(payload["TimestampPath"]) if payload.key?("TimestampPath")
            @seconds_path   = Path.new(payload["SecondsPath"]) if payload.key?("SecondsPath")

            @input_path  = Path.new(payload.fetch("InputPath", "$"))
            @output_path = Path.new(payload.fetch("OutputPath", "$"))
          end

          validate_state!(workflow)
        end

        def start(context)
          super

          if jsonata?
            wait_until!(
              context,
              :seconds => jsonata_seconds(context),
              :time    => evaluate_jsonata_value(context, timestamp)
            )
          else
            input = input_path.value(context, context.input)

            wait_until!(
              context,
              :seconds => seconds_path ? seconds_path.value(context, input).to_i : seconds,
              :time    => timestamp_path ? timestamp_path.value(context, input) : timestamp
            )
          end
        end

        def finish(context)
          if jsonata?
            context.output = process_output_jsonata(context, context.input)
          else
            input          = input_path.value(context, context.input)
            context.output = output_path.value(context, input)
          end
          super
        end

        def running?(context)
          waiting?(context)
        end

        def end?
          @end
        end

        private

        def jsonata_seconds(context)
          value = evaluate_jsonata_value(context, seconds)
          return value if value.nil?

          runtime_field_error!("Seconds", value, "must be a non-negative number") unless value.kind_of?(Numeric) && !value.negative?

          value
        end

        def validate_state!(workflow)
          validate_state_next!(workflow)
        end
      end
    end
  end
end
