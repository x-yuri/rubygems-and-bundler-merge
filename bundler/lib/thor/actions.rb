require 'fileutils'

Dir[File.join(File.dirname(__FILE__), "actions", "*.rb")].each do |action|
  require action
end

class Thor
  module Actions
    attr_accessor :behavior

    # On inclusion, add some options to base.
    #
    def self.included(base) #:nodoc:
      return unless base.respond_to?(:class_option)

      base.class_option :pretend, :type => :boolean, :aliases => "-p",
                                  :desc => "Run but do not make any changes"

      base.class_option :force, :type => :boolean, :aliases => "-f",
                                :desc => "Overwrite files that already exist"

      base.class_option :skip, :type => :boolean, :aliases => "-s",
                               :desc => "Skip files that already exist"

      base.class_option :quiet, :type => :boolean, :aliases => "-q",
                                :desc => "Supress status output"
    end

    # Extends initializer to add more configuration options.
    #
    # ==== Configuration
    # behavior<Symbol>:: The actions default behavior. Can be :invoke or :revoke.
    #                    It also accepts :force, :skip and :pretend to set the behavior
    #                    and the respective option.
    #
    # root<String>:: The root directory needed for some actions. It's also known
    #                as destination root.
    #
    # in_root<Boolean>:: When true, creates the root directory if it does not exist
    #                    and move to it. False by default.
    #
    def initialize(args=[], options={}, config={})
      self.behavior = case config[:behavior]
        when :force
          options.merge!(:force => true, 'force' => true)
          :invoke
        when :skip
          options.merge!(:skip => true, 'skip' => true)
          :invoke
        when :pretend
          options.merge!(:pretend => true, 'pretend' => true)
          :invoke
        when :revoke
          :revoke
        else
          :invoke
      end

      self.root = config[:root]
      if config[:in_root]
        FileUtils.mkdir_p(root) unless File.exist?(root)
        FileUtils.cd(root)
      end

      super
    end

    # Wraps an action object and call it accordingly to the thor class behavior.
    #
    def action(instance)
      if behavior == :revoke
        instance.revoke!
      else
        instance.invoke!
      end
    end

    # Returns the root for this thor class (also aliased as destination root).
    #
    def root
      @root_stack.last
    end
    alias :destination_root :root

    # Sets the root for this thor class. Relatives path are added to the
    # directory where the script was invoked and expanded.
    #
    def root=(root)
      @root_stack ||= []
      @root_stack[0] = File.expand_path(root || '')
    end

    # Returns the given path relative to the absolute root (ie, root where
    # the script started).
    #
    def relative_to_absolute_root(path, remove_dot=true)
      path = path.gsub(@root_stack[0], '.')
      remove_dot ? path[2..-1] : path
    end

    # Get the source root in the class. Raises an error if a source root is
    # not specified in the thor class.
    #
    def source_root
      self.class.source_root
    rescue NoMethodError => e
      raise NoMethodError, "You have to specify the class method source_root in your thor class."
    end

    # Do something in the root or on a provided subfolder. If a relative path
    # is given it's referenced from the current root. The full path is yielded
    # to the block you provide. The path is set back to the previous path when
    # the method exits.
    #
    # ==== Parameters
    # dir<String>:: the directory to move to.
    #
    def inside(dir='', &block)
      @root_stack.push File.expand_path(dir, root)
      FileUtils.mkdir_p(root) unless File.exist?(root)
      FileUtils.cd(root) { block.arity == 1 ? yield(root) : yield }
      @root_stack.pop
    end

    # Goes to the root and execute the given block.
    #
    def in_root
      inside(@root_stack.first) { yield }
    end

    # Changes the mode of the given file or directory.
    #
    # ==== Parameters
    # mode<Integer>:: the file mode
    # path<String>:: the name of the file to change mode
    # log_status<Boolean>:: if false, does not log the status. True by default.
    #                       If a symbol is given, uses it as the output color.
    #
    # ==== Example
    #
    #   chmod "script/*", 0755
    #
    def chmod(mode, path, log_status=true)
      path = File.expand_path(path, root)
      say_status_if_log :chmod, relative_to_absolute_root(path), log_status
      FileUtils.chmod_R(mode, path) unless options[:pretend]
    end

    # Executes a command.
    #
    # ==== Parameters
    # command<String>:: the command to be executed.
    # log_status<Boolean>:: if false, does not log the status. True by default.
    #                       If a symbol is given, uses it as the output color.
    #
    # ==== Example
    #
    #   inside('vendor') do
    #     run('ln -s ~/edge rails')
    #   end
    #
    def run(command, log_status=true)
      say_status_if_log :run, "#{command} from #{relative_to_absolute_root(root, false)}", log_status
      `#{command}` unless options[:pretend]
    end

    # Executes a ruby script (taking into account WIN32 platform quirks).
    #
    # ==== Parameters
    # command<String>:: the command to be executed.
    # log_status<Boolean>:: if false, does not log the status. True by default.
    #                       If a symbol is given, uses it as the output color.
    #
    def run_ruby_script(command, log_status=true)
      run("ruby #{command}", log_status)
    end

    # Run a thor command. A hash of options can be given and it's converted to 
    # switches.
    #
    # ==== Parameters
    # task<String>:: the task to be invoked
    # args<Array>:: arguments to the task
    # options<Hash>:: a hash with options used on invocation
    # log_status<Boolean>:: if false, does not log the status. True by default.
    #                       If a symbol is given, uses it as the output color.
    #
    # ==== Examples
    #
    #   thor :install, "http://gist.github.com/103208"
    #   #=> thor install http://gist.github.com/103208
    #
    #   thor :list, :all => true, :substring => 'rails'
    #   #=> thor list --all --substring=rails
    #
    def thor(task, *args)
      log_status = args.last.is_a?(Symbol) || [true, false].include?(args.last) ? args.pop : true
      options = args.last.is_a?(Hash) ? args.pop : {}

      in_root do
        args.unshift "thor #{task}"
        args.push Thor::Options.to_switches(options)
        run args.join(' ').strip, log_status
      end
    end

    # Run a regular expression replacement on a file.
    #
    # ==== Parameters
    # path<String>:: path of the file to be changed
    # flag<Regexp|String>:: the regexp or string to be replaced
    # replacement<String>:: the replacement, can be also given as a block
    # log_status<Boolean>:: if false, does not log the status. True by default.
    #                       If a symbol is given, uses it as the output color.
    #
    # ==== Example
    #
    #   gsub_file 'app/controllers/application_controller.rb', /#\s*(filter_parameter_logging :password)/, '\1'
    #
    #   gsub_file 'README', /rake/, :green do |match|
    #     match << " no more. Use thor!"
    #   end
    #
    def gsub_file(path, flag, *args, &block)
      log_status = args.last.is_a?(Symbol) || [ true, false ].include?(args.last) ? args.pop : true

      path = File.expand_path(path, root)
      say_status_if_log :gsub, relative_to_absolute_root(path), log_status

      unless options[:pretend]
        content = File.read(path)
        content.gsub!(flag, *args, &block)
        File.open(path, 'wb') { |file| file.write(content) }
      end
    end

    # Append text to a file.
    #
    # ==== Parameters
    # path<String>:: path of the file to be changed
    # data<String>:: the data to append to the file, can be also given as a block.
    # log_status<Boolean>:: if false, does not log the status. True by default.
    #                       If a symbol is given, uses it as the output color.
    #
    # ==== Example
    #
    #   append_file 'config/environments/test.rb', 'config.gem "rspec"'
    #
    def append_file(path, data=nil, log_status=true, &block)
      path = File.expand_path(path, root)
      say_status_if_log :append, relative_to_absolute_root(path), log_status

      File.open(path, 'ab') { |file| file.write(data || block.call) } unless options[:pretend]
    end

    # Prepend text to a file.
    #
    # ==== Parameters
    # path<String>:: path of the file to be changed
    # data<String>:: the data to prepend to the file, can be also given as a block.
    # log_status<Boolean>:: if false, does not log the status. True by default.
    #                       If a symbol is given, uses it as the output color.
    #
    # ==== Example
    #
    #   prepend_file 'config/environments/test.rb', 'config.gem "rspec"'
    #
    def prepend_file(path, data=nil, log_status=true, &block)
      path = File.expand_path(path, root)
      say_status_if_log :prepend, relative_to_absolute_root(path), log_status

      unless options[:pretend]
        content = data || block.call
        content << File.read(path)
        File.open(path, 'wb') { |file| file.write(content) }
      end
    end

    protected

      def say_status_if_log(status, message, log_status)
        color = log_status.is_a?(Symbol) ? log_status : :green
        shell.say_status status, message, color if log_status
      end

  end
end
