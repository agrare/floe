# Floe

[![CI](https://github.com/ManageIQ/floe/actions/workflows/ci.yaml/badge.svg)](https://github.com/ManageIQ/floe/actions/workflows/ci.yaml)
[![Code Climate](https://codeclimate.com/github/ManageIQ/floe.svg)](https://codeclimate.com/github/ManageIQ/floe)
[![Test Coverage](https://codeclimate.com/github/ManageIQ/floe/badges/coverage.svg)](https://codeclimate.com/github/ManageIQ/floe/coverage)

## Overview

Floe is a runner for [Amazon States Language](https://states-language.net/) workflows with support for Docker resources and running on Docker, Podman, or Kubernetes.

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add floe

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install floe

## Usage

Floe can be run as a command-line utility or as a ruby class.

### Command Line

```
bundle exec ruby exe/floe --workflow examples/workflow.asl --inputs='{"foo": 1}'
```

By default Floe will use `docker` to run `docker://` type resources, but `podman` and `kubernetes` are also supported runners.
A different runner can be specified with the `--runner` option:

```
bundle exec ruby exe/floe --workflow examples/workflow.asl --inputs='{"foo": 1}' --docker_runner podman
bundle exec ruby exe/floe --workflow examples/workflow.asl --inputs='{"foo": 1}' --docker_runner kubernetes --docker_runner-options namespace=default server=https://k8s.example.com:6443 token=my-token
```

### Ruby Library

```ruby
require 'floe'

workflow = Floe::Workflow.load(File.read("workflow.asl"))
workflow.run!
```

You can also specify a specific docker runner and runner options:
```ruby
require 'floe'

Floe::Workflow::Runner.docker_runner = Floe::Workflow::Runner::Podman.new
# Or
Floe::Workflow::Runner.docker_runner = Floe::Workflow::Runner::Kubernetes.new("namespace" => "default", "server" => "https://k8s.example.com:6443", "token" => "my-token")

workflow = Floe::Workflow.load(File.read("workflow.asl"))
workflow.run!
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ManageIQ/floe.
