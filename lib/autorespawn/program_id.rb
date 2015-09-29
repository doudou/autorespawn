require 'autorespawn/program_id'
require 'pathname'
require 'digest/sha1'

class Autorespawn
    # Management of the ID of a complete Ruby program
    #
    # It basically stores information about all the files that form this
    # program.
    class ProgramID
        FileInfo = Struct.new :require_path, :path, :mtime, :size

        # Information about the files that form this program
        #
        # @return [Hash<Pathname,FileInfo>]
        attr_reader :files

        def initialize
            @files = Hash.new
        end

        def initialize_copy(old)
            super
            @files = @files.dup
        end

        # Merge the information contained in another ProgramID object into self
        #
        # @param [ProgramID] id the object whose information we should merge
        # @return self
        def merge!(id)
            @files.merge!(id.files)
            @id = nil
            self
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
            loaded_features = $LOADED_FEATURES.map do |file|
                Pathname.new(file)
            end
            register_files(loaded_features)
        end

        # Resolve a file list into absolute paths
        def resolve_file_list(files, search_path = ruby_load_path, ignore_not_found: true)
            files.map do |path|
                begin resolve_file_path(path, search_path)
                rescue FileNotFound
                    raise if !ignore_not_found
                end
            end.compact
        end

        # Register a set of files
        #
        # @param [Array<String>] files the list of files
        # @param [Array<String>] search_path the path to resolve relative paths
        # @param [Boolean] ignore_not_found whether files that cannot be
        #   resolved are ignored or cause a FileNotFound exception
        # @return [Boolean] whether the program ID has been modified
        def register_files(files, search_path = ruby_load_path, ignore_not_found: true)
            modified = Array.new
            files = resolve_file_list(files, search_path, ignore_not_found: ignore_not_found)
            files.find_all do |path|
                register_file(path, search_path)
            end
        end

        # Removes any file in self that is not in the given file list and
        # returns the result
        def slice(files, search_path = ruby_load_path, ignore_not_found: true)
            result = dup
            files = resolve_file_list(files, search_path, ignore_not_found: ignore_not_found).
                to_set
            result.files.delete_if { |k, _| !files.include?(k) }
            result
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

            if modified
                @id = nil 
                info.path
            end
        end

        # Update the information about all the files registered on this object
        def refresh
            updated = Hash.new
            files.each_key do |path|
                next if !path.exist?
                info = file_info(path)
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
                "#{p}#{files[p].mtime}#{files[p].size}"
            end.join("")
            @id = Digest::SHA1.hexdigest(complete_id)
        end

        # Whether the state on disk is different than the state stored in self
        def changed?
            files.each_value.any? do |info|
                return true if !info.path.exist?
                stat = info.path.stat
                stat.mtime != info.mtime || stat.size != info.size
            end
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
            return FileInfo.new(path, resolved, stat.mtime, stat.size)
        end
    end
end
