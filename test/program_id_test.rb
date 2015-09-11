require 'test_helper'
require 'ruby_program_watch/program_id'
require 'fakefs/safe'

module RubyProgramWatch
    describe ProgramID do
        subject { ProgramID.new }

        before do
            FakeFS.activate!
        end

        after do
            FakeFS.deactivate!
            FakeFS::FileSystem.clear
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

            it "resolves the file" do
                info = subject.file_info(path, search_path)
                assert_equal path, info.require_path
                assert_equal full_path, info.path
            end

            it "computes the file ID based on the full path" do
                flexmock(subject).should_receive(:compute_file_id).with(full_path).
                    once.and_return("the file ID")
                info = subject.file_info(path, search_path)
                assert_equal "the file ID", info.id
            end
        end

        describe "#compute_file_id" do
            it "sanitizes spaces before computing the hash" do
                File.open('/file', 'w') do |io|
                    io.puts
                    io.puts "  "
                    io.puts "    line  "
                    io.puts "   two  three"
                    io.puts "\t  and   four\t"
                    io.puts
                end
                expected = ["line", "two three", "and four"].join("\n")
                assert_equal Digest::SHA1.hexdigest(expected),
                    subject.compute_file_id(Pathname.new('/file'))
            end
        end

        describe "#id" do
            before do
                FileUtils.mkdir_p '/path/to'
                FileUtils.touch '/path/to/file1'
                FileUtils.touch '/path/to/file2'
            end

            it "is an aggregate of the registered files" do
                flexmock(subject).should_receive(:compute_file_id).
                    and_return('an ID', 'another ID')
                subject.register_file(Pathname.new('/path/to/file1'))
                subject.register_file(Pathname.new('/path/to/file2'))
                assert_equal Digest::SHA1.hexdigest('an IDanother ID'),
                    subject.id
            end
            it "is recomputed when the list of files changes" do
                flexmock(subject).should_receive(:compute_file_id).
                    and_return('an ID', 'another ID')
                subject.register_file(Pathname.new('/path/to/file1'))
                assert_equal Digest::SHA1.hexdigest('an ID'),
                    subject.id
                subject.register_file(Pathname.new('/path/to/file2'))
                assert_equal Digest::SHA1.hexdigest('an IDanother ID'),
                    subject.id
            end
            it "is independent of the registration order" do
                flexmock(subject).should_receive(:compute_file_id).
                    and_return('another ID', 'an ID')
                subject.register_file(Pathname.new('/path/to/file2'))
                subject.register_file(Pathname.new('/path/to/file1'))
                assert_equal Digest::SHA1.hexdigest('an IDanother ID'),
                    subject.id
            end
        end

        describe "#changed?" do
            before do
                FileUtils.mkdir_p '/path/to'
                FileUtils.touch '/path/to/file1'
                FileUtils.touch '/path/to/file2'
            end

            it "returns false if only the mtime changes" do
                p = Pathname.new('/path/to/file1')
                flexmock(subject).should_receive(:compute_file_id).
                    and_return('an ID', 'an ID')
                subject.register_file(p)
                FileUtils.touch p
                assert !subject.changed?
            end
            it "does not evaluate the file ID if the mtime and size did not change" do
                flexmock(subject).should_receive(:compute_file_id).
                    and_return('an ID', 'another ID')
                subject.register_file(Pathname.new('/path/to/file1'))
                assert !subject.changed?
            end
            it "returns true if both the stat and ID change" do
                flexmock(subject).should_receive(:compute_file_id).
                    and_return('an ID', 'another ID')
                subject.register_file(Pathname.new('/path/to/file1'))
                FileUtils.touch p
                assert !subject.changed?
            end
        end
    end
end
