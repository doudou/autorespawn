class Autorespawn
    # A Slave-compatible object that represents the manager's process itself
    class Self < Slave
        def initialize(*args, **options)
            super

            @pid = Process.pid
        end

        def needed?(*); false end
        def needed!; end
        def spawn
            pid
        end
        def write_initial_dump
            true
        end
        def kill(*, **)
        end
        def join
        end
        def running?
            true
        end
        def finished?
            false
        end
    end
end
