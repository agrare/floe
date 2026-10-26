# Floe

[![CI](https://github.com/ManageIQ/floe/actions/workflows/ci.yaml/badge.svg)](https://github.com/ManageIQ/floe/actions/workflows/ci.yaml)

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

If you need to set a credential at runtime you can do that by using the `"ResultPath": "$$.Credentials"` directive, for example to user a username/password to login and get a Bearer token:

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
      "ResultPath": "$$.Credentials",
      "Next": "DoSomething"
    },
    "DoSomething": {
      "Type": "Task",
      "Resource": "docker://do-something:latest",
      "Credentials": {
        "token.$": "$$.Credentials.bearer_token"
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

### Task Runners

Floe provides a number of options for the Task `"Resource"` parameter.  The `"Resource"` runner is declared by the author based on the `URI`.

Task Runner Types:
* `floe://`
* `docker://`

#### Floe resource

This is the "builtin" runner and exposes methods that are executed internally without having to call out to a docker image.

##### Log builtin method

`floe://log` allows you to write a message to the logger.

Example:
```json
{
  "Comment": "Print log message",
  "StartAt": "Log",
  "States": {
    "Log": {
      "Type": "Task",
      "Resource": "floe://log",
      "Parameters": {
        "Level": "INFO",
        "Message": "Hello, Floe!"
      },
      "End": true
    }
```

Log Parameters:
* `Level` (required) - Log level. Permitted values: `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`, or `UNKNOWN`.  Defaults to `INFO`.
* `Message` (required) - The message to log

##### HTTP builtin method

`floe://http` allows you to execute HTTP method calls.

Example:
```json
{
  "Comment": "Execute a HTTP call",
  "StartAt": "HTTP",
  "States": {
    "HTTP": {
      "Type": "Task",
      "Resource": "floe://http",
      "Parameters": {
        "Method": "POST",
        "Url": "http://localhost:3000/api/login",
        "Headers": {"ContentType": "application/json"},
        "Body": {"username.$": "$$.Credentials.username", "password.$": "$$.Credentials.password"},
        "Options": {"Encoding": "JSON"}
      },
      "ResultSelector": {"auth_token.$": "$.Body.auth_token"},
      "ResultPath": "$$.Credentials",
      "End": true
    }
```

HTTP Parameters:
* `Method` (required) - HTTP method name. Permitted values: `GET`, `POST`, `PUT`, `DELETE`, `HEAD`, `PATCH`, `OPTIONS`, or `TRACE`.  Defaults to `GET`.
* `Url` (required) - URL to execute the HTTP call to
* `Headers` - Hash of unencoded HTTP request header key/value pairs.
* `QueryParameters` - URI query unencoded key/value pairs.
* `Body` - HTTP request body.  Depending on Encoding this can be a String or a Hash of key/value pairs.
* `Ssl` - SSL options
  * `Verify` - Boolean - Verify SSL certificate.
  * `VerifyHostname` - Boolean - Verify SSL certificate hostname.
  * `Hostname` - String - Server hostname for SNI.
  * `CaFile` - String - Path to a CA file in PEM format.
  * `CaPath` - String - Path to a CA directory.
  * `VerifyMode` - Integer - OpenSSL constant.
  * `VerifyDepth` - Integer - Maximum depth for the certificate chain validation.
  * `Version` - Integer - SSL Version.
  * `MinVersion` - Integer - Minimum SSL Version.
  * `MaxVersion` - Integer - Maximum SSL Version.
  * `Ciphers` - String - Ciphers supported.
* `Options`
  * `Timeout`
  * `ReadTimeout`
  * `OpenTimeout`
  * `WriteTimeout`
  * `Encoding` - String
    * `JSON` - JSON encodes the request and decodes the response
* `Proxy`
  * `Uri` - String - URI of the proxy.
  * `User` - String - User for the proxy.
  * `Password` - String - Pasword for the proxy

Output:
A successful HTTP request will return the response Status, Body, and Headers. For example,
```json
{
  "Status": 200,
  "Body": {"result": {"foo": "bar"}},
  "Headers": {"content-type": "application/json"}
}
```

Errors:
If an HTTP request fails, the `floe://http` builtin method will return an error payload that includes
the error code, the reason, and the response Status, Body, and Headers. For example,
```json
{
  "Error": "States.Http.StatusCode.404",
  "Cause": "Not Found",
  "Details": {"Status": 404, "Body": {"code": 404, "reason": "Page not found"}, "Headers": {"content-type": "application/json"}}
}
```

#### Docker resource

The docker resource runner takes a docker image URI, including the registry, name, and tag.

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

## JSONata

Floe supports the [JSONata query language](https://states-language.net/#jsonata-concepts) as an alternative to JSONPath.

Set `QueryLanguage` to `"JSONata"` at the top level of the workflow to use it for all states, or on individual states.  `Parallel` branches and `Map` item processors inherit the language of the state that contains them.  A state can set `"QueryLanguage": "JSONPath"` to switch back.  The default is `"JSONPath"`.

```json
{
  "QueryLanguage": "JSONata",
  "StartAt": "Total",
  "States": {
    "Total": {
      "Type": "Pass",
      "Assign": {"total": "{% $sum($states.input.orders.(price * qty)) %}"},
      "Next": "Done"
    },
    "Done": {
      "Type": "Succeed",
      "Output": {"total": "{% $total %}"}
    }
  }
}
```

In a JSONata state:
- Any string of the form `{% expression %}` is evaluated as JSONata.  This works at any depth in objects and arrays.
- `Arguments` (Task, Parallel) replaces `Parameters`, `Output` replaces `InputPath`/`ResultSelector`/`ResultPath`/`OutputPath`, and `Condition` replaces `Variable` and the comparison operators in `Choice` rules.
- Map uses `Items` instead of `ItemsPath`.
- `Assign` sets variables which are available as `$name` in the later states.  Variables are only visible to the expressions of states, `Parallel` branches and `Map` iterations that start after they are assigned, and changes made inside a branch or iteration are not visible outside it.
- `$states.input` is the state input, `$states.result` is the result of a Task, Parallel or Map, `$states.errorOutput` is the error in a `Catch`, and `$states.context` is the context object.
- Fields which only exist in JSONPath (`InputPath`, `OutputPath`, `Parameters`, `ResultPath`, `ResultSelector`, `ItemsPath`, `*Path` fields, `Variable`) are an error in a JSONata state, and so are the JSONata-only fields (`Arguments`, `Output`, `Assign`, `Items`, `Condition`) in a JSONPath state.
- `TimeoutSeconds`, `Seconds`, `Timestamp`, `Error`, `Cause`, `MaxConcurrency`, `ToleratedFailureCount` and `ToleratedFailurePercentage` can be a JSONata expression.
- An expression that fails to evaluate fails the state with the error `States.QueryEvaluationError`, which can be handled with `Catch`.

See [examples/jsonata.asl](examples/jsonata.asl) for a complete example.

JSONata requires Ruby 3.1 or newer and the [jsonata](https://github.com/Fryguy/jsonata-rb) gem.  The gem is not yet published to rubygems.org and so is not a dependency of floe's gemspec.  Applications which use JSONata must add it to their own Gemfile:

```ruby
gem "jsonata", :git => "https://github.com/Fryguy/jsonata-rb"
```

The gem is loaded the first time a `{% %}` expression is parsed, so workflows which do not use JSONata do not need it.

## Features Not Yet Supported

The following are not yet supported:
- Map State Fields:
  - ItemReader
  - ResultWriter
  - ItemBatcher in a JSONata state
- Assign field in a JSONPath state (it is supported when `QueryLanguage` is `JSONata`)
- `HeartbeatSeconds` expressions are parsed but, as with JSONPath, `HeartbeatSeconds` has no effect

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ManageIQ/floe.

## License

The gem is available as open source under the terms of the [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0).
