# frozen_string_literal: true

module Floe
  class Workflow
    class State
      include ValidationMixin

      class << self
        def build!(workflow, name, payload)
          state_type = payload["Type"]
          missing_field_error!(name, "Type") if payload["Type"].nil?
          invalid_field_error!(name[0..-2], "Name", name.last, "must be less than or equal to 80 characters") if name.last.length > 80

          begin
            klass = Floe::Workflow::States.const_get(state_type)
          rescue NameError
            invalid_field_error!(name, "Type", state_type, "is not valid")
          end

          klass.new(workflow, name, payload)
        end
      end

      attr_reader :comment, :name, :type, :payload

      def initialize(_workflow, name, payload)
        @name     = name
        @payload  = payload
        @type     = payload["Type"]
        @comment  = payload["Comment"]
      end

      def wait(context, timeout: nil)
        start = Time.now.utc

        loop do
          return 0             if ready?(context)
          return Errno::EAGAIN if timeout && (timeout.zero? || Time.now.utc - start > timeout)

          sleep(1)
        end
      end

      # @return for incomplete Errno::EAGAIN, for completed 0
      def run_nonblock!(context)
        start(context) unless context.state_started?
        return Errno::EAGAIN unless ready?(context)

        finish(context)
      rescue Floe::ExecutionError => e
        mark_error(context, e)
      end

      def start(context)
        mark_started(context)
      end

      def finish(context)
        mark_finished(context)
      end

      def mark_started(context)
        context.state["EnteredTime"] = Time.now.utc.iso8601

        context.logger.info("Running state: [#{long_name}] with input [#{context.json_input}]...")
      end

      def mark_finished(context)
        finished_time = Time.now.utc
        entered_time  = Time.parse(context.state["EnteredTime"])

        context.state["FinishedTime"] ||= finished_time.iso8601
        context.state["Duration"]       = finished_time - entered_time

        level = context.failed? ? :error : :info
        context.logger.public_send(level, "Running state: [#{long_name}] with input [#{context.json_input}]...Complete #{context.next_state ? "- next state [#{context.next_state}]" : "workflow -"} output: [#{context.json_output}]")

        0
      end

      def mark_error(context, exception)
        # InputPath or OutputPath were bad.
        context.next_state = nil
        context.output     = {"Error" => exception.floe_error, "Cause" => exception.message}
        # Since finish threw an exception, super was never called. Calling that now.
        mark_finished(context)
      end

      def ready?(context)
        !context.state_started? || !running?(context)
      end

      def running?(context)
        raise NotImplementedError, "Must be implemented in a subclass"
      end

      def waiting?(context)
        context.state["WaitUntil"] && Time.now.utc <= Time.parse(context.state["WaitUntil"])
      end

      def wait_until(context)
        context.state["WaitUntil"] && Time.parse(context.state["WaitUntil"])
      end

      def short_name
        name.last
      end

      def long_name
        "#{type}:#{short_name}"
      end

      private

      def wait_until!(context, seconds: nil, time: nil)
        context.state["WaitUntil"] =
          if seconds
            (Time.now + seconds).iso8601
          elsif time.kind_of?(String)
            time
          else
            time.iso8601
          end
      end
    end
  end
end
