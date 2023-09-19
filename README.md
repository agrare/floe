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
A different runner can be specified with the `--docker-runner` option:

```
bundle exec ruby exe/floe --workflow examples/workflow.asl --inputs='{"foo": 1}' --docker-runner podman
bundle exec ruby exe/floe --workflow examples/workflow.asl --inputs='{"foo": 1}' --docker-runner kubernetes --docker-runner-options namespace=default server=https://k8s.example.com:6443 token=my-token
```

If your workflow has `Credentials` you can provide a payload that will help resolve those credentials references at runtime.

For example if your workflow had the following Credentials field with a JSON Path property:
```json
"Credentials": {
  "RoleArn.$": "$.roleArn"
}
```

You can provide that at runtime via the `--credentials` parameter:

```
bundle exec ruby exe/floe --workflow my-workflow.asl --credentials='{"roleArn": "arn:aws:iam::111122223333:role/LambdaRole"}'
```

### Ruby Library

```ruby
require 'floe'

workflow = Floe::Workflow.load("workflow.asl")
workflow.run!
```

You can also specify a specific docker runner and runner options:
```ruby
require 'floe'

Floe::Workflow::Runner.docker_runner = Floe::Workflow::Runner::Podman.new
# Or
Floe::Workflow::Runner.docker_runner = Floe::Workflow::Runner::Kubernetes.new("namespace" => "default", "server" => "https://k8s.example.com:6443", "token" => "my-token")

workflow = Floe::Workflow.load("workflow.asl")
workflow.run!
```

### Non-Blocking Workflow Execution

It is also possible to step through a workflow without blocking, and any state which
would block will return `Errno::EAGAIN`.

```ruby
require 'floe'

workflow = Floe::Workflow.load("workflow.asl")

# Step through the workflow while it would not block
workflow.run_nonblock

# Go off and do some other task

# Continue stepping until the workflow is finished
workflow.run_nonblock
```

You can also use the `Floe::Workflow.wait` class method to wait on multiple workflows
and return all that are ready to be stepped through.

```ruby
require 'floe'

workflow1 = Floe::Workflow.load("workflow1.asl")
workflow2 = Floe::Workflow.load("workflow2.asl")

running_workflows = [workflow1, workflow2]
until running_workflows.empty?
  # run the states in each of the workflows that will not block
  ready_workflows.each(&:run_nonblock)
  # Remove any finished workflows from the list of running_workflows
  running_workflows.reject!(&:end?)
  # if there is more work to do, give the cpu a rest.
  sleep(1) unless running_workflows.empty?
end
```

### Docker Runner Options

#### Docker

Options supported by the Docker docker runner are:

* `network` - What docker to connect the container to, defaults to `"bridge"`.  If you need access to host resources for development you can pass `network=host`.

#### Podman

Options supported by the podman docker runner are:

* `identity=string` - path to SSH identity file, (CONTAINER_SSHKEY)
* `log-level=string` - Log messages above specified level (trace, debug, info, warn, warning, error, fatal, panic)
* `network=string` - What docker to connect the container to, defaults to `"bridge"`.  If you need access to host resources for development you can pass `network=host`.
* `noout=boolean` - do not output to stdout
* `root=string` - Path to the root directory in which data, including images, is stored
* `runroot=string` - Path to the 'run directory' where all state information is stored
* `runtime=string` - Path to the OCI-compatible binary used to run containers
* `runtime-flag=stringArray` - add global flags for the container runtime
* `storage-driver=string` - Select which storage driver is used to manage storage of images and containers
* `storage-opt=stringArray` - Used to pass an option to the storage driver
* `syslog=boolean` - Output logging information to syslog as well as the console
* `tmpdir=string` - Path to the tmp directory for libpod state content
* `transient-store=boolean` - Enable transient container storage
* `volumepath=string` - Path to the volume directory in which volume data is stored

#### Kubernetes

Options supported by the kubernetes docker runner are:

* `kubeconfig` - Path to a kubeconfig file, defaults to `KUBECONFIG` environment variable or `~/.kube/config`
* `kubeconfig_context` - Context to use in the kubeconfig file, defaults to `"default"`
* `namespace` - Namespace to use when creating kubernetes resources, defaults to `"default"`
* `server` - A kubernetes API Server URL, overrides anything in your kubeconfig file.  If set `KUBERNETES_SERVICE_HOST` and `KUBERNETES_SERVICE_PORT` will be used
* `token` - A bearer_token to use to authenticate to the kubernetes API, overrides anything in your kubeconfig file.  If present, `/run/secrets/kubernetes.io/serviceaccount/token` will be used
* `ca_file` - Path to a certificate-authority file for the kubernetes API, only valid if server and token are passed.  If present `/run/secrets/kubernetes.io/serviceaccount/ca.crt` will be used
* `verify_ssl` - Controls if the kubernetes API certificate-authority should be verified, defaults to "true", only vaild if server and token are passed

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ManageIQ/floe.
