require "autorespawn/version"
require "autorespawn/exceptions"
require "autorespawn/program_id"
require "autorespawn/watch"

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

    INITIAL_STATE_ENV_NAME = "AUTORESPAWN_AUTORELOAD"

    def initialize(track_current: false)
        @respawn_handlers = Array.new
        @program_id = ProgramID.new
        @exceptions = Array.new
        @required_paths = Set.new
        @error_paths = Set.new
        if track_current
            @required_paths = currently_loaded_files.to_set
        end
    end

    # Returns true if there is an initial state dump
    def has_initial_state?
        !!ENV[INITIAL_STATE_ENV_NAME]
    end

    # Loads the initial state from STDIN
    def load_initial_state
        @program_id = Marshal.load(STDIN)
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

    # Create a pipe and dump the program ID state of the current program
    # there
    def dump_initial_state(files)
        program_id = ProgramID.new
        files.each do |file|
            begin
                program_id.register_file(file)
            rescue FileNotFound
            end
        end
        r, w = IO.pipe
        s = Marshal.dump(program_id)
        w.write s
        w.flush
        return r, w
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
    def run(*command, **options, &block)
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

            if not_tracked.empty?
                Watch.new(program_id).wait
            end
            if did_yield
                respawn_handlers.each { |b| b.call }
            end
        end

        all_files.merge(currently_loaded_files)
        r, w = dump_initial_state(all_files)
        if command.empty?
            command = [$0, *ARGV]
        end
        exec(Hash[INITIAL_STATE_ENV_NAME => '1'], *command,
             in: r, **options)
    end

    def self.run(*command, **options, &block)
        new.run(*command, **options, &block)
    end
end

