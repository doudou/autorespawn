class Autorespawn
    # Functionality to watch a program for change
    class Watch
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

