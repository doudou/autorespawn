require 'set'
require "autorespawn/version"
require "autorespawn/exceptions"
require "autorespawn/program_id"
require "autorespawn/watch"
require "autorespawn/slave"
require "autorespawn/manager"

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
    INITIAL_STATE_FD = "AUTORESPAWN_AUTORELOAD"

    SLAVE_RESULT_ENV = 'AUTORESPAWN_SLAVE_RESULT_FD'
    SLAVE_INITIAL_STATE_ENV = 'AUTORESPAWN_SLAVE_INITIAL_STATE_FD'

    def self.slave_result_fd
        @slave_result_fd
    end
    def self.slave_initial_state_fd
        @slave_initial_state_fd
    end

    # Delete the envvars first, we really don't want them to leak
    slave_initial_state_fd = ENV.delete(SLAVE_INITIAL_STATE_ENV)
    slave_result_fd = ENV.delete(SLAVE_RESULT_ENV)

    if slave_initial_state_fd
        @slave_initial_state_fd = Integer(slave_initial_state_fd)
    end
    if slave_result_fd
        @slave_result_fd = Integer(slave_result_fd)
    end

    # Set of callbacks called just before we respawn the process
    #
    # @return [Array<#call>]
    attr_reader :respawn_handlers

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

    def initialize(track_current: false)
        @respawn_handlers = Array.new
        @program_id = ProgramID.new
        @exceptions = Array.new
        @required_paths = Set.new
        @error_paths = Set.new
        @subcommands = Array.new
        if track_current
            @required_paths = currently_loaded_files.to_set
        end
    end

    # Returns true if there is an initial state dump
    def has_initial_state?
        !!Autorespawn.slave_initial_state_fd
    end

    # Loads the initial state from STDIN
    def load_initial_state
        io = IO.for_fd(Autorespawn.slave_initial_state_fd)
        @program_id = Marshal.load(io)
        io.close
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
            exceptions << e
            backtrace = e.backtrace_locations.map { |l| Pathname.new(l.absolute_path) }
            error_paths.merge(backtrace)
            if e.kind_of?(LoadError)
                error_paths << e.path
            end
        end
        required_paths.merge(currently_loaded_files - current)
        return result, new_exceptions
    end

    # Returns whether we have been spawned by a manager, or in standalone mode
    def slave?
        self.class.slave_result_fd
    end

    # Request that the master spawns these subcommands
    #
    # @raise [NotSlave] if the script is being executed in standalone mode
    def master_request_subcommand(*cmdline, **spawn_options)
        if !slave?
            raise NotSlave, "cannot call #master_request_subcommand in standalone mode"
        end
        subcommands << [cmdline, spawn_options]
    end

    # Create a pipe and dump the program ID state of the current program
    # there
    def dump_initial_state(files)
        program_id = ProgramID.new
        program_id.register_files(files)

        io = Tempfile.new "autorespawn_initial_state"
        Marshal.dump(program_id, io)
        io.flush
        io.rewind
        io
    end

    def currently_loaded_files
        $LOADED_FEATURES.map { |p| Pathname.new(p) } +
            caller_locations.map { |l| Pathname.new(l.absolute_path) }
    end
        
    # Declares a handler that should be called in a process, just before
    # exec'ing a fresh process *if* the block has been executed
    def at_respawn(&block)
        respawn_handlers << block
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
    def run(*command, **spawn_options, &block)
        if has_initial_state?
            load_initial_state
        end

        all_files = required_paths | error_paths
        not_tracked = all_files.
            find_all do |p|
                begin !program_id.include?(p)
                rescue FileNotFound
                end
            end

        if not_tracked.empty? && !program_id.changed?
            if exceptions.empty?
                did_yield = true
                _, yield_exceptions = watch_yield(&block)
                yield_exceptions.each do |e|
                    backtrace = (e.backtrace || Array.new).dup
                    first_line = backtrace.shift
                    STDERR.puts "#{e.message}: #{first_line}"
                    STDERR.puts "  #{e.backtrace.join("\n  ")}"
                end

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
                respawn_handlers.each { |b| b.call }
            end
        end

        if slave?
            io = IO.for_fd(Autorespawn.slave_result_fd)
            string = Marshal.dump([subcommands, all_files])
            io.write string
            io.flush
            exit exit_code
        else
            io = dump_initial_state(all_files)
            if command.empty?
                command = [$0, *ARGV]
            end
            Kernel.exec(Hash[SLAVE_INITIAL_STATE_ENV => "#{io.fileno}"], *command,
                        io.fileno => io.fileno, **spawn_options)
        end
    end

    def self.run(*command, **options, &block)
        new.run(*command, **options, &block)
    end
end

