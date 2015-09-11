module RubyProgramWatch
    # Exception raised when a path cannot be resolved to a file on disk
    class FileNotFound < RuntimeError
        # @return [Pathname] the path to resolve
        attr_reader :path
        # @return [Array<Pathname>] the search path that was provided to resolve
        #   {#path}. It is always empty if {#path} is absolute
        attr_reader :search_path

        def initialize(path, search_path)
            @path, @search_path = path, search_path
        end
    end
end
