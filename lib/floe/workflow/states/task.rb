# frozen_string_literal: true

module Floe
  class Workflow
    module States
      class Task < Floe::Workflow::State
        include InputOutputMixin
        include NonTerminalMixin
        include RetryCatchMixin

        # The default TimeoutSeconds when none is given, per the States Language specification
        DEFAULT_TIMEOUT_SECONDS = 60

        attr_reader :credentials, :end, :heartbeat_seconds, :next, :parameters,
                    :result_selector, :resource, :timeout_seconds, :timeout_seconds_path,
                    :retry, :catch, :input_path, :output_path, :result_path

        def initialize(workflow, name, payload)
          super

          @resource = payload["Resource"]
          missing_field_error!("Resource") unless @resource.kind_of?(String)
          @runner = wrap_parser_error("Resource", @resource) { Floe::Runner.for_resource(@resource) }

          @next                 = payload["Next"]
          @end                  = !!payload["End"]
          @timeout_seconds      = payload["TimeoutSeconds"]
          @heartbeat_seconds    = payload["HeartbeatSeconds"]
          @retry                = payload["Retry"].to_a.map.with_index { |retrier, i| Retrier.new(workflow, name + ["Retry", i.to_s], retrier) }
          @catch                = payload["Catch"].to_a.map.with_index { |catcher, i| Catcher.new(workflow, name + ["Catch", i.to_s], catcher) }
          @input_path           = Path.new(payload.fetch("InputPath", "$"))
          @output_path          = Path.new(payload.fetch("OutputPath", "$"))
          @result_path          = ReferencePath.new(payload.fetch("ResultPath", "$"))
          @timeout_seconds_path = ReferencePath.new(payload["TimeoutSecondsPath"]) if payload["TimeoutSecondsPath"]
          @parameters           = PayloadTemplate.new(payload["Parameters"])       if payload["Parameters"]
          @result_selector      = PayloadTemplate.new(payload["ResultSelector"])   if payload["ResultSelector"]
          @credentials          = PayloadTemplate.new(payload["Credentials"])      if payload["Credentials"]

          validate_state!(workflow)
        end

        def start(context)
          super

          set_timeout_at!(context)

          input          = process_input(context)
          secrets        = credentials&.value(context, context.input)
          runner_context = runner.run_async!(resource, input, secrets, context)

          context.state["RunnerContext"] = runner_context
        end

        def finish(context)
          output = runner.output(context.state["RunnerContext"])
          raise Floe::ExecutionError.from_output(parse_error(output)) unless success?(context)

          output = parse_output(output)
          context.output = process_output(context, output)

          super
        ensure
          runner.cleanup(context.state["RunnerContext"])
        end

        def running?(context)
          return false if finished?(context)

          runner.status!(context.state["RunnerContext"])
          runner.running?(context.state["RunnerContext"])
        end

        def mark_error(context, exception)
          error = exception.to_output

          retry_state!(context, error) || catch_error!(context, error) || fail_workflow!(context, error)
          mark_finished(context)
        end

        def end?
          @end
        end

        def timeout_at(context)
          workflow_timeout = super
          task_timeout     = context.state["TimeoutAt"] && Time.parse(context.state["TimeoutAt"])

          [workflow_timeout, task_timeout].compact.min
        end

        private

        def set_timeout_at!(context)
          entered_time = Time.parse(context.state["EnteredTime"])
          seconds      = timeout_seconds || (timeout_seconds_path ? timeout_seconds_path.value(context, context.input) : DEFAULT_TIMEOUT_SECONDS)
          raise Floe::PathError, "TimeoutSecondsPath references an invalid value [#{seconds}]" unless seconds.kind_of?(Integer) && seconds > 0

          context.state["TimeoutAt"] = (entered_time + seconds).iso8601
        end

        attr_reader :runner

        def validate_state!(workflow)
          validate_state_next!(workflow)
          validate_state_timeout_seconds!(workflow)
          validate_state_timeout_seconds_path!(workflow)
          validate_state_heartbeat_seconds!
          validate_state_retry_catch!
        end

        def validate_state_timeout_seconds!(workflow)
          return if @timeout_seconds.nil?
          return if @timeout_seconds.kind_of?(Integer) && @timeout_seconds > 0

          invalid_field_error!("TimeoutSeconds", @timeout_seconds, "must be positive, non-zero integer")
        end

        def validate_state_timeout_seconds_path!(workflow)
          return if @timeout_seconds_path.nil? || @timeout_seconds.nil?

          invalid_field_error!("TimeoutSecondsPath", nil, "cannot specify both \"TimeoutSeconds\" and \"TimeoutSecondsPath\"")
        end

        def validate_state_heartbeat_seconds!
          invalid_field_error!("HeartbeatSecondsPath", nil, "cannot specify both \"HeartbeatSeconds\" and \"HeartbeatSecondsPath\"") if @heartbeat_seconds && payload["HeartbeatSecondsPath"]
          return if @heartbeat_seconds.nil?

          invalid_field_error!("HeartbeatSeconds", @heartbeat_seconds, "must be positive, non-zero integer") unless @heartbeat_seconds.kind_of?(Integer) && @heartbeat_seconds > 0
          invalid_field_error!("HeartbeatSeconds", @heartbeat_seconds, "must be smaller than \"TimeoutSeconds\"") if @timeout_seconds && @heartbeat_seconds >= @timeout_seconds
        end

        def success?(context)
          runner.success?(context.state["RunnerContext"])
        end

        def parse_error(output)
          return if output.nil?
          return output if output.kind_of?(Hash)

          JSON.parse(output.split("\n").last)
        rescue JSON::ParserError
          {"Error" => output.chomp}
        end

        def parse_output(output)
          return output if output.kind_of?(Hash)
          return if output.nil? || output.empty?

          JSON.parse(output.split("\n").last)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
