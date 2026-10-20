# frozen_string_literal: true

RSpec.describe(Redis::Async::Pool::FiberWorker) do
  subject(:worker) { described_class.new }

  # Runs a group of tasks that each report the task they ran in, by their ids.
  def run_group(size)
    group = worker.new_group(size: size)
    size.times { |id| group.push(id) { Async::Task.current? } }

    ran_in = {}
    group.each { |id, task| ran_in[id] = task }
    group.close
    ran_in
  end

  it "runs a group's tasks in fibers of their own, but its last in the calling fiber" do
    Sync do |caller|
      ran_in = run_group(3)

      expect(ran_in[2]).to(equal(caller))
      expect([ran_in[0], ran_in[1]]).to(all(satisfy { |task| !task.equal?(caller) }))
      expect(ran_in[0]).not_to(equal(ran_in[1]))
    end
  end

  it "runs a group of one in the calling fiber" do
    Sync do |caller|
      expect(run_group(1)[0]).to(equal(caller))
    end
  end

  it "runs a group's tasks concurrently" do
    Sync do
      group = worker.new_group(size: 3)
      3.times { |id| group.push(id) { sleep(0.1) } }

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      group.each { nil }

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).to(be < 0.2)
    end
  end

  it "runs a group's tasks inline outside a reactor" do
    expect(run_group(2).values).to(all(be_nil))
  end
end
