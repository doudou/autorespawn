require 'test_helper'
require 'autorespawn/program_id'
require 'fakefs/safe'

class Autorespawn
    describe ProgramID do
        subject { ProgramID.new }

        before do
            FakeFS.activate!
        end

        after do
            FakeFS.deactivate!
            FakeFS::FileSystem.clear
        end

        def assert_equal(expected, value)
            assert(expected == value, "expected\n#{expected}\nand\n#{value}\nto be equal")
        end

        describe "#resolve_file_path" do
            describe "when the file exists" do
                before do
                    FileUtils.mkdir_p '/path/to'
                    FileUtils.touch '/path/to/file'
                end

                it "leaves absolute paths as-is" do
                    p = Pathname.new('/path/to/file')
                    assert_equal p, subject.resolve_file_path(p)
                end

                it "resolves a path to an existing file using the search_path" do
                    search = [Pathname.new('/path')]
                    p = Pathname.new('to/file')
                    assert_equal Pathname.new('/path/to/file'),
                        subject.resolve_file_path(p, search)
                end

                it "resolves the search path in order" do
                    FileUtils.mkdir_p '/another/to'
                    FileUtils.touch '/another/to/file'
                    search = [Pathname.new('/path'), Pathname.new('/another')]
                    p = Pathname.new('to/file')
                    assert_equal Pathname.new('/path/to/file'),
                        subject.resolve_file_path(p, search)
                end
            end

            describe "when the file does not exist" do
                it "raises FileNotFound if an absolute path does not exist" do
                    p = Pathname.new('/path/to/file')
                    e = assert_raises(FileNotFound) do
                        subject.resolve_file_path(p)
                    end
                    assert_equal p, e.path
                    assert e.search_path.empty?
                end

                it "raises FileNotFound if a relative path cannot be resolved" do
                    search = [Pathname.new('/path')]
                    p = Pathname.new('to/file')
                    e = assert_raises(FileNotFound) do
                        subject.resolve_file_path(p, search)
                    end
                    assert_equal p, e.path
                    assert_equal search, e.search_path
                end
            end
        end

        describe "#file_info" do
            attr_reader :path, :search_path, :full_path

            before do
                FileUtils.mkdir_p '/path/to'
                FileUtils.touch '/path/to/file'
                @path = Pathname.new('to/file')
                @search_path = [Pathname.new('/path')]
                @full_path = Pathname.new('/path/to/file')
            end

            it "creates a FileInfo object for the file" do
                info = subject.file_info(full_path)
                assert_equal full_path, info.path
            end
        end

        describe "#register_file" do
            attr_reader :dir, :path
            before do
                @dir = Pathname('/path/to')
                dir.mkpath
                @path = Pathname('/path/to/file1')
                FileUtils.touch(path.to_s)
            end

            it "returns the full path to the file if it was not registered" do
                assert_equal path, subject.register_file(path)
            end

            it "returns the full path to the file if it has changed" do
                subject.register_file(path)
                FileUtils.touch(path.to_s)
                assert_equal path, subject.register_file(path)
            end
            
            it "returns nil if a file was already registered and did not change" do
                subject.register_file(path)
                assert_nil subject.register_file(path)
            end
        end

        describe "#register_files" do
            attr_reader :dir, :paths
            before do
                @dir = Pathname('/path/to')
                dir.mkpath
                @paths = Array.new
                paths << Pathname('/path/to/file1')
                paths << Pathname('/path/to/file2')
                paths.each { |p| FileUtils.touch(p.to_s) }
            end
            it "registers all the provided filed" do
                subject.register_files(paths)
                paths.each do |p|
                    assert subject.include?(p)
                end
            end
            it "returns the list of full paths for those that got newly registered" do
                assert_equal paths,
                    subject.register_files(paths)
            end
            it "returns the list of full paths for those that changed" do
                subject.register_files(paths)
                FileUtils.touch(paths[0].to_s)
                assert_equal [paths[0]],
                    subject.register_files(paths)
            end
        end

        describe "#changed?" do
            before do
                FileUtils.mkdir_p '/path/to'
                FileUtils.touch '/path/to/file1'
                FileUtils.touch '/path/to/file2'
            end

            it "returns true if the mtime changes" do
                subject.register_file(p = Pathname.new('/path/to/file1'))
                FileUtils.touch p.to_s
                assert subject.changed?
            end
        end
    end
end

