module RubyProgramWatch
    # Functionality to watch a program for change
    class Watch
        # Create a pipe and dump the program ID state of the current program
        # there
        def self.dump_self_id
            r, w = IO.pipe
            Marshal.dump(ProgramID.for_self, w)
            w.flush
            return r, w
        end

        # Automatically autoreload this program when one of the source file
        # changes
        #
        # Call this method from the entry point of your program, giving it the
        # actual program functionality as a block. The method will exec and
        # spawn subprocesses at will, when needed, and call the block in these
        # subprocesses as required.
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
        def self.autoreload(*command, **options)
            if !block_given?
                raise ArgumentError, "you must provide the actions to perform on reload as a block"
            end

            # Check if we're being called by an autoreload call already
            if ENV['RUBY_PROGRAM_WATCH_AUTORELOAD']
                program_id = Marshal.load(STDIN)
                if !program_id.changed?
                    # We can do what is required of us and wait for changes
                    yield
                    new(program_id).wait
                end

                r, w = dump_self_id
                exec(Hash['RUBY_PROGRAM_WATCH_AUTORELOAD' => '1'], *command,
                     in: r, **options)
            else
                begin
                    r, w = dump_self_id
                    pid = spawn(Hash['RUBY_PROGRAM_WATCH_AUTORELOAD' => '1'], *command,
                                in: r, pgroup: true, **options)
                    w.close
                    r.close
                    _, status = Process.waitpid2(pid)
                    exit status.exitcode
                ensure
                    if pid
                        Process.kill 'TERM', pid
                    end
                    if !$!
                        exit 0
                    end
                end
            end
        end

        # @return [ProgramID] the reference state
        attr_reader :current_state

        def initialize(current_state)
            @current_state = current_state
        end

        # Wait for changes
        def wait
            loop do
                if current_state.changed?
                    return
                end
                sleep 1
            end
        end
    end
end

