require 'rubygems/dependency_installer'

module Bundler
  class Installer < Environment
    def self.install(root, definition, unlock, options)
      installer = new(root, definition)
      installer.run(unlock, options)
      installer
    end

    def run(unlocked_gems, options)
      if dependencies.empty?
        Bundler.ui.warn "The Gemfile specifies no dependencies"
        return
      end

      # Unlock any requested gems
      @definition.unlock!(unlocked_gems)

      # Since we are installing, we can resolve the definition
      # using remote specs
      @definition.resolve_remotely!

      # Ensure that BUNDLE_PATH exists
      FileUtils.mkdir_p(Bundler.bundle_path)

      # Must install gems in the order that the resolver provides
      # as dependencies might actually affect the installation of
      # the gem.
      specs.each do |spec|
        spec.source.fetch(spec) if spec.source.respond_to?(:fetch)

        unless requested_specs.include?(spec)
          Bundler.ui.debug "  * Not in requested group; skipping."
          next
        end

        spec.source.install(spec)
        generate_bundler_executable_stubs(spec)
      end

      lock
    end

  private

    def generate_bundler_executable_stubs(spec)
      spec.executables.each do |executable|
        File.open "#{Bundler.bin_path}/#{executable}", 'w', 0755 do |f|
          f.puts File.read(File.expand_path('../templates/Executable', __FILE__))
        end
      end
    end

  end
end
