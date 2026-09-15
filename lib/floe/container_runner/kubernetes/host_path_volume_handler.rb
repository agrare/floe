# frozen_string_literal: true

module Floe
  class ContainerRunner
    class Kubernetes
      # Mixin that handles host_path volumes for Kubernetes by staging the
      # host-side directory to S3 for download by an init container.
      module HostPathVolumeHandler
        DEFAULT_INIT_IMAGE  = "curlimages/curl:latest"
        INIT_CONTAINER_NAME = "floe-init"

        def init_host_path_volume_options(options)
          @s3_endpoint   = options["s3_endpoint"]
          @s3_bucket     = options["s3_bucket"]
          @s3_access_key = options["s3_access_key"]
          @s3_secret_key = options["s3_secret_key"]
          @init_image    = options.fetch("init_image", DEFAULT_INIT_IMAGE)
        end

        # Deletes every S3 object represented by staged_volumes, suppressing
        # errors for each deletion.
        def cleanup_staged_volumes(staged_volumes)
          Array(staged_volumes).each { |volume| delete_s3_object(volume[:s3_key] || volume["s3_key"]) }
        end

        private

        attr_reader :s3_endpoint, :s3_bucket, :s3_access_key, :s3_secret_key, :init_image

        def host_path_volume_instance_variables_to_hide
          %i[@s3_access_key @s3_client @s3_secret_key]
        end

        # Upload each volume's host_path as a .tar.gz to S3, returning an array
        # of hashes with :volume, :s3_key, :presigned_input_url.
        def stage_host_path_volumes(volumes, execution_id, logger)
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

        def delete_s3_object(key)
          s3_client.delete_object(:bucket => s3_bucket, :key => key)
        rescue StandardError
          nil
        end

        # Mutates spec in-place to add the emptyDir shared volumes and init
        # container for staged volumes.
        def add_host_path_volumes_to_spec!(spec, staged_volumes)
          spec[:spec][:volumes] ||= []
          primary = spec[:spec][:containers][0]
          primary[:volumeMounts] ||= []

          init_cmds          = []
          init_volume_mounts = []

          staged_volumes.each_with_index do |sv, idx|
            volume     = sv[:volume]
            share_name = "floe-volume-#{idx}"

            # emptyDir shared between init container and primary
            spec[:spec][:volumes] << {:name => share_name, :emptyDir => {}}

            primary[:volumeMounts] << {
              :name      => share_name,
              :mountPath => volume[:container_path]
            }

            init_volume_mounts << {
              :name      => share_name,
              :mountPath => volume[:container_path]
            }

            # Init container downloads and unpacks each volume's tarball
            init_cmds << "curl -fsSL '#{sv[:presigned_input_url]}' | tar -xzf - -C '#{volume[:container_path]}'"
          end

          # Init container: runs to completion before the primary starts, populating
          # all shared volumes from S3. Primary command/args are left untouched.
          spec[:spec][:initContainers] ||= []
          spec[:spec][:initContainers] << {
            :name         => INIT_CONTAINER_NAME,
            :image        => init_image,
            :command      => ["sh", "-c", init_cmds.join(" && ")],
            :volumeMounts => init_volume_mounts
          }
        end

        def s3_configured?
          !!(s3_endpoint && s3_bucket && s3_access_key && s3_secret_key)
        end

        def s3_client
          require "aws-sdk-s3"

          @s3_client ||= Aws::S3::Client.new(
            :endpoint          => s3_endpoint,
            :region            => "us-east-1", # required by SDK even for non-AWS endpoints
            :access_key_id     => s3_access_key,
            :secret_access_key => s3_secret_key,
            :force_path_style  => true         # required for MinIO and other non-AWS endpoints
          )
        end

        def presign_s3_get(key)
          require "aws-sdk-s3"

          presigner = Aws::S3::Presigner.new(:client => s3_client)
          presigner.presigned_url(:get_object, :bucket => s3_bucket, :key => key, :expires_in => 3600)
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
      end
    end
  end
end
