require 'test_helper'
require 'ruby_program_watch/program_id'

module RubyProgramWatch
    describe Watch do
        describe 'autoreload' do
            after do
                if @pid
                    begin Process.kill 'TERM', @pid
                    rescue Errno::ESRCH
                    end
                end
            end

            it "executes the block once" do
                _, child_pid, _ = spawn_test_program
                refute child_pid.empty?, "the child process does not seem to have been successfully started"
            end

            it "executes the each time the source file changes" do
                r, child_pid, required_file = spawn_test_program
                required_file.write "puts \'RELOADED\'"
                required_file.flush
                new_child_output = r.readpartial(20)
                refute new_child_output.empty?
                lines = new_child_output.each_line.to_a
                assert_equal 2, lines.size
                assert_equal "RELOADED\n", lines.first
                # We're exec'ing, so the PID is the same
                assert Integer(child_pid) == Integer(lines.last)
            end

            def test_dir
                File.expand_path(File.dirname(__FILE__))
            end

            def reload_test_program
                File.expand_path('reload_test_program', test_dir)
            end

            def spawn_test_program
                required_file = Tempfile.open ['ruby_program_watch', '.rb']
                r, w = IO.pipe
                @pid = Kernel.spawn Hash['TEST_REQUIRE' => required_file.path],
                    reload_test_program, "-I#{test_dir}", out: w
                w.close
                return r, r.readpartial(10), required_file
            end
        end
    end
end
