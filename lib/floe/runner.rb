# frozen_string_literal: true

module Floe
  class Runner
    OUTPUT_MARKER = "__FLOE_OUTPUT__\n"

    def initialize(_options = {}) # rubocop:disable Style/RedundantInitialize
    end

    @runners = {}
    class << self
      def register_scheme(scheme, klass_or_proc)
        @runners[scheme] = klass_or_proc
      end

      private def resolve_scheme(scheme)
        runner = @runners[scheme]
        runner = @runners[scheme] = @runners[scheme].call if runner.kind_of?(Proc)
        runner
      end

      def for_resource(resource)
        raise ArgumentError, "resource cannot be nil" if resource.nil?

        scheme = resource.split("://").first
        resolve_scheme(scheme) || raise(ArgumentError, "Invalid resource scheme [#{scheme}]")
      end
    end

    # Run a command asynchronously and create a runner_context
    # @return [Hash] runner_context
    def run_async!(_resource, _env = {}, _secrets = {}, _context = {})
      raise NotImplementedError, "Must be implemented in a subclass"
    end

    # update the runner_context
    # @param  [Hash] runner_context (the value returned from run_async!)
    # @return [void]
    def status!(_runner_context)
      raise NotImplementedError, "Must be implemented in a subclass"
    end

    # check runner_contet to determine if the task is still running or completed
    # @param  [Hash] runner_context (the value returned from run_async!)
    # @return [Boolean] value if the task is still running
    #   true if the task is still running
    #   false if it has completed
    def running?(_runner_context)
      raise NotImplementedError, "Must be implemented in a subclass"
    end

    # For a non-running? task, check if it was successful
    # @param  [Hash] runner_context (the value returned from run_async!)
    # @return [Boolean] value if the task is still running
    #   true if the task completed successfully
    #   false if the task had an error
    def success?(_runner_context)
      raise NotImplementedError, "Must be implemented in a subclass"
    end

    # For a successful task, return the output
    # @param  [Hash] runner_context (the value returned from run_async!)
    # @return [String, Hash] output from task
    def output(_runner_context)
      raise NotImplementedError, "Must be implemented in a subclass"
    end

    # Cleanup runner context resources
    # Called after a task is completed and the runner_context is no longer needed.
    # @param  [Hash] runner_context (the value returned from run_async!)
    # @return [void]
    def cleanup(_runner_context)
      raise NotImplementedError, "Must be implemented in a subclass"
    end

    # Optional Watcher for events that is run in another thread.
    #
    # @yield [event, runner_context]
    # @yieldparam [Symbol] event values: :create :update :delete :unknown
    # @yieldparam [Hash] runner_context context provided by runner
    # def wait(timeout: nil, events: %i[create update delete])
    #   raise NotImplementedError, "Must be implemented in a subclass"
    # end
  end
end
