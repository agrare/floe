# frozen_string_literal: true

module Floe
  class WorkflowBase
    include ValidationMixin

    QUERY_LANGUAGES = %w[JSONPath JSONata].freeze

    attr_reader :name, :payload, :start_at, :states, :states_by_name, :query_language

    # @param query_language [String] the query language inherited from a parent workflow (default: JSONPath)
    def initialize(payload, name = nil, query_language: nil)
      # NOTE: this is a string, and states use an array
      @name     = name || "State Machine"
      @payload  = payload
      @start_at = payload["StartAt"]

      @query_language = payload["QueryLanguage"] || query_language || "JSONPath"
      validate_query_language!

      # NOTE: Everywhere else we include our name (i.e.: parent name) when building the child name.
      #       When creating the states, we are dropping our name (i.e.: the workflow name)
      @states         = payload["States"].to_a.map { |state_name, state| Floe::Workflow::State.build!(self, ["States", state_name], state) }
      @states_by_name = @states.to_h { |state| [state.short_name, state] }

      validate_workflow!
    end

    def run(context)
      run_nonblock(context) until context.ended?
    end

    def run_nonblock(context)
      start_workflow(context)
      loop while step_nonblock(context) == 0 && !context.ended?
      self
    end

    def step_nonblock(context)
      return Errno::EPERM if context.ended?

      result = current_state(context).run_nonblock!(context)
      return result if result != 0

      context.state_history << context.state
      context.next_state ? step!(context) : end_workflow!(context)

      result
    end

    def step_nonblock_ready?(context)
      !context.started? || current_state(context).ready?(context)
    end

    def waiting?(context)
      current_state(context)&.waiting?(context)
    end

    def wait_until(context)
      current_state(context)&.wait_until(context)
    end

    def start_workflow(context)
      return if context.state_name

      context.state["Name"]  = start_at
      context.state["Input"] = context.execution["Input"].dup

      context.execution["StartTime"] = Time.now.utc.iso8601

      self
    end

    def current_state(context)
      states_by_name[context.state_name]
    end

    def end?(context)
      context.ended?
    end

    def output(context)
      context.output.to_json if end?(context)
    end

    def state?(state_name)
      @payload["States"].include?(state_name)
    end

    private

    def step!(context)
      next_state = {"Name" => context.next_state}

      # if rerunning due to an error (and we are using Retry)
      if context.state_name == context.next_state && context.failed? && context.state.key?("Retrier")
        next_state.merge!(context.state.slice("RetryCount", "Input", "Retrier"))
      else
        next_state["Input"] = context.output
      end

      context.state = next_state
    end

    # Avoiding State#running? because that is potentially expensive.
    # State#run_nonblock! already called running? via State#ready? and
    # called State#finished -- which is what Context#state_finished? is detecting
    def end_workflow!(context)
      context.execution["EndTime"] = context.state["FinishedTime"]
    end

    def validate_query_language!
      return if QUERY_LANGUAGES.include?(@query_language)

      invalid_field_error!("QueryLanguage", @query_language, "must be one of #{QUERY_LANGUAGES.map { |l| "\"#{l}\"" }.join(", ")}")
    end

    def validate_workflow!
      missing_field_error!("States") if @states.empty?
      missing_field_error!("StartAt") if @start_at.nil?
      invalid_field_error!("StartAt", @start_at, "is not found in \"States\"") unless state?(@start_at)
    end
  end
end
