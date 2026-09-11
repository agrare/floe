# frozen_string_literal: true

module Floe
  class ContainerRunner
    class Kubernetes < Floe::Runner
      include Floe::ContainerRunner::DockerMixin

      TOKEN_FILE      = "/run/secrets/kubernetes.io/serviceaccount/token"
      CA_CERT_FILE    = "/run/secrets/kubernetes.io/serviceaccount/ca.crt"
      RUNNING_PHASES  = %w[Pending Running].freeze
      FAILURE_REASONS = %w[CrashLoopBackOff ImagePullBackOff ErrImagePull].freeze

      DEFAULT_SIDECAR_IMAGE    = "curlimages/curl:latest"
      SIDECAR_CONTAINER_NAME   = "floe-sidecar"
      READY_SENTINEL           = ".floe-ready"

      def initialize(options = {})
        require "active_support/core_ext/hash/keys" # deep_stringify_keys
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

        @s3_endpoint   = options["s3_endpoint"]
        @s3_bucket     = options["s3_bucket"]
        @s3_access_key = options["s3_access_key"]
        @s3_secret_key = options["s3_secret_key"]
        @sidecar_image = options.fetch("sidecar_image", DEFAULT_SIDECAR_IMAGE)

        super
      end

      def run_async!(resource, env, secrets, context, volumes: [])
        raise ArgumentError, "Invalid resource" unless resource&.start_with?("docker://")

        image  = resource.sub("docker://", "")
        name   = container_name(image)
        secret = create_secret!(secrets) if secrets && !secrets.empty?
        execution_id   = context.execution["Id"]
        runner_context = {"container_ref" => name, "container_state" => {"phase" => "Pending"}, "secrets_ref" => secret}

        staged_volumes = stage_volumes(volumes, execution_id, context.logger) if volumes.any?
        runner_context["s3_object_keys"] = staged_volumes.map { |sv| sv[:s3_key] } if staged_volumes

        begin
          spec = pod_spec(name, image, env, execution_id, secret, staged_volumes || [])
          kubeclient.create_pod(spec)
          runner_context["log_container"] = spec.dig(:metadata, :annotations, "floe/log_container")
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
        return false if runner_context.key?("Error")
        return false unless pod_running?(runner_context)
        # If a pod is Pending and the containers are waiting with a failure
        # reason such as ImagePullBackOff or CrashLoopBackOff then the pod
        # will never be run.
        return false if container_failed?(runner_context)

        true
      end

      def success?(runner_context)
        return false if runner_context.key?("Error")

        runner_context.dig("container_state", "phase") == "Succeeded"
      end

      def output(runner_context)
        if runner_context.key?("Error")
          runner_context.slice("Error", "Cause")
        elsif container_failed?(runner_context)
          failed_state = failed_container_states(runner_context).first
          {"Error" => failed_state["reason"], "Cause" => failed_state["message"]}
        else
          log_options = {}
          log_options[:container] = runner_context["log_container"] if runner_context["log_container"]
          runner_context["output"] = kubeclient.get_pod_log(runner_context["container_ref"], namespace, **log_options).body
        end
      end

      def cleanup(runner_context)
        pod, secret = runner_context.values_at("container_ref", "secrets_ref")

        delete_pod(pod)       if pod
        delete_secret(secret) if secret

        Array(runner_context["s3_object_keys"]).each { |key| delete_s3_object(key) }
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

      def inspect
        vars = instance_variables_to_inspect.map { |ivar| "#{ivar}=#{instance_variable_get(ivar).inspect}" }.join(", ")
        prefix = Kernel.instance_method(:inspect).bind_call(self).split(' ', 2).first
        "#{prefix} #{vars}>"
      end

      private

      attr_reader :ca_file, :kubeconfig_file, :kubeconfig_context, :namespace, :server, :token, :verify_ssl,
                  :s3_endpoint, :s3_bucket, :s3_access_key, :s3_secret_key, :sidecar_image

      def instance_variables_to_inspect
        instance_variables - %i[@kubeclient @s3_access_key @s3_client @s3_secret_key @token]
      end

      # ------------------------------------------------------------------
      # S3 volume staging
      # ------------------------------------------------------------------

      def s3_configured?
        !!(s3_endpoint && s3_bucket && s3_access_key && s3_secret_key)
      end

      def s3_client
        require "aws-sdk-s3"

        @s3_client ||= Aws::S3::Client.new(
          :endpoint         => s3_endpoint,
          :region           => "us-east-1", # required by SDK even for non-AWS endpoints
          :access_key_id     => s3_access_key,
          :secret_access_key => s3_secret_key,
          :force_path_style  => true         # required for MinIO and other non-AWS endpoints
        )
      end

      # Upload each volume's host_path as a .tar.gz to S3, returning an array
      # of hashes with :volume, :s3_key, :presigned_input_url.
      def stage_volumes(volumes, execution_id, logger)
        raise ArgumentError, "S3 must be configured (s3_endpoint, s3_bucket, s3_access_key, s3_secret_key) to use volumes with Kubernetes" unless s3_configured?

        volumes.map do |volume|
          s3_key = "floe/#{execution_id}/#{File.basename(volume[:container_path])}.tar.gz"
          logger.debug("Staging volume #{volume[:host_path]} -> s3://#{s3_bucket}/#{s3_key}")

          tarball = create_tarball(volume[:host_path])
          upload_to_s3(s3_key, tarball)
          presigned_url = presign_s3_get(s3_key)

          {:volume => volume, :s3_key => s3_key, :presigned_input_url => presigned_url}
        end
      end

      def create_tarball(source_path)
        require "rubygems/package"
        require "zlib"

        # TarWriter requires a seekable IO (pos=), so build the tar into a
        # plain StringIO first, then gzip the result.
        tar_buffer = StringIO.new
        Gem::Package::TarWriter.new(tar_buffer) do |tar|
          Dir.glob("#{source_path}/**/*", File::FNM_DOTMATCH).sort.each do |file|
            relative = file.sub("#{source_path}/", "")
            next if relative == "." || relative.empty?

            stat = File.stat(file)
            if stat.directory?
              tar.mkdir(relative, stat.mode)
            else
              tar.add_file(relative, stat.mode) do |io|
                File.open(file, "rb") { |f| IO.copy_stream(f, io) }
              end
            end
          end
        end

        gz_buffer = StringIO.new
        Zlib::GzipWriter.wrap(gz_buffer) { |gz| gz.write(tar_buffer.string) }
        gz_buffer.string
      end

      def upload_to_s3(key, data)
        s3_client.put_object(:bucket => s3_bucket, :key => key, :body => data)
      end

      def presign_s3_get(key)
        require "aws-sdk-s3"

        presigner = Aws::S3::Presigner.new(:client => s3_client)
        presigner.presigned_url(:get_object, :bucket => s3_bucket, :key => key, :expires_in => 3600)
      end

      def delete_s3_object(key)
        s3_client.delete_object(:bucket => s3_bucket, :key => key)
      rescue StandardError
        nil
      end

      # ------------------------------------------------------------------
      # Pod spec construction
      # ------------------------------------------------------------------

      def pod_spec(name, image, env, execution_id, secret = nil, staged_volumes = [])
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

        add_staged_volumes_to_spec!(spec, name, staged_volumes) if staged_volumes.any?

        spec
      end

      # Mutates spec in-place to add the emptyDir shared volumes, sidecar
      # container, and ready-poll CMD override on the primary container.
      def add_staged_volumes_to_spec!(spec, name, staged_volumes)
        spec[:spec][:volumes] ||= []
        primary = spec[:spec][:containers][0]
        primary[:volumeMounts] ||= []

        sidecar_download_cmds = []
        sidecar_wait_cmds     = []
        sidecar_upload_cmds   = []
        sidecar_volume_mounts = []

        staged_volumes.each_with_index do |sv, idx|
          volume     = sv[:volume]
          share_name = "floe-volume-#{idx}"

          # emptyDir shared between sidecar and primary
          spec[:spec][:volumes] << {:name => share_name, :emptyDir => {}}

          # Primary container mounts the shared volume at the requested path
          primary[:volumeMounts] << {
            :name      => share_name,
            :mountPath => volume[:container_path]
          }

          sidecar_volume_mounts << {
            :name      => share_name,
            :mountPath => volume[:container_path]
          }

          # Sidecar: download and unpack this volume's tarball
          sidecar_download_cmds << "curl -fsSL '#{sv[:presigned_input_url]}' | tar -xzf - -C '#{volume[:container_path]}'"

          # Sidecar: wait for completion sentinel if provided
          if volume[:completion_path]
            sidecar_wait_cmds << "until [ -f '#{volume[:completion_path]}' ]; do sleep 1; done"
          end

          # Sidecar: upload output if output_path is provided
          if volume[:output_path]
            upload_key    = sv[:s3_key].sub("input", "output")
            presigned_put = presign_s3_put(upload_key)
            sidecar_upload_cmds << "tar -czf - -C '#{volume[:output_path]}' . | curl -fsSL -T - '#{presigned_put}'"
          end
        end

        # Write the ready sentinel after all volumes are unpacked
        sidecar_download_cmds << "touch '#{staged_volumes.first[:volume][:container_path]}/#{READY_SENTINEL}'"

        sidecar_cmd = (sidecar_download_cmds + sidecar_wait_cmds + sidecar_upload_cmds).join(" && ")

        # Primary container: poll for the ready sentinel before executing
        ready_check = "until [ -f '#{staged_volumes.first[:volume][:container_path]}/#{READY_SENTINEL}' ]; do sleep 0.5; done"
        original_cmd = primary.delete(:command)
        primary[:command] = ["sh", "-c", "#{ready_check} && #{original_cmd ? original_cmd.join(' ') : 'exec \"$@\"'}"]
        primary[:args]    = original_cmd ? [] : primary.delete(:args) || []

        spec[:spec][:containers] << {
          :name         => SIDECAR_CONTAINER_NAME,
          :image        => sidecar_image,
          :command      => ["sh", "-c", sidecar_cmd],
          :volumeMounts => sidecar_volume_mounts
        }

        # Record the primary container name so output() knows which logs to fetch
        spec[:metadata] ||= {}
        spec[:metadata][:annotations] ||= {}
        spec[:metadata][:annotations]["floe/log_container"] = primary[:name]
      end

      def presign_s3_put(key)
        require "aws-sdk-s3"

        presigner = Aws::S3::Presigner.new(:client => s3_client)
        presigner.presigned_url(:put_object, :bucket => s3_bucket, :key => key, :expires_in => 3600)
      end

      # ------------------------------------------------------------------
      # Pod / secret lifecycle
      # ------------------------------------------------------------------

      def pod_info(pod_name)
        kubeclient.get_pod(pod_name, namespace)
      rescue Kubeclient::HttpError => err
        raise Floe::ExecutionError, "Failed to get status for pod #{namespace}/#{pod_name}: #{err}"
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
