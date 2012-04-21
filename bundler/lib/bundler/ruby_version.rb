module Bundler
  class RubyVersion
    attr_reader :version, :engine, :engine_version

    def initialize(version, engine, engine_version)
      # The parameters to this method must satisfy the
      # following constraints, which are verified in
      # the DSL:
      #
      # * If an engine is specified, an engine version
      #   must also be specified
      # * If an engine version is specified, an engine
      #   must also be specified
      # * If the engine is "ruby", the engine version
      #   must not be specified, or the engine version
      #   specified must match the version.

      @version        = version
      @engine         = engine || "ruby"
      @engine_version = engine_version || version
    end

    def to_s
      "ruby #{version} (#{engine} #{engine_version})"
    end

    def ==(other)
      @version          == other.version &&
        @engine         == other.engine &&
        @engine_version == other.engine_version
    end
  end

  # A subclass of RubyVersion that implements version,
  # engine and engine_version based upon the current
  # information in the system. It can be used anywhere
  # a RubyVersion object is expected, and can be
  # compared with a RubyVersion object.
  class SystemRubyVersion < RubyVersion
    def initialize(*)
      # override the default initialize, because
      # we will implement version, engine and
      # engine_version dynamically
    end

    def version
      RUBY_VERSION
    end

    def engine
      RUBY_ENGINE
    end

    def engine_version
      case RUBY_ENGINE
      when "ruby"
        RUBY_VERSION
      when "rbx"
        Rubinius::VERSION
      when "jruby"
        JRUBY_VERSION
      else
        raise BundlerError, "That RUBY_ENGINE is not recognized"
        nil
      end
    end
  end
end
