class Autorespawn
    # Representation of an autorespawn-aware subprocess that is started by a
    # {Manager}
    #
    # Slaves have two roles: the one of discovery (what are the commands that
    # need to be started) and the one of 
    class Slave
        # The slave's name
        #
        # It is an arbitrary object useful for reporting/tracking
        #
        # @return [Object]
        attr_reader :name
        # The currently known program ID
        attr_reader :program_id
        # The command line of the subprocess
        attr_reader :cmdline
        # Environment that should be set in the subprocess
        attr_reader :spawn_env
        # Options that should be passed to Kernel.spawn
        attr_reader :spawn_options
        # @return [nil,Integer] pid the PID of the current process or of the
        #   last process if it is finished. It is non-nil only after {#spawn} has
        #   been called
        attr_reader :pid
        # @return [Process::Status] the exit status of the last run. Is nil
        #   while the process is running
        attr_reader :status

        # @return [Array<String>] a list of commands that this slave requests
        attr_reader :subcommands

        # @api private
        #
        # @return [IO] the result I/O
        attr_reader :result_r
        # @api private
        #
        # @return [String] the result data as received
        attr_reader :result_buffer

        # @param [Object] name an arbitrary object that can be used for
        #   reporting / tracking reasons
        # @param [ProgramID] seed a seed object with some relevant files already
        #   registered, to avoid respawning the slave unnecessarily.
        def initialize(*cmdline, name: nil, seed: ProgramID.new, env: Hash.new, **spawn_options)
            @name = name
            @program_id = seed.dup
            @cmdline    = cmdline
            @needed = true
            @spawn_env     = env
            @spawn_options = spawn_options
            @subcommands = Array.new
            @pid        = nil
            @status     = nil
            @result_r  = nil
            @result_buffer = nil
        end

        def inspect
            "#<Autorespawn::Slave #{object_id.to_s(16)} #{cmdline.join(" ")}>"
        end

        # Enumerate the files that are tracked for {#needed?}
        def each_tracked_file(with_status: false, &block)
            @program_id.each_tracked_file(with_status: with_status, &block)
        end

        def to_s; inspect end

        # Register files on the program ID
        #
        # (see ProgramID#register_files)
        def register_files(files, search_path = program_id.ruby_load_path, ignore_not_found: true)
            program_id.register_files(files, search_path, ignore_not_found: ignore_not_found)
        end

        # Start the slave
        #
        # @return [Integer] the slave's PID
        def spawn
            if running?
                raise AlreadyRunning, "cannot call #spawn on #{self}: already running"
            end

            initial_r, initial_w = IO.pipe
            result_r, result_w = IO.pipe
            env = self.spawn_env.merge(
                SLAVE_INITIAL_STATE_ENV => initial_r.fileno.to_s,
                SLAVE_RESULT_ENV        => result_w.fileno.to_s)

            program_id.refresh
            @needed = nil
            pid = Kernel.spawn(env, *cmdline, initial_r => initial_r, result_w => result_w, **spawn_options)
            initial_r.close
            result_w.close
            Marshal.dump([name, program_id], initial_w)

            @pid = pid
            @status = nil
            @result_buffer = ''
            @result_r = result_r
            pid

        rescue Exception => e
            if pid
                Process.kill 'TERM', pid
            end
            result_r.close if result_r && !result_r.closed?
            raise

        ensure
            initial_r.close if initial_r && !initial_r.closed?
            initial_w.close if initial_w && !initial_r.closed?
            result_w.close  if result_w && !result_w.closed?
        end

        # Whether this slave would need to be spawned, either because it has
        # never be, or because the program ID changed
        def needed?
            if running? then false
            elsif !@needed.nil?
                @needed
            else program_id.changed?
            end
        end

        # Marks this slave for execution
        #
        # Note that it will only be executed by the underlying {Manager} when
        # (1) a slot is available and (2) it has stopped running
        #
        # This is usually not called directly, but through {Manager#queue} which
        # also ensures that the slave gets in front of the execution queue
        def needed!
            @needed = true
        end

        # Forces {#needed?} to return false
        #
        # Call {#needed_auto} to revert back to determining if the slave is
        # needed or not using the tracked files
        def not_needed!
            @needed = false
        end

        def needed_auto
            @needed = nil
        end

        # Whether the slave is running
        def running?
            pid && !status
        end

        # Whether the slave has already ran, and is finished
        def finished?
            pid && status
        end

        # Kill the slave
        #
        # @param [Boolean] join whether the method should wait for the child to
        #   end
        # @see join
        def kill(signal = 'TERM', join: true)
            Process.kill signal, pid
            if join
                self.join
            end
        end

        # Wait for the slave to terminate and call {#finished}
        def join
            _, status = Process.waitpid2(pid)
            finished(status)
        end

        # Whether the slave behaved properly
        #
        # This does *not* indicate whether the slave's intended work has been
        # done, only that it produced the data expected by Autorespawn. To check
        # the child's success w.r.t. its execution, check {#status}
        def success?
            if !status
                raise NotFinished, "called {#success?} on a #{pid ? 'running' : 'non-started'} child"
            end
            @success
        end

        # @api private
        #
        # Announce that the slave already finished, with the given exit status
        #
        # @param [Process::Status] the exit status
        # @return [Array<Pathname>] a set of files that either changed or got
        #   added since the call to {#spawn}. If not empty, the slave calls
        #   {#needed!} by itself to force a re-execution
        def finished(status)
            @status = status
            read_queued_result
            begin
                @subcommands, file_list = Marshal.load(result_buffer)
                @success = true
            rescue ArgumentError # "Marshal data too short"
                @subcommands = Array.new
                file_list = Array.new
                @success = false
            end
            @program_id = program_id.slice(file_list)
            modified = program_id.register_files(file_list)
            if !modified.empty?
                needed!
            end
            result_r.close
            modified
        end

        # @api private
        #
        # Queue any pending result data sent by the slave
        def read_queued_result
            while true
                result_buffer << result_r.read_nonblock(1024)
            end
        rescue IO::WaitReadable, EOFError
        end
    end
end



