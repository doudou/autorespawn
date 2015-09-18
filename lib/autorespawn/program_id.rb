require 'autorespawn/program_id'
require 'pathname'
require 'digest/sha1'

class Autorespawn
    # Management of the ID of a complete Ruby program
    #
    # It basically stores information about all the files that form this
    # program.
    class ProgramID
        FileInfo = Struct.new :require_path, :path, :mtime, :size, :id

        # Information about the files that form this program
        #
        # @return [Hash<Pathname,FileInfo>]
        attr_reader :files

        def initialize
            @files = Hash.new
        end

        # Compute ID information abou thte current Ruby process
        def self.for_self
            id = ProgramID.new
            id.register_loaded_features
            id
        end

        # Whether this program ID tracks some files
        def empty?
            files.empty?
        end

        # Remove all tracked files
        def clear
            files.clear
        end

        # Registers the file information for all loaded features
        # 
        # @return [void]
        def register_loaded_features
            search_path = ruby_load_path
            $LOADED_FEATURES.each do |file|
                # enumerator.so is listed in $LOADED_FEATURES but is not present
                # on disk ... no idea
                begin
                    begin
                        register_file(Pathname.new(file))
                    rescue FileNotFound => e
                        STDERR.puts "WARN: could not find #{e.path} in ruby search path, ignored"
                    end
                end
            end
        end

        # Register a set of files
        #
        # @param [Array<String>] files the list of files
        # @param [Array<String>] search_path the path to resolve relative paths
        # @param [Boolean] ignore_not_found whether files that cannot be
        #   resolved are ignored or cause a FileNotFound exception
        # @return [Boolean] whether the program ID has been modified
        def register_files(files, search_path = ruby_load_path, ignore_not_found: true)
            modified = false
            files.each do |path|
                begin modified = register_file(path, search_path) || modified
                rescue FileNotFound
                    raise if !ignore_not_found
                end
            end
            modified
        end

        # Registers file information for one file
        #
        # @param [Pathname] file the path to the file
        # @return [Boolean] whether the registration modified the program ID's
        #   state
        def register_file(file, search_path = ruby_load_path)
            info = file_info(file, search_path)
            modified = (files[info.path] != info)
            files[info.path] = info
            @id = nil if modified
            modified
        end

        # Update the information about all the files registered on this object
        def refresh
            updated = Hash.new
            files.each_key do |info|
                next if !info.path.exist?
                info = file_info(info.path)
                updated[info.path] = info
            end
            @files = updated
            @id = nil
            updated
        end

        # Enumerate the path of all the files that are being tracked
        #
        # @yieldparam [Pathname] path
        def each_tracked_file(&block)
            files.keys.each(&block)
        end

        # Returns a string that can ID this program
        def id
            return @id if @id

            complete_id = files.keys.sort.map do |p|
                files[p].id
            end.join("")
            @id = Digest::SHA1.hexdigest(complete_id)
        end

        # Whether the state on disk is different than the state stored in self
        def changed?
            files.each_value do |info|
                return true if !info.path.exist?
                stat = info.path.stat
                if stat.mtime != info.mtime || stat.size != info.size
                    new_id = compute_file_id(info.path)
                    return new_id != info.id
                end
            end
            false
        end

        def include?(path, search_path = ruby_load_path)
            files.has_key?(resolve_file_path(path, search_path))
        end

        # @api private
        #
        # Given a path that may be relative, computes the full path to the
        # corresponding file
        #
        # @param [Pathname] path the file path
        # @param [Array<Pathname>] search_path the search path to use to resolve
        #   relative paths
        # @return [void]
        # @raise FileNotFound when a relative path cannot be resolved into a
        #   global one
        def resolve_file_path(path, search_path = Array.new)
            if !path.absolute?
                search_path.each do |search_p|
                    full = search_p + path
                    if full.exist?
                        return full
                    end
                end
                raise FileNotFound.new(path, search_path), "cannot find #{path} in #{search_path.join(", ")}"
            elsif !path.exist?
                raise FileNotFound.new(path, []), "#{path} does not exist"
            else
                return path
            end
        end

        # The ruby load path
        #
        # @param [Array<Pathname>]
        def ruby_load_path
            $LOAD_PATH.map { |p| Pathname.new(p) }
        end

        # Resolve file information about a single file
        #
        # @param [Pathname] path the path to the file
        # @param [Array<Pathname>] search_path the search path to use to resolve
        #    'path' if it is relative
        # @return [FileInfo]
        def file_info(path, search_path = ruby_load_path)
            resolved = resolve_file_path(path, search_path)
            stat = resolved.stat
            id   = compute_file_id(resolved)
            return FileInfo.new(path, resolved, stat.mtime, stat.size, id)
        end

        # @api private
        #
        # Compute the content ID of a text (code) file
        def compute_text_file_id(file)
            sanitized = file.readlines.map do |line|
                # Remove unnecessary spaces
                line = line.strip
                line = line.gsub(/\s\s+/, ' ')
                if !line.empty?
                    line
                end
            end.compact
            Digest::SHA1.hexdigest(sanitized.join("\n"))
        end

        # @api private
        #
        # Compute the content ID of a binary file
        def compute_binary_file_id(file)
            Digest::SHA1.hexdigest(file.read(enc: 'BINARY'))
        end
    
        # Compute a SHA1 that is representative of the file's contents
        #
        # It does some whitespace cleanup, but is not meant to be super-robust
        # to changes that are irrelevant to the end program
        #
        # @param [Pathname] file the path to the file
        # @return [String] an ID string
        def compute_file_id(file)
            if file.extname == ".rb"
                compute_text_file_id(file)
            else
                compute_binary_file_id(file)
            end
        end
    end
end
