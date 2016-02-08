# frozen_string_literal: true
require "bundler/cli/common"

module Bundler
  class CLI::Outdated
    attr_reader :options, :gems
    def initialize(options, gems)
      @options = options
      @gems = gems
    end

    def run
      sources = Array(options[:source])

      gems.each do |gem_name|
        Bundler::CLI::Common.select_spec(gem_name)
      end

      Bundler.definition.validate_ruby!
      current_specs = Bundler.ui.silence { Bundler.load.specs }
      current_dependencies = {}
      Bundler.ui.silence { Bundler.load.dependencies.each {|dep| current_dependencies[dep.name] = dep } }

      if gems.empty? && sources.empty?
        # We're doing a full update
        definition = Bundler.definition(true)
      else
        definition = Bundler.definition(:gems => gems, :sources => sources)
      end

      definition_resolution = proc { options["local"] ? definition.resolve_with_cache! : definition.resolve_remotely! }
      if options[:parseable]
        Bundler.ui.silence(&definition_resolution)
      else
        definition_resolution.call
      end

      Bundler.ui.info ""

      out_count = 0
      # Loop through the current specs
      gemfile_specs, dependency_specs = current_specs.partition {|spec| current_dependencies.key? spec.name }
      [gemfile_specs.sort_by(&:name), dependency_specs.sort_by(&:name)].flatten.each do |current_spec|
        next if !gems.empty? && !gems.include?(current_spec.name)

        dependency = current_dependencies[current_spec.name]

        if options["strict"]
          active_spec = definition.specs.detect {|spec| spec.name == current_spec.name }
        else
          active_spec = definition.index[current_spec.name].sort_by(&:version)
          if !current_spec.version.prerelease? && !options[:pre] && active_spec.size > 1
            active_spec = active_spec.delete_if {|b| b.respond_to?(:version) && b.version.prerelease? }
          end
          active_spec = active_spec.last

          if options[:major]
            current_major = current_spec.version.segments.first
            active_major = active_spec.version.segments.first
            active_spec = nil unless active_major > current_major
          end

          if options[:minor]
            current_minor = current_spec.version.segments[0, 2].compact.join(".")
            active_minor = active_spec.version.segments[0, 2].compact.join(".")
            active_spec = nil unless active_minor > current_minor
          end
        end
        next if active_spec.nil?

        gem_outdated = Gem::Version.new(active_spec.version) > Gem::Version.new(current_spec.version)
        git_outdated = current_spec.git_version != active_spec.git_version
        if gem_outdated || git_outdated
          unless options[:parseable]
            if out_count == 0
              if options["pre"]
                Bundler.ui.info "Outdated gems included in the bundle (including pre-releases):"
              else
                Bundler.ui.info "Outdated gems included in the bundle:"
              end
            end
          end

          spec_version    = "#{active_spec.version}#{active_spec.git_version}"
          current_version = "#{current_spec.version}#{current_spec.git_version}"
          dependency_version = %(, requested #{dependency.requirement}) if dependency && dependency.specific?

          if dependency && !options[:parseable]
            groups = dependency.groups.join(", ")
            pl = (dependency.groups.length > 1) ? "s" : ""
            groups = " in group#{pl} \"#{groups}\""
          end

          spec_outdated_info = "#{active_spec.name} (newest #{spec_version}, installed #{current_version}#{dependency_version})"
          if options[:parseable]
            Bundler.ui.info spec_outdated_info.to_s.rstrip
          else
            Bundler.ui.info "  * #{spec_outdated_info}#{groups}".rstrip
          end

          out_count += 1
        end
        Bundler.ui.debug "from #{active_spec.loaded_from}"
      end

      if out_count.zero?
        Bundler.ui.info "Bundle up to date!\n" unless options[:parseable]
      else
        exit 1
      end
    end
  end
end
