class Autorespawn
    # Manager of a bunch of autorespawn slaves
    class Manager
        include Hooks
        include Hooks::InstanceHooks

        # @return [ProgramID] a seed object that is passed to new slaves to
        #   represent the currently known state of file, to avoid unnecessary
        #   respawning
        #
        # @see add_seed_file
        attr_reader :seed
        # @return [Object] an object that is used to identify the manager itself
        attr_reader :name
        # @return [Self] an object that has the same API than [Slave] to
        #   represent the manager's process itself. It is always included in
        #   {#workers} and {#active_slaves}
        attr_reader :self_slave
        # @return [Integer] the number of processes allowed to work in parallel
        attr_reader :parallel_level
        # @return [Array<Slave>] declared worker processes, as a hash from
        #   the PID to a Slave object
        attr_reader :workers
        # @return [Hash<Slave>] list of active slaves
        attr_reader :active_slaves

        # @!group Hooks

        # Register a callback for when a new slave is added by {#add_slave}
        #
        # @param [#call] block the callback
        # @yieldparam [Slave] the new slave
        def on_slave_new(&block)
            __on_slave_new(&block)
            workers.each do |w|
                block.call(w)
            end
        end
        define_hooks :__on_slave_new

        # Register a callback that should be called when a new slave has been
        # spawned by {#poll}
        #
        # @param [#call] block the callback
        # @yieldparam [Slave] the newly started slave
        def on_slave_start(&block)
            __on_slave_start(&block)
            active_slaves.each_value do |w|
                block.call(w)
            end
        end
        define_hooks :__on_slave_start
        
        # @!method on_slave_finished
        #
        # Hook called when a slave finishes
        #
        # @yieldparam [Slave] the slave
        define_hooks :on_slave_finished
        
        # @!method on_slave_removed
        #
        # Hook called when a slave has been removed from this manager
        #
        # @yieldparam [Slave] the slave
        define_hooks :on_slave_removed

        # @!endgroup

        def initialize(name: nil, parallel_level: 1)
            @parallel_level = parallel_level + 1
            @workers   = Array.new
            @name = name
            @seed = ProgramID.for_self

            @self_slave = Self.new(name: name)
            @workers << self_slave
            @active_slaves = Hash[self_slave.pid => self_slave]
        end

        # Add files to {#seed}
        #
        # (see ProgramID#register_files)
        def register_seed_files(files, search_patch = seed.ruby_load_path, ignore_not_found: true)
            seed.register_files(files, search_path, ignore_not_found)
        end

        # Tests whether this slave is registered as a worker on self
        def include?(slave)
            workers.include?(slave)
        end

        # Tests whether this slave is currently active on self
        def active?(slave)
            active_slaves[slave.pid] == slave
        end

        # Spawns a worker, i.e. a program that will perform the intended work
        # and report the program state
        #
        # @param [Object] name an arbitrary object that can be used for
        #   reporting / tracking
        def add_slave(*cmdline, name: nil, **spawn_options)
            slave = Slave.new(*cmdline, name: name, seed: seed, **spawn_options)
            register_slave(slave)
            slave
        end

        # Remove a worker from this manager
        #
        # @raise [ArgumentError] if the slave is still running
        def remove_slave(slave)
            if active?(slave)
                raise ArgumentError, "#{slave} is still running"
            end
            workers.delete(slave)
            run_hook :on_slave_removed, slave
        end

        # @api private
        #
        # Registers a slave
        def register_slave(slave)
            workers << slave
            run_hook :__on_slave_new, slave
            slave
        end

        # @api private
        #
        # Collect information about the finished slaves
        #
        # @return [Array<Slave>] the slaves that finished
        def collect_finished_slaves
            finished_slaves = Array.new
            while finished_child = Process.waitpid2(-1, Process::WNOHANG)
                pid, status = *finished_child
                if slave = active_slaves.delete(pid)
                    finished_slaves << slave
                    slave.finished(status)
                    slave.subcommands.each do |name, cmdline, spawn_options|
                        add_slave(*cmdline, name: name, **spawn_options)
                    end
                    seed.merge!(slave.program_id)
                    run_hook :on_slave_finished, slave
                end
            end
            finished_slaves
        rescue Errno::ECHILD
            Array.new
        end

        def run
            while true
                poll
                sleep 1
            end

        rescue Interrupt
        ensure
            active_slaves.values.each do |slave|
                slave.kill
            end
        end

        # Wait for children to terminate and spawns them when needed
        def poll
            finished_slaves = collect_finished_slaves
            new_slaves = Array.new
            while active_slaves.size < parallel_level
                if slave_i = workers.index { |s| s.needs_spawn? }
                    slave = workers.delete_at(slave_i)
                    @workers = workers[slave_i..-1] + workers[0, slave_i] + [slave]
                    slave.spawn
                    run_hook :__on_slave_start, slave
                    new_slaves << slave
                    active_slaves[slave.pid] = slave
                else
                    break
                end
            end
            return new_slaves, finished_slaves
        end
    end
end

