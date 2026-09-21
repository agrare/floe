# frozen_string_literal: true

require "securerandom"

module Floe
  class Workflow
    class Context
      include Logging

      # @param context [Json|Hash] (default, create another with input and execution params)
      # @param input [Json] (default: '{}')
      def initialize(context = nil, input: nil, credentials: nil, logger: nil)
        context = JSON.parse(context) if context.kind_of?(String)

        @context = context || {}
        self["Credentials"]        ||= credentials || {}
        self["Execution"]          ||= {}
        self["Execution"]["Input"] ||= JSON.parse(input || "{}")
        self["State"]              ||= {}
        self["StateHistory"]       ||= []
        self["StateMachine"]       ||= {}
        self["Task"]               ||= {}

        self.logger = logger if logger
      rescue JSON::ParserError => err
        raise Floe::InvalidExecutionInput, "Invalid State Machine Execution Input: #{err}: was expecting (JSON String, Number, Array, Object or token 'null', 'true' or 'false')"
      end

      def prepare_start(start_at, timeout_seconds: nil)
        return if started?

        state["Name"]  = start_at
        state["Input"] = execution["Input"].dup
        state["Guid"]  = SecureRandom.uuid

        execution["Id"]      ||= SecureRandom.uuid
        execution["StartTime"] = Time.now.utc.iso8601
        execution["TimeoutAt"] = (Time.now.utc + timeout_seconds).iso8601 if timeout_seconds

        if logger.respond_to?(:execution_id=)
          logger.execution_id = execution["Id"]
        end
      end

      def execution
        @context["Execution"]
      end

      def execution_id
        execution["Id"]
      end

      def credentials
        @context["Credentials"]
      end

      def started?
        execution.key?("StartTime")
      end

      def running?
        started? && !ended?
      end

      def failed?
        (output.kind_of?(Hash) && output.key?("Error")) || false
      end

      def ended?
        execution.key?("EndTime")
      end

      def state
        @context["State"]
      end

      def input
        state["Input"]
      end

      def json_input
        input.to_json
      end

      def output
        state["Output"]
      end

      def json_output
        output.to_json
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
        elsif failed?
          "failure"
        else
          "success"
        end
      end

      def success?
        status == "success"
      end

      def state_started?
        state.key?("EnteredTime")
      end

      # State#running? also checks docker to see if it is running.
      # You possibly want to use that instead
      def state_finished?
        state.key?("FinishedTime")
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

      def child_context(input)
        require "active_support/core_ext/object/deep_dup"

        # Copy the Execution context minus any keys which are set at runtime.
        # This allows any user defined state-machine execution values be used
        # by child workflows.
        #
        # The deep_dup is important here, otherwise the Execution hash object is
        # shared between all child workflows.
        child_execution = execution
          .except("Input", "StartTime", "EndTime")
          .deep_dup
          .merge("Input" => input)

        self.class.new({"Execution" => child_execution})
      end

      def inspect
        "#<#{self.class.name}: #{safe_context.inspect}>"
      end

      def to_h
        safe_context
      end

      def ==(other)
        other.kind_of?(self.class) && other.instance_variable_get(:@context) == @context
      end
      alias eql? ==

      def hash
        @context.hash
      end

      private

      def safe_context
        @context.except("Credentials")
      end
    end
  end
end
