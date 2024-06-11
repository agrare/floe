# frozen_string_literal: true

module Floe
  class Workflow
    class State
      include Logging

      class << self
        def build!(workflow, name, payload)
          state_type = payload["Type"]
          raise Floe::InvalidWorkflowError, "Missing \"Type\" field in state [#{name}]" if payload["Type"].nil?

          begin
            klass = Floe::Workflow::States.const_get(state_type)
          rescue NameError
            raise Floe::InvalidWorkflowError, "Invalid state type: [#{state_type}]"
          end

          klass.new(workflow, name, payload)
        end
      end

      attr_reader :workflow, :comment, :name, :type, :payload

      def initialize(workflow, name, payload)
        @workflow = workflow
        @name     = name
        @payload  = payload
        @type     = payload["Type"]
        @comment  = payload["Comment"]

        raise Floe::InvalidWorkflowError, "Missing \"Type\" field in state [#{name}]" if payload["Type"].nil?
        raise Floe::InvalidWorkflowError, "State name [#{name}] must be less than or equal to 80 characters" if name.length > 80
      end

      def wait(timeout: nil)
        start = Time.now.utc

        loop do
          return 0             if ready?
          return Errno::EAGAIN if timeout && (timeout.zero? || Time.now.utc - start > timeout)

          sleep(1)
        end
      end

      # @return for incomplete Errno::EAGAIN, for completed 0
      def run_nonblock!
        start(context.input) unless started?
        return Errno::EAGAIN unless ready?

        finish
      end

      def start(_input)
        context.state["Guid"]        = SecureRandom.uuid
        context.state["EnteredTime"] = Time.now.utc.iso8601

        logger.info("Running state: [#{long_name}] with input [#{context.input}]...")
      end

      def finish
        finished_time     = Time.now.utc
        entered_time      = Time.parse(context.state["EnteredTime"])

        context.state["FinishedTime"] ||= finished_time.iso8601
        context.state["Duration"]       = finished_time - entered_time

        level = context.output&.[]("Error") ? :error : :info
        logger.public_send(level, "Running state: [#{long_name}] with input [#{context.input}]...Complete #{context.next_state ? "- next state [#{context.next_state}]" : "workflow -"} output: [#{context.output}]")

        0
      end

      def context
        workflow.context
      end

      def started?
        context.state_started?
      end

      def ready?
        !started? || !running?
      end

      def finished?
        context.state_finished?
      end

      def waiting?
        context.state["WaitUntil"] && Time.now.utc <= Time.parse(context.state["WaitUntil"])
      end

      def wait_until
        context.state["WaitUntil"] && Time.parse(context.state["WaitUntil"])
      end

      def long_name
        "#{payload["Type"]}:#{name}"
      end

      private

      def wait_until!(seconds: nil, time: nil)
        context.state["WaitUntil"] =
          if seconds
            (Time.parse(context.state["EnteredTime"]) + seconds).iso8601
          elsif time.kind_of?(String)
            time
          else
            time.iso8601
          end
      end
    end
  end
end
