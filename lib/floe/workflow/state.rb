# frozen_string_literal: true

module Floe
  class Workflow
    class State
      include Logging

      class << self
        def build!(workflow, name, payload)
          state_type = payload["Type"]

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
      end

      def run_nonblock!
        unless started?
          context.step_nonblock_start
          start(context.input)
        end

        return Errno::EAGAIN if running?

        finish

        0
      end

      def run!(timeout: :forever)
        start = Time.now.utc

        while run_nonblock! == Errno::EAGAIN
          return Errno::EAGAIN if timeout != :forever && (timeout.zero? || Time.now.utc - start > timeout)
          sleep(1)
        end

        0
      end

      def start(_input)
        raise NotImpelmentedError
      end

      def finish
        context.step_nonblock_finish
      end

      def context
        workflow.context
      end

      def started?
        context.state_started?
      end

      def finished?
        context.state_finished?
      end

      # drop?
      def step_nonblock_ready?
        !started? || !running?
      end
    end
  end
end
