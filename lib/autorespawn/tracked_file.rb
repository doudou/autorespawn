class Autorespawn
    class TrackedFile
        attr_reader :path, :mtime, :size, :slaves

        def initialize(path, mtime: nil, size: nil)
            @path  = path
            @mtime = mtime
            @size  = size
            @slaves = Array.new
        end

        def update
            return true if !path.exist?
            return true if !mtime

            stat = path.stat
            if stat.mtime != mtime || stat.size != size
                @mtime = stat.mtime
                @size  = stat.size
                true
            end
        end
    end
end

