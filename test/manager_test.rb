require 'test_helper'
require 'autorespawn/program_id'

class Autorespawn
    describe Manager do
        subject { Manager.new }
        
        def start_slave(cmd, pid: 42)
            slave = subject.add_slave('cmd')
            slave = flexmock(slave, needed?: true, pid: pid)
            slave.should_receive(:spawn).once
            subject.poll
            slave
        end

        describe "#collect_finished_slaves" do
            it "calls #finished on the terminated slave and returns the list of terminated slaves" do
                slave = start_slave 'cmd', pid: 20
                flexmock(Process).should_receive(:waitpid2).and_return([20, status = flexmock], nil)
                slave.should_receive(:finished).once.with(status)
                assert_equal [slave], subject.collect_finished_slaves
            end

            it "removes the terminated slave from the active_slaves list" do
                slave = start_slave 'cmd', pid: 20
                flexmock(Process).should_receive(:waitpid2).and_return([20, status = flexmock], nil)
                slave.should_receive(:finished).once.with(status)
                subject.collect_finished_slaves
                assert_equal Hash[Process.pid => subject.self_slave], subject.active_slaves
            end

            it "calls the :on_slave_finished hook with the finished slave" do
                slave = start_slave 'cmd', pid: 20
                flexmock(Process).should_receive(:waitpid2).and_return([20, status = flexmock], nil)
                slave.should_receive(:finished).once.with(status)

                recorder = flexmock do |r|
                    r.should_receive(:finished).with(slave).once
                end

                subject.on_slave_finished { |slave| recorder.finished(slave) }
                subject.collect_finished_slaves
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
                flexmock(slave).should_receive(:finished).once.with(status)
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

            it "reorders the workers array properly even if the active slave is the last one" do
                slaves = [subject.add_slave('cmd'), subject.add_slave('cmd')]
                flexmock(slaves[1]).should_receive(:needed?).and_return(true)
                flexmock(slaves[1]).should_receive(:spawn).once
                flexmock(slaves[0]).should_receive(:needed?).and_return(false)

                subject.poll
                assert_equal([subject.self_slave] + slaves, subject.workers)
            end

            it "reorders the workers array properly even if the active slave is the first one" do
                slaves = [subject.add_slave('cmd'), subject.add_slave('cmd')]
                flexmock(slaves[0]).should_receive(:needed?).and_return(true)
                flexmock(slaves[0]).should_receive(:spawn).once
                flexmock(slaves[1]).should_receive(:needed?).and_return(false)

                subject.poll
                assert_equal [slaves[1], subject.self_slave, slaves[0]], subject.workers
            end

            it "reorders the workers array to put the slaves before the executed one at the end" do
                slaves = (0..9).map do |i|
                    slave = subject.add_slave('cmd')
                    if i == 3
                        flexmock(slave).should_receive(:needed?).and_return(true)
                        flexmock(slave).should_receive(:spawn).once
                    else
                        flexmock(slave).should_receive(:needed?).and_return(false)
                        flexmock(slave).should_receive(:spawn).never
                    end
                    slave
                end
                before = slaves[0..2]
                slave  = slaves[3]
                after  = slaves[4..-1]

                subject.poll
                assert_equal 11, subject.workers.size
                assert_equal (after + [subject.self_slave] + before + [slave]), subject.workers
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

            it "returns true for an active slave" do
                mock_slave_active(slave)
                assert subject.active?(slave)
            end
            it "returns false for a worker that is not active" do
                assert !subject.active?(slave)
            end
            it "returns false for a slave not even included in the manager" do
                subject.remove_slave(slave)
                assert !subject.active?(slave)
            end
        end

        def mock_slave_active(slave)
            flexmock(slave).should_receive(:spawn)
            pid = rand(40000)
            flexmock(slave).should_receive(:pid).and_return(pid)
            flexmock(slave).should_receive(:needed?).and_return(true)
            subject.poll
        end

        describe "#remove_slave" do
            attr_reader :slave

            before do
                @slave = subject.add_slave('cmd')
            end

            it "raises ArgumentError if the slave is still active" do
                mock_slave_active(slave)
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
    end
end

