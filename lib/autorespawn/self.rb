class Autorespawn
    # A Slave-compatible object that represents the manager's process itself
    class Self < Slave
        def initialize(*args, **options)
            super

            @pid = Process.pid
        end

        def needs_spawn?; false end
        def spawn
            pid
        end
        def kill
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
