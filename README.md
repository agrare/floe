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

Or if you are running the floe command programmatically you can securely provide the credentials via a stdin pipe via `--credentials=-`:
```
echo '{"roleArn": "arn:aws:iam::111122223333:role/LambdaRole"}' | bundle exec ruby exe/floe --workflow my-workflow.asl --credentials -
```

Or you can pass a file path with the `--credentials-file` parameter:
```
bundle exec ruby exe/floe --workflow my-workflow.asl --credentials-file /tmp/20231218-80537-kj494t
```

If you need to set a credential at runtime you can do that by using the `"ResultPath": "$.Credentials"` directive, for example to user a username/password to login and get a Bearer token:

```
bundle exec ruby exe/floe --workflow my-workflow.asl --credentials='{"username": "user", "password": "pass"}'
```

```json
{
  "StartAt": "Login",
  "States": {
    "Login": {
      "Type": "Task",
      "Resource": "docker://login:latest",
      "Credentials": {
        "username.$": "$.username",
        "password.$": "$.password"
      },
      "ResultPath": "$.Credentials",
      "Next": "DoSomething"
    },
    "DoSomething": {
      "Type": "Task",
      "Resource": "docker://do-something:latest",
      "Credentials": {
        "token.$": "$.bearer_token"
      },
      "End": true
    }
  }
}
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
  # Wait for any of the running workflows to be ready (up to the timeout)
  ready_workflows = Floe::Workflow.wait(running_workflows)
  # Step through the ready workflows until they would block
  ready_workflows.each do |workflow|
    workflow.run_nonblock
  end
  # Remove any finished workflows from the list of running_workflows
  running_workflows.reject!(&:end?)
end
```

### Docker Runner Options

#### Docker

Options supported by the Docker docker runner are:

* `network` - What docker to connect the container to, defaults to `"bridge"`.  If you need access to host resources for development you can pass `network=host`.
* `pull-policy` - Pull image policy. The default is missing.  Allowed values: always, missing, never

#### Podman

Options supported by the podman docker runner are:

* `identity=string` - path to SSH identity file, (CONTAINER_SSHKEY)
* `log-level=string` - Log messages above specified level (trace, debug, info, warn, warning, error, fatal, panic)
* `network=string` - What docker to connect the container to, defaults to `"bridge"`.  If you need access to host resources for development you can pass `network=host`.
* `noout=boolean` - do not output to stdout
* `pull-policy=string` - Pull image policy. The default is missing. Allowed values: always, missing, never, newer
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
* `pull-policy` - Pull image policy. The default is Always.  Allowed values: IfNotPresent, Always, Never
* `server` - A kubernetes API Server URL, overrides anything in your kubeconfig file.  If set `KUBERNETES_SERVICE_HOST` and `KUBERNETES_SERVICE_PORT` will be used
* `token` - A bearer_token to use to authenticate to the kubernetes API, overrides anything in your kubeconfig file.  If present, `/run/secrets/kubernetes.io/serviceaccount/token` will be used
* `ca_file` - Path to a certificate-authority file for the kubernetes API, only valid if server and token are passed.  If present `/run/secrets/kubernetes.io/serviceaccount/ca.crt` will be used
* `verify_ssl` - Controls if the kubernetes API certificate-authority should be verified, defaults to "true", only vaild if server and token are passed

## Features Not Yet Supported

The following are not yet supported:
- Map State Fields:
  - ItemReader
  - ItemSelector/ItemBatcher
  - ResultWriter

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ManageIQ/floe.

## License

The gem is available as open source under the terms of the [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0).
