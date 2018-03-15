require "chef-workstation/action/base"
require "chef-workstation/action/errors"
require "chef-workstation/config"
require "fileutils"
module ChefWorkstation
  module Action
    class InstallChef < Base
      # TODO - linux specific value:
      UPLOAD_PATH = "/tmp/chef-install"

      def perform_action
        # TODO when we add windows support in the next card, let's
        # mixin 'install_to_target' and 'already_installed' from
        # platform-specific providers.
        verify_target_platform!
        return if already_installed_on_target?

        # TODO this is a pretty major divergence in behavior -
        # do we want to subclass InstallChefFromLocalSource, InstallChefFRomRemoteSource
        # and the caller determines which one to instantiate?
        package = lookup_artifact()
        local_path = download_to_workstation(package.url)
        remote_path = upload_to_target(local_path)

        install_chef_to_target(remote_path)
      end

      def verify_target_platform!
        if connection.os.linux?
          :ok
        else
          raise Errors::UnsupportedTargetOS.new(connection.os[:name])
        end
      end

      def already_installed_on_target?
        connection.run_command("which chef-client").exit_status == 0
      end

      def lookup_artifact
        require "mixlib/install"
        os = connection.os
        platform = os[:platform]
        c = {
          platform_version: platform[:release],
          platform: os[:name],
          architecture: platform[:arch],
          product_name: "chef",
          version: :latest,
          channel: :stable,
        }
        Mixlib::Install.new(c).artifact_info
      end

      def download_to_workstation(url_path)
        require "uri"
        require "net/http"

        FileUtils.mkdir_p(Config.cache.path)
        url = URI.parse(url_path)
        name = File.basename(url.path)
        local_path = File.join(Config.cache.path, name)

        return local_path if File.exist?(local_path)

        file = open(local_path, "wb")
        # TODO - this may be a file-downloader kind of class if we need to
        #        directly handle additional downloads.

        puts "Downloading: #{local_path}"
        Net::HTTP.start(url.host) do |http|
          begin
            # TODO status update when we progress through a chunk,
            # perhaps look at total size and use an actual progress bar?
            http.request_get(url.path) do |resp|
              resp.read_body do |segment|
                file.write(segment)
              end
            end
          rescue => e
            puts e.message
            error = true
          ensure
            file.close()
            if error
              File.delete(local_path)
            end
          end
        end
        local_path
      end

      def upload_to_target(local_path)
        # TODO config:
        installer_dir = "/tmp/chef-installer"
        remote_path = File.join(installer_dir, File.basename(local_path))
        connection.run_command("mkdir -p #{installer_dir}")
        connection.run_command("chmod 777 #{installer_dir}")
        # TODO status updates - uploading file... any hooks in train?
        connection.upload_file(local_path, remote_path)
        remote_path
      end

      def install_chef_to_target(remote_path)
        install_cmd = case File.extname(remote_path)
                      when ".rpm"
                        "rpm -Uvh #{remote_path}"
                      when ".deb"
                        "dpkg -i #{remote_path}"
                      end
        connection.run_command(install_cmd)
      end
    end
  end
end
