# frozen_string_literal: true

require_relative "floe/version"

require_relative "floe/null_logger"
require_relative "floe/logging"

require_relative "floe/runner"

require_relative "floe/workflow"
require_relative "floe/workflow/catcher"
require_relative "floe/workflow/choice_rule"
require_relative "floe/workflow/choice_rule/not"
require_relative "floe/workflow/choice_rule/or"
require_relative "floe/workflow/choice_rule/and"
require_relative "floe/workflow/choice_rule/data"
require_relative "floe/workflow/context"
require_relative "floe/workflow/path"
require_relative "floe/workflow/payload_template"
require_relative "floe/workflow/reference_path"
require_relative "floe/workflow/retrier"
require_relative "floe/workflow/state"
require_relative "floe/workflow/states/choice"
require_relative "floe/workflow/states/fail"
require_relative "floe/workflow/states/input_output_mixin"
require_relative "floe/workflow/states/map"
require_relative "floe/workflow/states/non_terminal_mixin"
require_relative "floe/workflow/states/parallel"
require_relative "floe/workflow/states/pass"
require_relative "floe/workflow/states/succeed"
require_relative "floe/workflow/states/task"
require_relative "floe/workflow/states/wait"

require "jsonpath"
require "time"

module Floe
  class Error < StandardError; end
  class InvalidWorkflowError < Error; end
  class InvalidExecutionInput < Error; end

  def self.logger
    @logger ||= NullLogger.new
  end

  # Set the logger to use
  #
  # @example
  #   require "logger"
  #   Floe.logger = Logger.new($stdout)
  #
  # @param logger [Logger] logger to use for logging actions
  def self.logger=(logger)
    @logger = logger
  end
end
