# frozen_string_literal: true

module Bundler
  # Dsl to parse the Gemfile looking for plugins to install
  module Plugin
    class DSL < Bundler::Dsl
      class PluginGemfileError < PluginError; end
      alias_method :_gem, :gem # To use for plugin installation as gem

      # So that we don't have to override all there methods to dummy ones
      # explicitly.
      # They will be handled by method_missing
      [:gemspec, :gem, :path, :install_if, :platforms, :env].each {|m| undef_method m }

      attr_reader :auto_plugins

      def initialize
        super
        @sources = Plugin::SourceList.new
        @auto_plugins = [] # The source plugins inferred from :type
      end

      def plugin(name, *args)
        _gem(name, *args)
      end

      def method_missing(name, *args)
        raise PluginGemfileError, "Undefined local variable or method `#{name}' for Gemfile" unless Bundler::Dsl.method_defined? name
      end

      def source(source, *args, &blk)
        options = args.last.is_a?(Hash) ? args.pop.dup : {}
        options = normalize_hash(options)
        return super unless options.key?("type")

        plugin_name = "bundler-source-#{options["type"]}"
        unless @auto_plugins.include? plugin_name
          plugin(plugin_name)
          @auto_plugins << plugin_name
        end
      end
    end
  end
end
