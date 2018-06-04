# frozen_string_literal: true

module Bundler
  class Injector
    def self.inject(deps, options = {})
      injector = new(deps, options)
      injector.inject(Bundler.default_gemfile, Bundler.default_lockfile)
    end

    def self.remove(gems, options = {})
      injector = new(gems, options)
      injector.remove(Bundler.default_gemfile, Bundler.default_lockfile)
    end

    def initialize(deps, options = {})
      @deps = deps
      @options = options
    end

    # @param [Pathname] gemfile_path The Gemfile in which to inject the new dependency.
    # @param [Pathname] lockfile_path The lockfile in which to inject the new dependency.
    # @return [Array]
    def inject(gemfile_path, lockfile_path)
      if Bundler.frozen_bundle?
        # ensure the lock and Gemfile are synced
        Bundler.definition.ensure_equivalent_gemfile_and_lockfile(true)
      end

      # temporarily unfreeze
      Bundler.settings.temporary(:deployment => false, :frozen => false) do
        # evaluate the Gemfile we have now
        builder = Dsl.new
        builder.eval_gemfile(gemfile_path)

        # don't inject any gems that are already in the Gemfile
        @deps -= builder.dependencies

        # add new deps to the end of the in-memory Gemfile
        # Set conservative versioning to false because we want to let the resolver resolve the version first
        builder.eval_gemfile("injected gems", build_gem_lines(false)) if @deps.any?

        # resolve to see if the new deps broke anything
        @definition = builder.to_definition(lockfile_path, {})
        @definition.resolve_remotely!

        # since nothing broke, we can add those gems to the gemfile
        append_to(gemfile_path, build_gem_lines(@options[:conservative_versioning])) if @deps.any?

        # since we resolved successfully, write out the lockfile
        @definition.lock(Bundler.default_lockfile)

        # invalidate the cached Bundler.definition
        Bundler.reset_paths!

        # return an array of the deps that we added
        @deps
      end
    end

    # @param [Pathname] gemfile_path The Gemfile from which to remove dependencies.
    # @param [Pathname] lockfile_path The lockfile from which to remove dependencies.
    # @return [Array]
    def remove(gemfile_path, lockfile_path)
      # evaluate the main Gemfile
      builder = Dsl.new
      builder.eval_gemfile(Bundler.default_gemfile)

      definition = builder.to_definition(lockfile_path, {})

      # remove gems from each gemfiles we have
      definition.gemfiles.each do |path|
        deps = remove_deps(path)

        show_warning("No gems were removed from the gemfile.") if deps.empty?

        deps.each {|dep| Bundler.ui.confirm "#{SharedHelpers.pretty_dependency(dep, false, true)} was removed." }
      end
    end

  private

    def conservative_version(spec)
      version = spec.version
      return ">= 0" if version.nil?
      segments = version.segments
      seg_end_index = version >= Gem::Version.new("1.0") ? 1 : 2

      prerelease_suffix = version.to_s.gsub(version.release.to_s, "") if version.prerelease?
      "#{version_prefix}#{segments[0..seg_end_index].join(".")}#{prerelease_suffix}"
    end

    def version_prefix
      if @options[:strict]
        "= "
      elsif @options[:optimistic]
        ">= "
      else
        "~> "
      end
    end

    def build_gem_lines(conservative_versioning)
      @deps.map do |d|
        name = d.name.dump

        requirement = if conservative_versioning
          ", \"#{conservative_version(@definition.specs[d.name][0])}\""
        else
          ", #{d.requirement.as_list.map(&:dump).join(", ")}"
        end

        if d.groups != Array(:default)
          group = d.groups.size == 1 ? ", :group => #{d.groups.inspect}" : ", :groups => #{d.groups.inspect}"
        end

        source = ", :source => \"#{d.source}\"" unless d.source.nil?

        %(gem #{name}#{requirement}#{group}#{source})
      end.join("\n")
    end

    def append_to(gemfile_path, new_gem_lines)
      gemfile_path.open("a") do |f|
        f.puts
        f.puts new_gem_lines
      end
    end

    # evalutes a gemfile to remove the specified gem
    # from it.
    def remove_deps(gemfile_path)
      # get initial snap shot of the gemfile
      initial_gemfile = IO.readlines(gemfile_path)

      # inform user of the the gemfile currently
      # being evaluated
      Bundler.ui.info "Removing gems from #{gemfile_path}"

      # evaluate the Gemfile we have
      builder = Dsl.new
      builder.eval_gemfile(gemfile_path)

      # remove gems from dependencies
      removed_deps = remove_gems_from_dependencies(builder, @deps)

      # abort the opertion if no gems were removed
      # no need to operate on gemfile furthur
      return [] if removed_deps.empty?

      # gemfile after removing requested gems
      cleaned_gemfile = remove_gems_from_gemfile(@deps, gemfile_path)

      # write the new gemfile
      write_to_gemfile(gemfile_path, cleaned_gemfile)

      # check for errors
      # including extra gems being removed
      # or some gems not being removed
      # and return the actual removed deps
      cross_check_for_errors(gemfile_path, builder.dependencies, removed_deps, initial_gemfile)
    end

    # @param [Dsl]    builder Dsl object of current Gemfile.
    # @param [Array]  gems Array of names of gems to be removed.
    # @return [Array] removed_deps Array of removed dependencies.
    def remove_gems_from_dependencies(builder, gems)
      removed_deps = []

      gems.each do |gem_name|
        deleted_dep = builder.dependencies.find {|d| d.name == gem_name }

        if deleted_dep.nil?
          raise GemfileError, "`#{gem_name}` is not specified in Gemfile so could not be removed."
        end

        builder.dependencies.delete(deleted_dep)

        removed_deps << deleted_dep
      end

      removed_deps
    end

    # @param [Array] gems            Array of names of gems to be removed.
    # @param [Pathname] gemfile_path The Gemfile from which to remove dependencies.
    def remove_gems_from_gemfile(gems, gemfile_path)
      # store patterns of all gems to be removed
      patterns = /gem\s+(['"])#{Regexp.union(gems)}\1|gem\s*\((['"])#{Regexp.union(gems)}\2\)/

      # remove lines which match the regex
      new_gemfile = IO.readlines(gemfile_path).reject {|line| line.match(patterns) }

      # remove lone \n and append them with other strings
      new_gemfile.each_with_index do |_line, index|
        if new_gemfile[index + 1] == "\n"
          new_gemfile[index] += new_gemfile[index + 1]
          new_gemfile.delete_at(index + 1)
        end
      end

      # remove any empty (and nested) blocks
      %w[group source env install_if].each {|block| remove_nested_blocks(new_gemfile, block) }

      new_gemfile.join.chomp
    end

    # @param [Pathname] gemfile_path  The Gemfile from which to remove dependencies.
    # @param [String]  contents       Content to written to Gemfile.
    def write_to_gemfile(gemfile_path, contents)
      SharedHelpers.filesystem_access(gemfile_path) {|g| File.open(g, "w") {|file| file.puts contents } }
    end

    # @param [Array] gemfile       Array of gemfile contents.
    # @param [String] block_name   Name of block name to look for.
    def remove_nested_blocks(gemfile, block_name)
      nested_blocks = 0

      # count number of nested blocks
      gemfile.each_with_index {|line, index| nested_blocks += 1 if !gemfile[index + 1].nil? && gemfile[index + 1].include?(block_name) && line.include?(block_name) }

      while nested_blocks >= 0
        nested_blocks -= 1

        gemfile.each_with_index do |line, index|
          next if line !~ /#{block_name}/
          if gemfile[index + 1] =~ /^\s*end\s*$/
            gemfile[index] = nil
            gemfile[index + 1] = nil
          end
        end

        # remove nil elements
        gemfile.reject!(&:nil?)
      end
    end

    # @param [Pathname] gemfile_path   The Gemfile from which to remove dependencies.
    # @param [Array] original_deps     Array of original dependencies.
    # @param [Array] removed_deps      Array of removed dependencies.
    # @param [Array] initial_gemfile   Contents of original Gemfile before any operation.
    def cross_check_for_errors(gemfile_path, original_deps, removed_deps, initial_gemfile)
      # evalute the new gemfile to look for any failure cases
      builder = Dsl.new
      builder.eval_gemfile(gemfile_path)

      # record gems which were removed but not requested
      extra_removed_gems = original_deps - builder.dependencies

      # if some extra gems were removed then raise error
      # and revert Gemfile to original
      unless extra_removed_gems.empty?
        write_to_gemfile(gemfile_path, initial_gemfile.join)

        raise InvalidOption, "Gems could not be removed."
      end

      # record gems which could not be removed due to some reasons
      errored_deps = builder.dependencies & removed_deps

      # warn user regarding those gems
      show_warning "#{errored_deps.map(&:name).join(", ")} could not be removed." unless errored_deps.empty?

      # return actual removed dependencies
      removed_deps - errored_deps
    end

    def show_warning(message)
      Bundler.ui.info Bundler.ui.add_color(message, :yellow)
    end
  end
end
