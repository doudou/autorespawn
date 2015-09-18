require 'test_helper'
require 'autorespawn/program_id'

class Autorespawn
    describe Manager do
        subject { Manager.new }
        
        describe "#collect_finished_slaves" do
            def start_slave(cmd, pid: 42)
                slave = subject.add_slave('cmd')
                flexmock(slave).should_receive(:pid).and_return(pid)
                flexmock(slave).should_receive(:spawn).once
                subject.poll
                slave
            end

            it "calls #finished on the terminated slave and returns the list of terminated slaves" do
                slave = start_slave 'cmd', pid: 20
                flexmock(Process).should_receive(:waitpid2).and_return([20, status = flexmock], nil)
                flexmock(slave).should_receive(:finished).once.with(status)
                assert_equal [slave], subject.collect_finished_slaves
            end

            it "removes the terminated slave from the active_slaves list" do
                slave = start_slave 'cmd', pid: 20
                flexmock(Process).should_receive(:waitpid2).and_return([20, status = flexmock], nil)
                flexmock(slave).should_receive(:finished).once.with(status)
                subject.collect_finished_slaves
                assert subject.active_slaves.empty?
            end
        end

        describe '#poll' do
            it "spawns new workers" do
                slave = subject.add_slave('cmd')
                flexmock(slave).should_receive(:spawn).once
                assert_equal [[slave], Array.new], subject.poll
            end

            it "reorders the workers array to put the slaves before the executed one at the end" do
                slaves = (0..9).map do |i|
                    slave = subject.add_slave('cmd')
                    if i == 3
                        flexmock(slave).should_receive(:needs_spawn?).and_return(true)
                        flexmock(slave).should_receive(:spawn).once
                    else
                        flexmock(slave).should_receive(:needs_spawn?).and_return(false)
                        flexmock(slave).should_receive(:spawn).never
                    end
                    slave
                end
                before = slaves[0..2]
                slave  = slaves[3]
                after  = slaves[4..-1]

                subject.poll
                assert_equal 10, subject.workers.size
                assert_equal (after + before + [slave]), subject.workers
            end
        end
    end
end
