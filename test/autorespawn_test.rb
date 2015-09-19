require 'test_helper'
require 'autorespawn/program_id'

describe Autorespawn do
    describe '#run' do
        after do
            if @pid
                Process.waitpid2 @pid
            end
        end

        it "passes slave definitions to a manager" do
            spawner = Autorespawn.new
            spawner.add_slave 'cmd', priority: 10

            manager = flexmock(Autorespawn::Manager).new_instances
            manager.should_receive(:add_slave).with('cmd', priority: 10).once
            manager.should_receive(:run).once.and_return(ret = flexmock)
            assert_equal ret, spawner.run
        end

        it "raises if using both #add_slave and a block" do
            spawner = Autorespawn.new
            spawner.add_slave 'cmd', priority: 10
            assert_raises(ArgumentError) { spawner.run { } }
        end

        it "executes the block once" do
            # spawn_test_program expects a PID as output and will fail if
            # not
            spawn_test_program(2)
        end

        it "executes the each time the source file changes" do
            r, child_pid, required_file = spawn_test_program(3)
            required_file.write "RESULT_IO.puts \'RELOADED\'"
            required_file.flush
            assert_outputs /^RELOADED\n#{child_pid}\n/, r
        end

        it "does not execute the block on load error, but reexecutes if a file changes" do
            r, child_pid, required_file = spawn_test_program(4)

            required_file.puts "RESULT_IO.puts \'ERROR\'; raise"
            assert_outputs /^ERROR\n/, r

            required_file.rewind
            required_file.truncate(0)
            required_file.write "RESULT_IO.puts \'RELOADED\'"
            assert_outputs(/^RELOADED\n#{child_pid}\n/, r)
        end

        def programs_dir
            File.expand_path('programs', File.dirname(__FILE__))
        end

        def test_program_path
            File.expand_path('standalone', programs_dir)
        end

        def assert_outputs(matcher, io, timeout: 5)
            buffer = ""
            remaining_timeout = timeout
            start = Time.now
            while remaining_timeout > 0
                select [io], [], [], remaining_timeout
                begin
                    while s = io.read_nonblock(10)
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

        def spawn_test_program(exit_level)
            required_file = Tempfile.open ['autorespawn', '.rb']
            required_file.sync = true
            r, w = IO.pipe
            env = Hash[
                'TEST_RESULT_IO' => w.fileno.to_s,
                'TEST_REQUIRE' => required_file.path,
                'TEST_NAME' => self.name]
            @pid = Kernel.spawn env, test_program_path, '--exit-level', exit_level.to_s, w => w
            w.close
            string = assert_outputs /^\d+\n/, r
            return r, Integer(string), required_file
        end
    end
end

