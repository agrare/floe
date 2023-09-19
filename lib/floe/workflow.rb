# frozen_string_literal: true

require "securerandom"
require "json"

module Floe
  class Workflow
    include Logging

    class << self
      def load(path_or_io, context = nil, credentials = {})
        payload = path_or_io.respond_to?(:read) ? path_or_io.read : File.read(path_or_io)
        new(payload, context, credentials)
      end
    end

    attr_reader :context, :credentials, :payload, :states, :states_by_name, :start_at

    def initialize(payload, context = nil, credentials = {})
      payload     = JSON.parse(payload)     if payload.kind_of?(String)
      credentials = JSON.parse(credentials) if credentials.kind_of?(String)
      context     = Context.new(context)    unless context.kind_of?(Context)

      @payload     = payload
      @context     = context
      @credentials = credentials
      @start_at    = payload["StartAt"]

      @states         = payload["States"].to_a.map { |name, state| State.build!(self, name, state) }
      @states_by_name = @states.each_with_object({}) { |state, result| result[state.name] = state }

      unless context.state.key?("Name")
        context.state["Name"] = start_at
        context.state["Input"]     = context.execution["Input"].dup
      end
    rescue JSON::ParserError => err
      raise Floe::InvalidWorkflowError, err.message
    end

    def run!(timeout: :forever)

      while !end? && step(:timeout => timeout) == 0 
      end

      self
    end

    def step(timeout: :forever)
      return Errno::EPERM if end?

      loop do
        logger.info("Running state: [#{context.state_name}] with input [#{context.input}]...") unless context.state_started?
        ret = current_state.run_nonblock!

        # if this step is blocked
        if ret == Errno::EAGAIN
          # if we are not going forever
          # and we have no timeout or our timeout has passed
          # then return
          if timeout != :forever && (timeout.zero? || Time.now.utc - start > timeout)
            return Errno::EAGAIN
          else
            sleep(1)
          end
        else
          return 0
        end
      end
    end

    # drop
    def run_nonblock
      run!(:timeout => 0)
    end

    # drop?
    def step_nonblock
      step(:timeout => 0)
    end

    # drop?
    def step_nonblock_wait(timeout: 5)
      step(:timeout => timeout)
    end

    # drop?
    def step_nonblock_ready?
      current_state.step_nonblock_ready?
    end

    def status
      context.status
    end

    def output
      context.output
    end

    def end?
      context.ended?
    end

    # currently, only used for stubbing in tests
    def current_state
      @states_by_name[context.state_name]
    end
  end
end
