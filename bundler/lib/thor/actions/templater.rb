class Thor
  module Actions

    # This is the base class for templater actions, ie. that copies something
    # from some directory (source) to another (destination).
    #
    # This implementation is completely based in Templater actions, created
    # by Jonas Nicklas and Michael S. Klishin under MIT LICENSE.
    #
    class Templater #:nodoc:
      attr_reader :base, :source, :destination, :relative_destination

      # Initializes given the source and destination.
      #
      # ==== Parameters
      # base<Thor::Base>:: A Thor::Base instance
      # source<String>:: Relative path to the source of this file
      # destination<String>:: Relative path to the destination of this file
      # log_status<Boolean>:: If false, does not log the status. True by default.
      #                       Templater log status does not accept color.
      #
      def initialize(base, source, destination, log_status=true)
        @base, @log_status = base, log_status
        self.source = source
        self.destination = destination
      end

      # Returns the contents of the source file as a String. If render is
      # available, a diff option is shown in the file collision menu.
      #
      # ==== Returns
      # String:: The source file.
      #
      # def render
      # end

      # Checks if the destination file already exists.
      #
      # ==== Returns
      # Boolean:: true if the file exists, false otherwise.
      #
      def exists?
        ::File.exists?(destination)
      end

      # Checks if the content of the file at the destination is identical to the rendered result.
      #
      # ==== Returns
      # Boolean:: true if it is identical, false otherwise.
      #
      def identical?
        exists? && (is_not_comparable? || ::File.read(destination) == render)
      end

      # Invokes the action. By default it adds to the file the content rendered,
      # but you can modify in the subclass.
      #
      def invoke!
        invoke_with_options!(base.options) do
          ::FileUtils.mkdir_p(::File.dirname(destination))
          ::File.open(destination, 'w'){ |f| f.write render }
        end
      end

      # Revokes the action.
      #
      def revoke!
        say_status :deleted, :green
        ::FileUtils.rm_rf(destination) unless pretend?
      end

      protected

        # Shortcut for pretend.
        #
        def pretend?
          base.options[:pretend]
        end

        # A templater is comparable if responds to render. In such cases, we have
        # to show the conflict menu to the user unless the files are identical.
        #
        def is_not_comparable?
          !respond_to?(:render)
        end

        # Sets the source value from a relative source value.
        #
        def source=(source)
          if source
            @source = ::File.expand_path(source.to_s, base.source_root)
          end
        end

        # Sets the destination value from a relative destination value. The
        # relative destination is kept to be used in output messages.
        #
        def destination=(destination)
          if destination
            @destination = ::File.expand_path(convert_encoded_instructions(destination.to_s), base.destination_root)
            @relative_destination = base.relative_to_absolute_root(@destination)
          end
        end

        # Filenames in the encoded form are converted. If you have a file:
        #
        #   %class_name%.rb
        #
        # It gets the class name from the base and replace it:
        #
        #   user.rb
        #
        def convert_encoded_instructions(filename)
          filename.gsub(/%(.*?)%/) do |string|
            instruction = $1.strip
            base.respond_to?(instruction) ? base.send(instruction) : string
          end
        end

        # Receives a hash of options and just execute the block if some
        # conditions are met.
        #
        def invoke_with_options!(options, &block)
          if exists?
            if is_not_comparable?
              say_status :exist, :blue
            elsif identical?
              say_status :identical, :blue
            else
              force_or_skip_or_conflict(options[:force], options[:skip], &block)
            end
          else
            say_status :create, :green
            block.call unless pretend?
          end

          destination
        end

        # If force is true, run the action, otherwise check if it's not being
        # skipped. If both are false, show the file_collision menu, if the menu
        # returns true, force it, otherwise skip.
        #
        def force_or_skip_or_conflict(force, skip, &block)
          if force
            say_status :force, :yellow
            block.call unless pretend?
          elsif skip
            say_status :skip, :yellow
          else
            say_status :conflict, :red
            force_or_skip_or_conflict(force_on_collision?, true, &block)
          end
        end

        # Shows the file collision menu to the user and gets the result.
        #
        def force_on_collision?
          base.shell.file_collision(destination){ render }
        end

        # Shortcut to say_status shell method.
        #
        def say_status(status, color)
          base.shell.say_status status, relative_destination, color if @log_status
        end

    end
  end
end
