class Autorespawn
    # Manager of a bunch of autorespawn slaves
    class Manager
        # @param [Integer] the number of processes allowed to work in parallel
        attr_reader :parallel_level
        # @return [Array<Slave>] declared worker processes, as a hash from
        #   the PID to a Slave object
        attr_reader :workers
        # @return [Hash<Slave>] list of active slaves
        attr_reader :active_slaves
        # @return [Array<#call>] list of callbacks that will be called with new
        #   slaves when they are added
        attr_reader :slave_registration_callbacks

        def initialize(parallel_level: 1)
            @parallel_level = parallel_level
            @workers   = Array.new
            @active_slaves = Hash.new
            @slave_registration_callbacks = Array.new
        end

        # Register a callback that should be called when a new slave has been
        # added by {#add_slave}
        #
        # @param [#call] block the callback
        # @yieldparam [Slave] the new slave
        def on_new_slave(&block)
            slave_registration_callbacks << block
        end

        # Spawns a worker, i.e. a program that will perform the intended work
        # and report the program state
        #
        # @param [Object] name an arbitrary object that can be used for
        #   reporting / tracking
        def add_slave(*cmdline, name: nil, **spawn_options)
            slave = Slave.new(*cmdline, name: name, **spawn_options)
            workers << slave
            slave_registration_callbacks.each do |callback|
                callback.call(slave)
            end
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

