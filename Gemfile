# frozen_string_literal: true

source "https://rubygems.org"

plugin "bundler-inject", "~> 2.0"
require File.join(Bundler::Plugin.index.load_paths("bundler-inject")[0], "bundler-inject") rescue nil # rubocop:disable Style/RescueModifier

# Specify your gem's dependencies in floe.gemspec
gemspec

# JSONata support is optional and requires Ruby >= 3.1.
# The jsonata gem is not yet published to rubygems.
gem "jsonata", :git => "https://github.com/Fryguy/jsonata-rb", :install_if => -> { RUBY_VERSION >= "3.1" }
