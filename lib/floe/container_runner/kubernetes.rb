# frozen_string_literal: true

module Floe
  class ContainerRunner
    class Kubernetes < Floe::Runner
      include Floe::ContainerRunner::DockerMixin

      TOKEN_FILE      = "/run/secrets/kubernetes.io/serviceaccount/token"
      CA_CERT_FILE    = "/run/secrets/kubernetes.io/serviceaccount/ca.crt"
      RUNNING_PHASES  = %w[Pending Running].freeze
      FAILURE_REASONS = %w[CrashLoopBackOff ImagePullBackOff ErrImagePull].freeze

      def initialize(options = {})
        require "active_support/core_ext/hash/keys"
        require "awesome_spawn"
        require "securerandom"
        require "base64"
        require "kubeclient"
        require "yaml"

        @kubeconfig_file    = ENV.fetch("KUBECONFIG", nil) || options.fetch("kubeconfig", File.join(Dir.home, ".kube", "config"))
        @kubeconfig_context = options["kubeconfig_context"]

        @token   = options["token"]
        @token ||= File.read(options["token_file"]) if options.key?("token_file")
        @token ||= File.read(TOKEN_FILE) if File.exist?(TOKEN_FILE)

        @server   = options["server"]
        @server ||= URI::HTTPS.build(:host => ENV.fetch("KUBERNETES_SERVICE_HOST"), :port => ENV.fetch("KUBERNETES_SERVICE_PORT", 6443)) if ENV.key?("KUBERNETES_SERVICE_HOST")

        @ca_file   = options["ca_file"]
        @ca_file ||= CA_CERT_FILE if File.exist?(CA_CERT_FILE)

        @verify_ssl = options["verify_ssl"] == "false" ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER

        if server.nil? && token.nil? && !File.exist?(kubeconfig_file)
          raise ArgumentError, "Missing connections options, provide a kubeconfig file or pass server and token via --docker-runner-options"
        end

        @namespace = options.fetch("namespace", "default")

        @pull_policy          = options["pull-policy"]
        @task_service_account = options["task_service_account"]

        super
      end

      def run_async!(resource, env, secrets, context)
        raise ArgumentError, "Invalid resource" unless resource&.start_with?("docker://")

        image  = resource.sub("docker://", "")
        name   = container_name(image)
        secret = create_secret!(secrets) if secrets && !secrets.empty?
        execution_id   = context.execution["Id"]
        runner_context = {"container_ref" => name, "container_state" => {"phase" => "Pending"}, "secrets_ref" => secret}

        begin
          create_pod!(name, image, env, execution_id, secret)
          runner_context
        rescue Kubeclient::HttpError => err
          cleanup(runner_context)
          {"Error" => "States.TaskFailed", "Cause" => err.to_s}
        end
      end

      def status!(runner_context)
        return if runner_context.key?("Error")

        runner_context["container_state"] = pod_info(runner_context["container_ref"]).to_h.deep_stringify_keys["status"]
      end

      def running?(runner_context)
        return false unless pod_running?(runner_context)
        # If a pod is Pending and the containers are waiting with a failure
        # reason such as ImagePullBackOff or CrashLoopBackOff then the pod
        # will never be run.
        return false if container_failed?(runner_context)

        true
      end

      def success?(runner_context)
        runner_context.dig("container_state", "phase") == "Succeeded"
      end

      def output(runner_context)
        if runner_context.key?("Error")
          runner_context.slice("Error", "Cause")
        elsif container_failed?(runner_context)
          failed_state = failed_container_states(runner_context).first
          {"Error" => failed_state["reason"], "Cause" => failed_state["message"]}
        else
          runner_context["output"] = kubeclient.get_pod_log(runner_context["container_ref"], namespace).body
        end
      end

      def cleanup(runner_context)
        pod, secret = runner_context.values_at("container_ref", "secrets_ref")

        delete_pod(pod)       if pod
        delete_secret(secret) if secret
      end

      def wait(timeout: nil, events: %i[create update delete])
        retry_connection = true

        begin
          watcher = kubeclient.watch_pods(:namespace => namespace)

          retry_connection = true

          if timeout.to_i > 0
            timeout_thread = Thread.new do
              sleep(timeout)
              watcher.finish
            end
          end

          watcher.each do |notice|
            break if error_notice?(notice)

            event = kube_notice_type_to_event(notice.type)
            next unless events.include?(event)

            runner_context = parse_notice(notice)
            next if runner_context.nil?

            if block_given?
              yield [event, runner_context]
            else
              timeout_thread&.kill # If we break out before the timeout, kill the timeout thread
              return [[event, runner_context]]
            end
          end
        rescue Kubeclient::HttpError => err
          raise unless err.error_code == 401 && retry_connection

          @kubeclient = nil
          retry_connection = false
          retry
        ensure
          begin
            watch&.finish
          rescue
            nil
          end

          timeout_thread&.join(0)
        end
      end

      private

      attr_reader :ca_file, :kubeconfig_file, :kubeconfig_context, :namespace, :server, :token, :verify_ssl

      def pod_info(pod_name)
        kubeclient.get_pod(pod_name, namespace)
      end

      def pod_running?(context)
        RUNNING_PHASES.include?(context.dig("container_state", "phase"))
      end

      def failed_container_states(context)
        container_statuses = context.dig("container_state", "containerStatuses") || []
        container_statuses.filter_map { |status| status["state"]&.values&.first }
                          .select { |state| FAILURE_REASONS.include?(state["reason"]) }
      end

      def container_failed?(context)
        failed_container_states(context).any?
      end

      def pod_spec(name, image, env, execution_id, secret = nil)
        spec = {
          :kind       => "Pod",
          :apiVersion => "v1",
          :metadata   => {
            :name      => name,
            :namespace => namespace,
            :labels    => {"execution_id" => execution_id}
          },
          :spec       => {
            :containers    => [
              {
                :name  => name[0...-9], # remove the random suffix and its leading hyphen
                :image => image,
                :env   => env.map { |k, v| {:name => k, :value => v.to_s} }
              }
            ],
            :restartPolicy => "Never"
          }
        }

        spec[:spec][:imagePullPolicy]    = @pull_policy          if @pull_policy
        spec[:spec][:serviceAccountName] = @task_service_account if @task_service_account

        if secret
          spec[:spec][:volumes] = [
            {
              :name   => "secret-volume",
              :secret => {:secretName => secret}
            }
          ]

          spec[:spec][:containers][0][:env] << {
            :name  => "_CREDENTIALS",
            :value => "/run/secrets/#{secret}/secret"
          }

          spec[:spec][:containers][0][:volumeMounts] = [
            {
              :name      => "secret-volume",
              :mountPath => "/run/secrets/#{secret}",
              :readOnly  => true
            }
          ]
        end

        spec
      end

      def create_pod!(name, image, env, execution_id, secret = nil)
        kubeclient.create_pod(pod_spec(name, image, env, execution_id, secret))
      end

      def delete_pod!(name)
        kubeclient.delete_pod(name, namespace)
      end

      def delete_pod(name)
        delete_pod!(name)
      rescue
        nil
      end

      def create_secret!(secrets)
        secret_name = SecureRandom.uuid

        secret_config = {
          :kind       => "Secret",
          :apiVersion => "v1",
          :metadata   => {
            :name      => secret_name,
            :namespace => namespace
          },
          :data       => {
            :secret => Base64.urlsafe_encode64(secrets.to_json)
          },
          :type       => "Opaque"
        }

        kubeclient.create_secret(secret_config)

        secret_name
      end

      def delete_secret!(secret_name)
        kubeclient.delete_secret(secret_name, namespace)
      end

      def delete_secret(name)
        delete_secret!(name)
      rescue
        nil
      end

      def kube_notice_type_to_event(type)
        case type
        when "ADDED"
          :create
        when "MODIFIED"
          :update
        when "DELETED"
          :delete
        else
          :unknown
        end
      end

      def error_notice?(notice)
        return false unless notice.type == "ERROR"

        message = notice.object&.message
        code    = notice.object&.code
        reason  = notice.object&.reason

        # This feels like a global concern and not an end user's concern
        Floe.logger.warn("Received [#{code} #{reason}], [#{message}]")

        true
      end

      def parse_notice(notice)
        return if notice.object.nil?

        pod             = notice.object
        container_ref   = pod.metadata.name
        execution_id    = pod.metadata.labels["execution_id"]
        container_state = pod.to_h[:status].deep_stringify_keys

        {"execution_id" => execution_id, "runner_context" => {"container_ref" => container_ref, "container_state" => container_state}}
      end

      def kubeclient
        return @kubeclient unless @kubeclient.nil?

        if server && token
          api_endpoint = server
          auth_options = {:bearer_token => token}
          ssl_options  = {:verify_ssl => verify_ssl}
          ssl_options[:ca_file] = ca_file if ca_file
        else
          context = kubeconfig&.context(kubeconfig_context)
          raise ArgumentError, "Missing connections options, provide a kubeconfig file or pass server and token via --docker-runner-options" if context.nil?

          api_endpoint = context.api_endpoint
          auth_options = context.auth_options
          ssl_options  = context.ssl_options
        end

        @kubeclient = Kubeclient::Client.new(api_endpoint, "v1", :ssl_options => ssl_options, :auth_options => auth_options).tap(&:discover)
      end

      def kubeconfig
        return if kubeconfig_file.nil? || !File.exist?(kubeconfig_file)

        Kubeclient::Config.read(kubeconfig_file)
      end
    end
  end
end
