# frozen_string_literal: true

module Floe
  module Logging
    def self.included(base)
      base.extend(self)
    end

    def logger
      @logger || Floe.logger
    end

    def logger=(logger)
      @logger = logger
    end
  end
end
