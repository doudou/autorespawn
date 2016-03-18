require 'test_helper'
require 'autorespawn/program_id'

class Autorespawn
    describe Manager do
        subject { Manager.new }
        
        def start_slave(cmd, pid: 42)
            slave = subject.add_slave('cmd')
            slave = flexmock(slave)
            slave_pid = nil
            slave.should_receive(:pid).and_return { slave_pid }
            slave.should_receive(:spawn).once.and_return do
                slave_pid = pid
                nil
            end
            subject.poll
            slave
        end

        describe "#collect_finished_slaves" do
            it "calls #finished on the terminated slave and returns the list of terminated slaves" do
                slave = start_slave 'cmd', pid: 20
                flexmock(Process).should_receive(:waitpid2).and_return([20, status = flexmock], nil)
                slave.should_receive(:finished).once.with(status).and_return([])
                assert_equal [slave], subject.collect_finished_slaves
            end

            it "removes the terminated slave from the active_slaves list" do
                slave = start_slave 'cmd', pid: 20
                flexmock(Process).should_receive(:waitpid2).and_return([20, status = flexmock], nil)
                slave.should_receive(:finished).once.with(status).and_return([])
                subject.collect_finished_slaves
                assert_equal Hash[Process.pid => subject.self_slave], subject.active_slaves
            end

            it "calls the :on_slave_finished hook with the finished slave" do
                slave = start_slave 'cmd', pid: 20
                flexmock(Process).should_receive(:waitpid2).and_return([20, status = flexmock], nil)
                slave.should_receive(:finished).once.with(status).and_return([])

                recorder = flexmock do |r|
                    r.should_receive(:finished).with(slave).once
                end

                subject.on_slave_finished { |slave| recorder.finished(slave) }
                subject.collect_finished_slaves
            end

            it "explicitely marks a slave whose tracked files have not been modified as not needed" do
                # NOTE: calling #needed! if the slave changed is handled by Slave#finish
                subject.active_slaves[42] = (slave = flexmock(subcommands: [], program_id: ProgramID.new))
                flexmock(Process).should_receive(:waitpid2).and_return([42, flexmock], nil)
                slave.should_receive(:each_tracked_file)
                slave.should_receive(:finished).and_return([])
                slave.should_receive(:needed!).never
                slave.should_receive(:not_needed!).once
                subject.collect_finished_slaves
            end

            it "registers the tracked files of a worker whose tracked files have been modified" do
                subject.active_slaves[42] = (slave = flexmock(subcommands: [], program_id: ProgramID.new))
                flexmock(Process).should_receive(:waitpid2).and_return([42, flexmock], nil)
                slave.should_receive(:each_tracked_file).with(Hash[with_status: true], any).
                    and_yield(['/path', mtime = Time.now, 10])
                slave.should_receive(:finished).and_return([flexmock])
                subject.collect_finished_slaves
                assert subject.tracked_files.empty?
            end

            it "registers the tracked files after a worker finishes" do
                subject.active_slaves[42] = (slave = flexmock(subcommands: [], program_id: ProgramID.new, not_needed!: nil))
                flexmock(Process).should_receive(:waitpid2).and_return([42, flexmock], nil)
                slave.should_receive(:each_tracked_file).with(Hash[with_status: true], any).
                    and_yield(['/path', mtime = Time.now, 10])
                slave.should_receive(:finished).and_return([])
                subject.collect_finished_slaves

                assert_equal mtime, subject.tracked_files['/path'].mtime
                assert_equal 10, subject.tracked_files['/path'].size
                assert_equal [slave], subject.tracked_files['/path'].slaves
            end
        end

        describe "#on_slave_start" do
            it "calls the on_slave_start hook with the already started slaves" do
                slave = subject.add_slave('cmd')
                flexmock(slave).should_receive(:spawn)
                subject.poll
                recorder = flexmock do |r|
                    r.should_receive(:started).with(subject.self_slave).once
                    r.should_receive(:started).with(slave).once
                end
                subject.on_slave_start { |slave| recorder.started(slave) }
            end
        end

        describe '#poll' do
            it "spawns new workers" do
                slave = subject.add_slave('cmd')
                flexmock(slave).should_receive(:spawn).once
                assert_equal [[slave], Array.new], subject.poll
            end

            it "marks new workers as active" do
                slave = subject.add_slave('cmd')
                flexmock(slave).should_receive(:spawn).once
                subject.poll
                assert subject.active?(slave)
            end

            it "calls the on_slave_start hook with the self slave" do
                recorder = flexmock do |r|
                    r.should_receive(:started).with(subject.self_slave).once
                end
                subject.on_slave_start { |slave| recorder.started(slave) }
            end

            it "calls the on_slave_start hook with the started slave" do
                slave = subject.add_slave('cmd')
                flexmock(slave).should_receive(:spawn)
                recorder = flexmock do |r|
                    r.should_receive(:started).with(subject.self_slave).once
                    r.should_receive(:started).with(slave).once
                end
                subject.on_slave_start { |slave| recorder.started(slave) }
                subject.poll
            end

            it "returns even if there is not enough slaves to fill all the available slots" do
                subject.poll
            end

            def mock_slave_finished(slave)
                flexmock(Process).should_receive(:waitpid2).and_return([slave.pid, status = flexmock], nil)
                flexmock(slave).should_receive(:finished).once.with(status).and_return([])
            end

            it "registers subcommands from the slave to the worker list" do
                slave = start_slave 'cmd', pid: 20
                mock_slave_finished(slave)
                ret = [['testname', ['cmd'], Hash.new]]
                slave.should_receive(:subcommands).and_return(ret)

                flexmock(subject).should_receive(:add_slave).once.
                    with('cmd', name: 'testname')
                subject.collect_finished_slaves
            end

            it "executes only queued workers if autospawn is false" do
                subject.parallel_level = 10
                normal_slave = subject.add_slave('normal')
                flexmock(normal_slave).should_receive(:spawn).never
                queued_slave = subject.add_slave('cmd')
                flexmock(queued_slave).should_receive(:spawn).once
                subject.queue(queued_slave)
                subject.poll(autospawn: false)
            end

            it "executes queued workers first even if autospawn is true" do
                subject.parallel_level = 1
                normal_slave = subject.add_slave('normal')
                flexmock(normal_slave).should_receive(:spawn).never
                queued_slave = subject.add_slave('cmd')
                flexmock(queued_slave).should_receive(:spawn).once
                subject.queue(queued_slave)
                subject.poll
            end

            it "executes failed workers first" do
                subject.parallel_level = 1
                normal_slave = subject.add_slave('normal')
                flexmock(normal_slave).should_receive(:spawn).never
                failed_slave = subject.add_slave('failed')
                flexmock(failed_slave, success?: false, finished?: true).should_receive(:spawn).once

                subject.poll
            end
        end

        describe "#trigger_slaves_as_necessary" do
            it "marks new workers as needed if the associated tracked files have changed" do
                subject.tracked_files['/entry'] = flexmock(
                    update: true,
                    slaves: [slave = flexmock])
                slave.should_receive(:needed? => false)
                slave.should_receive(:needed!).once

                subject.trigger_slaves_as_necessary
                assert subject.tracked_files.empty?
            end

            it "removes slaves that are already marked as needed before calling #update" do
                subject.tracked_files['/entry'] = flexmock(slaves: [flexmock(:needed? => true)])
                subject.trigger_slaves_as_necessary
                assert subject.tracked_files.empty?
            end
        end

        describe "#run" do
            it "kills active workers on exception" do
                slave = subject.add_slave('cmd')
                flexmock(slave).should_receive(:spawn).once.ordered
                subject.poll
                flexmock(slave).should_receive(:kill).once.ordered
                flexmock(subject).should_receive(:poll).and_raise(RuntimeError)
                assert_raises(RuntimeError) do
                    subject.run
                end
            end
        end

        describe "#on_slave_new" do
            it "calls the callback with the current list of slaves" do
                slave = subject.add_slave('cmd', name: name)
                recorder = flexmock do |r|
                    r.should_receive(:called).with(subject.self_slave).once
                    r.should_receive(:called).with(slave).once
                end
                subject.on_slave_new { |slave| recorder.called(slave) }
            end
        end

        describe "#add_slave" do
            it "calls new slave callbacks when called" do
                name = flexmock
                recorder = flexmock do |r|
                    r.should_receive(:called).once.with(subject.self_slave)
                    r.should_receive(:called).once.with(->(slave) { slave.name == name && slave.cmdline == ['cmd'] })
                end
                subject.on_slave_new { |slave| recorder.called(slave) }
                subject.add_slave('cmd', name: name)
            end
        end

        describe "#active?" do
            let(:slave) { subject.add_slave('cmd') }

            it "returns false for a worker that is not active" do
                assert !subject.active?(slave)
            end
            it "returns false for a slave not even included in the manager" do
                subject.remove_slave(slave)
                assert !subject.active?(slave)
            end
        end

        describe "#remove_slave" do
            attr_reader :slave

            before do
                @slave = subject.add_slave('cmd')
            end

            it "raises ArgumentError if the slave is still active" do
                flexmock(subject).should_receive(:active?).with(slave).and_return(true)
                assert_raises(ArgumentError) { subject.remove_slave(slave) }
            end

            it "removes the slave" do
                subject.remove_slave(slave)
                assert !subject.include?(slave)
            end

            it "calls on_slave_removed with the slave" do
                recorder = flexmock do |r|
                    r.should_receive(:called).with(slave).once
                end
                subject.on_slave_removed { |slave| recorder.called(slave) }
                subject.remove_slave(slave)
            end
        end

        describe "#has_active_slaves?" do
            it "returns true if some slaves are spawned, ignoring the self slave" do
                assert !subject.has_active_slaves?
                slave = subject.add_slave('cmd')
                assert !subject.has_active_slaves?
                flexmock(slave).should_receive(:spawn)
                subject.poll
                assert subject.has_active_slaves?
            end
        end

        describe "#slave_count" do
            it "returns the count of slaves, ignoring the self slave" do
                assert_equal 0, subject.slave_count
                subject.add_slave('cmd')
                assert_equal 1, subject.slave_count
            end
            it "returns true if a slave has been added explicitely" do
                subject.add_slave('cmd')
                assert subject.has_slaves?
            end
        end
        describe "#has_slaves?" do
            it "returns false if no slave has been added explicitely, ignoring the self slave" do
                assert !subject.has_slaves?
            end
            it "returns true if a slave has been added explicitely" do
                subject.add_slave('cmd')
                assert subject.has_slaves?
            end
        end
    end
end

