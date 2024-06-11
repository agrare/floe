# frozen_string_literal: true

require "securerandom"
require "json"

module Floe
  class Workflow
    include Logging

    class << self
      def load(path_or_io, context = nil, credentials = {}, name = nil)
        payload = path_or_io.respond_to?(:read) ? path_or_io.read : File.read(path_or_io)
        # default the name if it is a filename and none was passed in
        name ||= path_or_io.respond_to?(:read) ? "stream" : path_or_io.split("/").last.split(".").first

        new(payload, context, credentials, name)
      end

      def wait(workflows, timeout: nil, &block)
        workflows = [workflows] if workflows.kind_of?(self)
        logger.info("checking #{workflows.count} workflows...")

        run_until   = Time.now.utc + timeout if timeout.to_i > 0
        ready       = []
        queue       = Queue.new
        wait_thread = Thread.new do
          loop do
            Runner.for_resource("docker").wait do |event, runner_context|
              queue.push([event, runner_context])
            end
          end
        end

        loop do
          ready = workflows.select(&:step_nonblock_ready?)
          break if block.nil? && !ready.empty?

          ready.each(&block)

          # Break if all workflows are completed or we've exceeded the
          # requested timeout
          break if workflows.all?(&:end?)
          break if timeout && (timeout.zero? || Time.now.utc > run_until)

          # Find the earliest time that we should wakeup if no container events
          # are caught, either a workflow in a Wait or Retry state or we've
          # exceeded the requested timeout
          wait_until = workflows.map(&:wait_until)
                                .unshift(run_until)
                                .compact
                                .min

          # If a workflow is in a waiting state wakeup the main thread when
          # it will be done sleeping
          if wait_until
            sleep_thread = Thread.new do
              sleep_duration = wait_until - Time.now.utc
              sleep sleep_duration if sleep_duration > 0
              queue.push(nil)
            end
          end

          loop do
            # Block until an event is raised
            event, runner_context = queue.pop
            break if event.nil?

            # If the event is for one of our workflows set the updated runner_context
            workflows.each do |workflow|
              next unless workflow.context.state.dig("RunnerContext", "container_ref") == runner_context["container_ref"]

              workflow.context.state["RunnerContext"] = runner_context
            end

            break if queue.empty?
          end
        ensure
          sleep_thread&.kill
        end

        logger.info("checking #{workflows.count} workflows...Complete - #{ready.count} ready")
        ready
      ensure
        wait_thread&.kill
      end
    end

    attr_reader :context, :credentials, :payload, :states, :states_by_name, :start_at, :name, :comment

    def initialize(payload, context = nil, credentials = {}, name = nil)
      payload     = JSON.parse(payload)     if payload.kind_of?(String)
      credentials = JSON.parse(credentials) if credentials.kind_of?(String)
      context     = Context.new(context)    unless context.kind_of?(Context)

      raise Floe::InvalidWorkflowError, "Missing field \"States\""  if payload["States"].nil?
      raise Floe::InvalidWorkflowError, "Missing field \"StartAt\"" if payload["StartAt"].nil?
      raise Floe::InvalidWorkflowError, "\"StartAt\" not in the \"States\" field" unless payload["States"].key?(payload["StartAt"])

      @name        = name
      @payload     = payload
      @context     = context
      @credentials = credentials || {}
      @comment     = payload["Comment"]
      @start_at    = payload["StartAt"]

      @states         = payload["States"].to_a.map { |state_name, state| State.build!(self, state_name, state) }
      @states_by_name = @states.each_with_object({}) { |state, result| result[state.name] = state }
    rescue => err
      raise Floe::InvalidWorkflowError, err.message
    end

    def run_nonblock
      start_workflow
      loop while step_nonblock == 0 && !end?
      self
    end

    # NOTE: If running manually, make sure to call start_workflow at startup
    def step_nonblock
      return Errno::EPERM if end?

      result = current_state.run_nonblock!

      # if it completed the step
      if result == 0
        context.state_history << context.state
        if context.next_state.nil?
          end_workflow
        else
          step_next
        end
      end

      result
    end

    # if this hasn't started (and we have no current_state yet), assume it is ready
    def step_nonblock_wait(timeout: nil)
      context.started? ? current_state.wait(:timeout => timeout) : 0
    end

    # if this hasn't started (and we have no current_state yet), assume it is ready
    def step_nonblock_ready?
      !context.started? || current_state.ready?
    end

    def waiting?
      current_state.waiting?
    end

    def wait_until
      current_state.wait_until
    end

    def status
      context.status
    end

    def output
      context.output if end?
    end

    def end?
      context.ended?
    end

    # setup a workflow
    def start_workflow
      return if context.state_name

      context.state["Name"] = start_at
      context.state["Input"] = context.execution["Input"].dup
      context.execution["StartTime"] = Time.now.utc.iso8601

      self
    end

    # Avoiding State#running? because that is potentially expensive.
    # State#run_nonblock! already called running? via State#ready? and
    # called State#finished -- which is what Context#state_finished? is detecting
    def end_workflow
      context.execution["EndTime"] = context.state["FinishedTime"]
    end

    # NOTE: Expecting the context to be initialized (via start_workflow) before this
    def current_state
      @states_by_name[context.state_name]
    end

    private

    def step_next
      next_state = {"Name" => context.next_state}

      # if rerunning due to an error (and we are using Retry)
      if context.state_name == context.next_state && context.failed? && context.state.key?("Retrier")
        next_state.merge!(context.state.slice("RetryCount", "Input", "Retrier"))
      else
        next_state["Input"] = context.output
      end

      context.state = next_state
    end
  end
end
