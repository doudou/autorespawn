require 'test_helper'

class Autorespawn
    describe Slave do
        def programs_dir; File.expand_path('programs', File.dirname(__FILE__)) end

        def slave(*cmdline, **spawn_options)
            register_slave(slave = Slave.new(*cmdline))
            slave
        end

        def register_slave(slave)
            @slaves << slave
        end

        before do
            @slaves = Array.new
            # For code coverage inside the subprocesses
            ENV['TEST_NAME'] = self.name
        end

        after do
            ENV.delete('TEST_NAME')
            @slaves.each do |slave|
                if slave.running?
                    slave.kill
                end
            end
        end

        describe "#spawn" do
            it "raises on an already-running slave" do
                slave = slave(File.join(programs_dir, 'slave'), '--exit', '1')
                flexmock(slave).should_receive(:running?).and_return(true)
                assert_raises(AlreadyRunning) { slave.spawn }
            end

            it "calling it on an already-running slave does not interfere with the slave" do
                slave = slave(File.join(programs_dir, 'slave'), '--exit', '1')
                slave.spawn
                assert_raises(AlreadyRunning) { slave.spawn }
                assert slave.running?
                slave.join
                assert slave.success?
                assert slave.finished?
                assert_equal 1, slave.status.exitstatus
            end
            it "starts and joins the slave" do
                slave = slave(File.join(programs_dir, 'slave'), '--exit', '1')
                slave.spawn
                assert slave.running?
                assert !slave.finished?
                slave.join
                assert slave.success?
                assert slave.finished?
                assert_equal 1, slave.status.exitstatus
                assert slave.program_id.empty?, "the slave's program ID was expected to be empty, but is tracking #{slave.program_id.files.keys.join("\n  ")}"
                assert !slave.needed?
            end

            it "handles slaves that terminate unexpectedly, not under Autorespawn supervision" do
                slave = slave(File.join(programs_dir, 'slave'), '--terminate', '1')
                slave.spawn
                slave.join
                assert !slave.success?
                assert_equal 1, slave.status.exitstatus
                assert slave.program_id.empty?, "the slave's program ID was expected to be empty, but is tracking #{slave.program_id.files.keys.join("\n  ")}"
                assert !slave.needed?
            end

            it "adds discovered requires to the program ID" do
                Tempfile.open ['autorespawn_required_file', '.rb'] do |io|
                    slave = slave(File.join(programs_dir, 'slave'), '--require', io.path)
                    slave.spawn
                    slave.join
                    assert slave.success?
                    assert slave.program_id.include?(Pathname.new(io.path))
                    assert slave.needed?
                end
            end

            it "adds discovered subcommands" do
                slave = slave(File.join(programs_dir, 'slave'), '--subcommand', 'ls')
                slave.spawn
                slave.join
                assert slave.success?
                assert_equal [['ls', ['ls'], Hash.new]], slave.subcommands
            end
        end

        describe "#success?" do
            it "raises on a fresh slave object" do
                assert_raises(NotFinished) { Slave.new('cmd').success? }
            end
            it "raises on a running slave object" do
                slave = Slave.new('cmd')
                flexmock(slave).should_receive(:running?).and_return(true)
                assert_raises(NotFinished) { slave.success? }
            end
        end

        describe "#needed?" do
            it "is set on a fresh slave object" do
                assert Slave.new('cmd').needed?
            end
            it "is false if the slave is running" do
                slave = flexmock(Slave.new('cmd'))
                slave.should_receive(:running?).and_return(true)
                assert !slave.needed?
            end
            it "is set to true by #needed!" do
                slave = Slave.new('cmd')
                slave.not_needed!
                assert !slave.needed?
                slave.needed!
                assert slave.needed?
            end
            it "is true if the program ID changed" do
                slave = Slave.new('cmd')
                slave.not_needed!
                assert !slave.needed?
                flexmock(slave).should_receive(:program_id).and_return(flexmock(:changed? => true))
                assert slave.needed?
            end
        end
    end
end

