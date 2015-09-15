require 'test_helper'
require 'autorespawn/program_id'

describe Autorespawn do
    describe '#autorespawn' do
        after do
            if @pid
                begin Process.kill 'TERM', @pid
                rescue Errno::ESRCH
                end
            end
        end

        it "executes the block once" do
            # spawn_test_program expects a PID as output and will fail if
            # not
            spawn_test_program
        end

        it "executes the each time the source file changes" do
            r, child_pid, required_file = spawn_test_program
            required_file.write "puts \'RELOADED\'"
            required_file.flush
            assert_outputs "RELOADED\n#{child_pid}\n", r
        end

        it "does not execute the block on load error, but reexecutes if a file changes" do
            r, child_pid, required_file = spawn_test_program

            required_file.puts "puts \'ERROR\'; raise"
            required_file.flush
            assert_outputs "ERROR\n", r

            required_file.rewind
            required_file.truncate(0)
            required_file.write "puts \'RELOADED\'"
            required_file.flush
            assert_outputs("RELOADED\n#{child_pid}\n", r)
        end

        def test_dir
            File.expand_path(File.dirname(__FILE__))
        end

        def test_program_path
            File.expand_path('reload_test_program', test_dir)
        end

        def assert_outputs(matcher, io, timeout: 5)
            buffer = ""
            remaining_timeout = timeout
            start = Time.now
            while remaining_timeout > 0
                select [io], [], [], remaining_timeout
                begin
                    while s = io.read_nonblock(1)
                        buffer += s
                        if matcher === buffer
                            return buffer
                        end
                    end
                rescue IO::WaitReadable
                end
                remaining_timeout = timeout - (Time.now - start)
            end
            assert(false, "expected to receive something matching #{matcher.inspect}, but received #{buffer.inspect}")
        end

        def spawn_test_program
            required_file = Tempfile.open ['autorespawn', '.rb']
            r, w = IO.pipe
            @pid = Kernel.spawn Hash['TEST_REQUIRE' => required_file.path, 'TEST_NAME' => self.name],
                test_program_path, "-I#{test_dir}", out: w
            w.close
            string = assert_outputs /^\d+\n/, r
            return r, Integer(string), required_file
        end
    end
end
