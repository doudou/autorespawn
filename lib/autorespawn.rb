require 'set'
require 'hooks'
require 'autorespawn/hooks'
require "autorespawn/version"
require "autorespawn/exceptions"
require "autorespawn/program_id"
require "autorespawn/watch"
require "autorespawn/slave"
require "autorespawn/self"
require "autorespawn/manager"
require 'autorespawn/tracked_file'
require 'tempfile'

# Automatically exec's the current program when one of the source file changes
#
# The exec is done at very-well defined points to avoid weird state, and it is
# possible to define cleanup handlers beyond Ruby's at_exit mechanism
#
# Call this method from the entry point of your program, giving it the actual
# program functionality as a block. The method will exec and spawn subprocesses
# at will, when needed, and call the block in these subprocesses as required.
#
# At the point of call, all of the program's dependencies must be
# already required, as it is on this basis that the auto-reloading will
# be done
#
# This method does NOT return
#
# @param [Array<String>] command the command to be executed. It is
#   passed as-is to Kernel.spawn and Kernel.exec
# @param options keyword options to pass to Kernel.spawn and Kernel.exec
class Autorespawn
    include Hooks
    include Hooks::InstanceHooks

    INITIAL_STATE_FD = "AUTORESPAWN_AUTORELOAD"

    SLAVE_RESULT_ENV = 'AUTORESPAWN_SLAVE_RESULT_FD'
    SLAVE_INITIAL_STATE_ENV = 'AUTORESPAWN_SLAVE_INITIAL_STATE_FD'

    # ID object
    #
    # An arbitrary object passed to {#initialize} or {#add_slave} to identify
    # this process.
    #
    # @return [nil,Object]
    def self.name
        @name
    end
    def self.slave_result_fd
        @slave_result_fd
    end
    def self.slave?
        !!slave_result_fd
    end
    def self.initial_program_id
        @initial_program_id
    end
    @name, @slave_result_fd, @initial_program_id = nil

    def self.read_child_state
        # Delete the envvars first, we really don't want them to leak
        slave_initial_state_fd = ENV.delete(SLAVE_INITIAL_STATE_ENV)
        slave_result_fd = ENV.delete(SLAVE_RESULT_ENV)
        if slave_initial_state_fd
            slave_initial_state_fd = Integer(slave_initial_state_fd)
            io = IO.for_fd(slave_initial_state_fd)
            @name, @initial_program_id = Marshal.load(io)
            io.close
        end
        if slave_result_fd
            @slave_result_fd = Integer(slave_result_fd)
        end
    end
    read_child_state

    # An arbitrary objcet that can be used to identify the processes/slaves
    #
    # @return [nil,Object]
    attr_reader :name

    # The arguments that should be passed to Kernel.exec in standalone mode
    #
    # Ignored in slave mode
    #
    # @return [(Array,Hash)]
    attr_reader :process_command_line

    # @!group Hooks

    # @!method on_exception
    #
    # Register a callback that is called whenever an exception is rescued by
    # {#watch_yield}
    #
    # @yieldparam [Exception] exception
    define_hooks :on_exception

    # @!method at_exit
    #
    # Register a callback that is called after the block passed to {#run} has
    # been called, but before the process gets respawned. Meant to perform what
    # hass been done in {#run} that should be cleaned before respawning.
    #
    # @yieldparam [Exception] exception
    define_hooks :at_respawn

    # @!endgroup

    # @return [ProgramID] object currently known state of files makind this
    #   program
    attr_reader :program_id

    # @return [Array<Exception>] exceptions received in a {#requires} block or
    #   in a file required with {#require}
    attr_reader :exceptions

    # Set of paths that have been required within a {#requires} block or through
    # {#require}
    #
    # @return [Set<Pathname>]
    attr_reader :required_paths

    # Set of paths that are part of an error backtrace
    #
    # This is updated in {#requires} or {#require}
    #
    # @return [Set<Pathname>]
    attr_reader :error_paths

    # In master/slave mode, the list of subcommands that the master should spawn
    attr_reader :subcommands

    def initialize(*command, name: Autorespawn.name, track_current: false, **options)
        if command.empty?
            command = [$0, *ARGV]
        end
        @name = name
        @program_id = Autorespawn.initial_program_id ||
            ProgramID.new

        @process_command_line = [command, options]
        @exceptions = Array.new
        @required_paths = Set.new
        @error_paths = Set.new
        @subcommands = Array.new
        @exit_code = 0
        if track_current
            @required_paths = currently_loaded_files.to_set
        end
    end

    # Requires one file under the autorespawn supervision
    #
    # If the require fails, the call to {.run} will not execute its block,
    # instead waiting for the file(s) to change
    def require(file)
        watch_yield { Kernel.require file }
    end

    # Call to require a bunch of files in a block and add the result to the list of watches
    def watch_yield
        current = currently_loaded_files
        new_exceptions = Array.new
        begin
            result = yield
        rescue Interrupt, SystemExit
            raise
        rescue Exception => e
            new_exceptions << e
            run_hook :on_exception, e
            exceptions << e
            # cross-drb exceptions are broken w.r.t. #backtrace_locations. It
            # returns a string in their case. Since it happens only on
            # exceptions that originate from the server (which means a broken
            # Roby codepath), let's just ignore it
            if !e.backtrace_locations.kind_of?(String)
                backtrace = e.backtrace_locations.map { |l| Pathname.new(l.absolute_path) }
            else
                STDERR.puts "Caught what appears to be a cross-drb exception, which should not happen"
                STDERR.puts e.message
                STDERR.puts e.backtrace.join("\n  ")
                backtrace = Array.new
            end
            error_paths.merge(backtrace)
            if e.kind_of?(LoadError) && e.path
                error_paths << Pathname.new(e.path)
            end
        end
        required_paths.merge(currently_loaded_files - current)
        return result, new_exceptions
    end

    # Returns whether we have been spawned by a manager, or in standalone mode
    def slave?
        self.class.slave?
    end

    # Request that the master spawns these subcommands
    #
    # @raise [NotSlave] if the script is being executed in standalone mode
    def add_slave(*cmdline, name: nil, **spawn_options)
        subcommands << [name, cmdline, spawn_options]
    end

    # Create a pipe and dump the program ID state of the current program
    # there
    def dump_initial_state(files)
        program_id = ProgramID.new
        program_id.register_files(files)

        io = Tempfile.new "autorespawn_initial_state"
        Marshal.dump([name, program_id], io)
        io.flush
        io.rewind
        io
    end

    def currently_loaded_files
        $LOADED_FEATURES.map { |p| Pathname.new(p) } +
            caller_locations.map { |l| Pathname.new(l.absolute_path) }
    end

    # Defines the exit code for this instance
    def exit_code(value = nil)
        if value
            @exit_code = value
        else
            @exit_code
        end
    end

    # Perform the program workd and reexec it when needed
    #
    # It is the last method you should be calling in your program, providing the
    # program's actual work in the block. Once the block return, the method will
    # watch for changes and reexec's it 
    #
    # Exceptions raised by the block are displayed but do not cause the watch to
    # stop
    #
    # This method does NOT return
    def run(&block)
        if slave? || subcommands.empty?
            all_files = required_paths | error_paths
            if block_given? 
                all_files = perform_work(all_files, &block)
            end

            if slave?
                io = IO.for_fd(Autorespawn.slave_result_fd)
                string = Marshal.dump([subcommands, all_files])
                io.write string
                io.flush
                exit exit_code
            else
                io = dump_initial_state(all_files)
                cmdline  = process_command_line[0].dup
                redirect = Hash[io.fileno => io.fileno].merge(process_command_line[1])
                if cmdline.last.kind_of?(Hash)
                    redirect = redirect.merge(cmdline.pop)
                end
                Kernel.exec(Hash[SLAVE_INITIAL_STATE_ENV => "#{io.fileno}"], *cmdline, redirect)
            end
        else
            if block_given?
                raise ArgumentError, "cannot call #run with a block after using #add_slave"
            end
            manager = Manager.new
            subcommands.each do |name, command, options|
                manager.add_slave(*command, name: name, **options)
            end
            return manager.run
        end
    end

    # @api private
    def perform_work(all_files, &block)
        not_tracked = all_files.
            find_all do |p|
                begin !program_id.include?(p)
                rescue FileNotFound
                end
            end

        if not_tracked.empty? && !program_id.changed?
            if exceptions.empty?
                did_yield = true
                watch_yield(&block)
            end

            all_files = required_paths | error_paths
            not_tracked = all_files.
                find_all do |p|
                    begin !program_id.include?(p)
                    rescue FileNotFound
                    end
                end

            if !slave? && not_tracked.empty?
                Watch.new(program_id).wait
            end
            if did_yield
                run_hook :at_respawn
            end
        end
        all_files
    end

    def self.run(*command, **options, &block)
        new(*command, **options).run(&block)
    end
end

