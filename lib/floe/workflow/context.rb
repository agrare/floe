# frozen_string_literal: true

module Floe
  class Workflow
    class Context
      def initialize(context = nil, input: {})
        context = JSON.parse(context) if context.kind_of?(String)

        @context = context || {
          "Execution"    => {
            "Input" => input
          },
          "State"        => {},
          "StateHistory" => [],
          "StateMachine" => {},
          "Task"         => {}
        }
      end

      def execution
        @context["Execution"]
      end

      def started?
        execution.key?("StartTime")
      end

      def running?
        started? && !ended?
      end

      def ended?
        execution.key?("EndTime")
      end

      def state
        @context["State"]
      end

      def state_started?
        state.key?("EnteredTime")
      end

      def state_finished?
        state.key?("FinishedTime")
      end

      # rename - kept name to explain
      def step_nonblock_start
        start_time = Time.now.utc

        execution["StartTime"] ||= start_time
        state["Guid"]            = SecureRandom.uuid
        state["EnteredTime"]     = start_time

      end

      # rename - kept name to explain
      def step_nonblock_finish
        state["FinishedTime"] ||= Time.now.utc
        state["Duration"]    = state["FinishedTime"] - state["EnteredTime"]
        execution["EndTime"] = Time.now.utc if next_state.nil?

        state_history << state

        state = {"Name" => next_state, "Input" => output} if next_state
      end

      def input
        state["Input"]
      end

      def output
        state["Output"]
      end

      def output=(val)
        state["Output"] = val
      end

      def state_name
        state["Name"]
      end

      def next_state
        state["NextState"]
      end

      def next_state=(val)
        state["NextState"] = val
      end

      def status
        if !started?
          "pending"
        elsif running?
          "running"
        elsif state["Error"]
          "failure"
        else
          "success"
        end
      end

      def state=(val)
        @context["State"] = val
      end

      def state_history
        @context["StateHistory"]
      end

      def state_machine
        @context["StateMachine"]
      end

      def task
        @context["Task"]
      end

      def [](key)
        @context[key]
      end

      def []=(key, val)
        @context[key] = val
      end

      def dig(*args)
        @context.dig(*args)
      end

      def to_h
        @context
      end
    end
  end
end
