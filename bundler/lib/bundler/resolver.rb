require 'set'
# This is the latest iteration of the gem dependency resolving algorithm. As of now,
# it can resolve (as a success or failure) any set of gem dependencies we throw at it
# in a reasonable amount of time. The most iterations I've seen it take is about 150.
# The actual implementation of the algorithm is not as good as it could be yet, but that
# can come later.

# Extending Gem classes to add necessary tracking information
module Gem
  class Specification
    def required_by
      @required_by ||= []
    end
  end
  class Dependency
    def required_by
      @required_by ||= []
    end
  end
end

module Bundler
  class Resolver
    ALL = [ Gem::Platform::RUBY,
            Gem::Platform::JAVA,
            Gem::Platform::MSWIN,
            Gem::Platform::MING]

    class SpecGroup < Array
      attr_reader :activated, :required_by

      def initialize(a)
        super
        @required_by  = []
        @activated    = []
        @dependencies = nil
        @specs        = {}

        ALL.each do |p|
          @specs[p] = reverse.find { |s| s.match_platform(p) }
        end
      end

      def initialize_copy(o)
        super
        @required_by = o.required_by.dup
        @activated   = o.activated.dup
      end

      def to_specs
        specs = {}

        @activated.each do |p|
          if s = @specs[p]
            platform = Gem::Platform.new(s.platform).to_generic
            next if specs[platform]

            lazy_spec = LazySpecification.new(name, version, platform, source)
            lazy_spec.dependencies.replace s.dependencies
            specs[platform] = lazy_spec
          end
        end
        specs.values
      end

      def activate_platform(platform)
        unless @activated.include?(platform)
          @activated << platform
          return __dependencies[platform] || []
        end
        []
      end

      def name
        @name ||= first.name
      end

      def version
        @version ||= first.version
      end

      def source
        @source ||= first.source
      end

      def for?(platform)
        @specs[platform]
      end

    private

      def __dependencies
        @dependencies ||= begin
          dependencies = {}
          ALL.each do |p|
            if spec = @specs[p]
              dependencies[p] = []
              spec.dependencies.each do |dep|
                next if dep.type == :development
                dependencies[p] << DepProxy.new(dep, p)
              end
            end
          end
          dependencies
        end
      end
    end

    attr_reader :errors

    # Figures out the best possible configuration of gems that satisfies
    # the list of passed dependencies and any child dependencies without
    # causing any gem activation errors.
    #
    # ==== Parameters
    # *dependencies<Gem::Dependency>:: The list of dependencies to resolve
    #
    # ==== Returns
    # <GemBundle>,nil:: If the list of dependencies can be resolved, a
    #   collection of gemspecs is returned. Otherwise, nil is returned.
    def self.resolve(requirements, index, source_requirements = {}, base = [])
      base = SpecSet.new(base) unless base.is_a?(SpecSet)
      resolver = new(index, source_requirements, base)
      result = catch(:success) do
        resolver.start(requirements)
        raise resolver.version_conflict
        nil
      end
      SpecSet.new(result)
    end

    def initialize(index, source_requirements, base)
      @errors = {}
      @stack  = []
      @base   = base
      @index  = index
      @source_requirements = source_requirements
    end

    def debug
      if ENV['DEBUG_RESOLVER']
        debug_info = yield
        debug_info = debug_info.inpsect unless debug_info.is_a?(String)
        $stderr.puts debug_info
      end
    end

    def successify(activated)
      activated.values.map { |s| s.to_specs }.flatten.compact
    end

    def start(reqs)
      activated    = {}

      resolve(reqs, activated)
    end

    def resolve(reqs, activated)
      # If the requirements are empty, then we are in a success state. Aka, all
      # gem dependencies have been resolved.
      throw :success, successify(activated) if reqs.empty?

      debug { print "\e[2J\e[f" ; "==== Iterating ====\n\n" }

      # Sort dependencies so that the ones that are easiest to resolve are first.
      # Easiest to resolve is defined by:
      #   1) Is this gem already activated?
      #   2) Do the version requirements include prereleased gems?
      #   3) Sort by number of gems available in the source.
      reqs = reqs.sort_by do |a|
        [ activated[a.name] ? 0 : 1,
          a.requirement.prerelease? ? 0 : 1,
          @errors[a.name]   ? 0 : 1,
          activated[a.name] ? 0 : search(a).size ]
      end

      debug { "Activated:\n" + activated.values.map { |a| "  #{a.name} (#{a.version})" }.join("\n") }
      debug { "Requirements:\n" + reqs.map { |r| "  #{r.name} (#{r.requirement})"}.join("\n") }

      activated = activated.dup

      # Pull off the first requirement so that we can resolve it
      current = reqs.shift

      debug { "Attempting:\n  #{current.name} (#{current.requirement})"}

      # Check if the gem has already been activated, if it has, we will make sure
      # that the currently activated gem satisfies the requirement.
      if existing = activated[current.name]
        if current.requirement.satisfied_by?(existing.version)
          debug { "    * [SUCCESS] Already activated" }
          @errors.delete(existing.name)
          # Since the current requirement is satisfied, we can continue resolving
          # the remaining requirements.

          # I have no idea if this is the right way to do it, but let's see if it works
          # The current requirement might activate some other platforms, so let's try
          # adding those requirements here.
          reqs.concat existing.activate_platform(current.__platform)

          resolve(reqs, activated)
        else
          debug { "    * [FAIL] Already activated" }
          @errors[existing.name] = [existing, current]
          debug { current.required_by.map {|d| "      * #{d.name} (#{d.requirement})" }.join("\n") }
          # debug { "    * All current conflicts:\n" + @errors.keys.map { |c| "      - #{c}" }.join("\n") }
          # Since the current requirement conflicts with an activated gem, we need
          # to backtrack to the current requirement's parent and try another version
          # of it (maybe the current requirement won't be present anymore). If the
          # current requirement is a root level requirement, we need to jump back to
          # where the conflicting gem was activated.
          parent = current.required_by.last
          # `existing` could not respond to required_by if it is part of the base set
          # of specs that was passed to the resolver (aka, instance of LazySpecification)
          parent ||= existing.required_by.last if existing.respond_to?(:required_by)
          # We track the spot where the current gem was activated because we need
          # to keep a list of every spot a failure happened.
          debug { "    -> Jumping to: #{parent.name}" }
          if parent
            throw parent.name, existing.respond_to?(:required_by) && existing.required_by.last.name
          else
            # The original set of dependencies conflict with the base set of specs
            # passed to the resolver. This is by definition an impossible resolve.
            raise version_conflict
          end
        end
      else
        # There are no activated gems for the current requirement, so we are going
        # to find all gems that match the current requirement and try them in decending
        # order. We also need to keep a set of all conflicts that happen while trying
        # this gem. This is so that if no versions work, we can figure out the best
        # place to backtrack to.
        conflicts = Set.new

        # Fetch all gem versions matching the requirement
        #
        # TODO: Warn / error when no matching versions are found.
        matching_versions = search(current)

        if matching_versions.empty?
          if current.required_by.empty?
            if current.source
              name = current.name
              versions = @source_requirements[name][name].map { |s| s.version }
              message  = "Could not find gem '#{current}' in #{current.source}.\n"
              if versions.any?
                message << "Source contains '#{name}' at: #{versions.join(', ')}"
              else
                message << "Source does not contain any versions of '#{current}'"
              end
            else
              message = "Could not find gem '#{current}' "
              if @index.sources.include?(Bundler::Source::Rubygems)
                message << "in any of the gem sources."
              else
                message << "in the gems available on this machine."
              end
            end
            raise GemNotFound, message
          else
            @errors[current.name] = [nil, current]
          end
        end

        matching_versions.reverse_each do |spec_group|
          conflict = resolve_requirement(spec_group, current, reqs.dup, activated.dup)
          conflicts << conflict if conflict
        end
        # If the current requirement is a root level gem and we have conflicts, we
        # can figure out the best spot to backtrack to.
        if current.required_by.empty? && !conflicts.empty?
          # Check the current "catch" stack for the first one that is included in the
          # conflicts set. That is where the parent of the conflicting gem was required.
          # By jumping back to this spot, we can try other version of the parent of
          # the conflicting gem, hopefully finding a combination that activates correctly.
          @stack.reverse_each do |savepoint|
            if conflicts.include?(savepoint)
              debug { "    -> Jumping to: #{savepoint}" }
              throw savepoint
            end
          end
        end
      end
    end

    def resolve_requirement(spec_group, requirement, reqs, activated)
      # We are going to try activating the spec. We need to keep track of stack of
      # requirements that got us to the point of activating this gem.
      spec_group.required_by.replace requirement.required_by
      spec_group.required_by << requirement

      activated[spec_group.name] = spec_group
      debug { "  Activating: #{spec.name} (#{spec.version})" }
      debug { spec.required_by.map { |d| "    * #{d.name} (#{d.requirement})" }.join("\n") }

      dependencies = spec_group.activate_platform(requirement.__platform)

      # Now, we have to loop through all child dependencies and add them to our
      # array of requirements.
      debug { "    Dependencies"}
      dependencies.each do |dep|
        next if dep.type == :development
        debug { "    * #{dep.name} (#{dep.requirement})" }
        dep.required_by.replace(requirement.required_by)
        dep.required_by << requirement
        reqs << dep
      end

      # We create a savepoint and mark it by the name of the requirement that caused
      # the gem to be activated. If the activated gem ever conflicts, we are able to
      # jump back to this point and try another version of the gem.
      length = @stack.length
      @stack << requirement.name
      retval = catch(requirement.name) do
        resolve(reqs, activated)
      end
      # Since we're doing a lot of throw / catches. A push does not necessarily match
      # up to a pop. So, we simply slice the stack back to what it was before the catch
      # block.
      @stack.slice!(length..-1)
      retval
    end

    def search(dep)
      results = @base[dep.name]

      if results.any?
        d = Gem::Dependency.new(dep.name, results.first.version)
      else
        d = dep.dep
      end

      index = @source_requirements[d.name] || @index
      # results = index.search_for_all_platforms(d) + results
      results += index.search_for_all_platforms(d)

      if results.any?
        version = results.first.version
        nested  = [[]]
        results.each do |spec|
          if spec.version != version
            nested << []
            version = spec.version
          end
          nested.last << spec
        end
        nested.map { |a| SpecGroup.new(a) }.select { |sg| sg.for?(dep.__platform) }
      else
        []
      end
    end

    def version_conflict
      VersionConflict.new(
        errors.keys,
        "No compatible versions could be found for required dependencies:\n  #{error_message}")
    end

    def error_message
      output = errors.inject("") do |o, (conflict, (origin, requirement))|
        if origin
          o << "  Conflict on: #{conflict.inspect}:\n"
          if origin.respond_to?(:required_by) && required_by = origin.required_by.first
            o << "    * #{conflict} (#{origin.version}) activated by #{required_by}\n"
          else
            o << "    * #{conflict} (#{origin.version}) in Gemfile.lock\n"
          end
          o << "    * #{requirement} required"
          if requirement.required_by.first
            o << " by #{requirement.required_by.first}\n"
          else
            o << " in Gemfile\n"
          end
        else
          o << "  #{requirement} not found in any of the sources\n"
          o << "      required by #{requirement.required_by.first}\n"
        end
        o << "    All possible versions of origin requirements conflict."
      end
    end
  end
end
