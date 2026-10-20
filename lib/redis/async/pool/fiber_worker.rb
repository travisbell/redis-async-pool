# frozen_string_literal: true

class Redis
  module Async
    module Pool
      # A redis-cluster-client concurrent worker that runs each task (a node's share of a pipeline, a command sent
      # to every node, ...) in a fiber of its own on the current reactor, rather than in a thread (its :on_demand
      # and :pooled models) or one after another (:none, the default). Outside a reactor, tasks run inline.
      class FiberWorker
        # Runs a group's tasks in fibers of their own, except its last (or only) one, which runs in the calling
        # fiber: the others are already under way by then, so it saves starting a task without losing any
        # concurrency.
        class Tasks
          def initialize(size)
            @remaining = size
          end

          def push(task)
            @remaining -= 1

            if @remaining.positive? && (current = ::Async::Task.current?)
              current.async { task.exec }
            else
              task.exec
            end
          end
        end

        def new_group(size:)
          ::RedisClient::Cluster::ConcurrentWorker::Group.new(worker: Tasks.new(size), queue: ::Thread::Queue.new, size: size)
        end

        def close; end

        def inspect
          "#<#{self.class.name}>"
        end
      end

      # Adds a concurrency model, :async (a FiberWorker), to redis-cluster-client's.
      module ConcurrentWorkerModels
        def create(model: :none, size: 5)
          model.to_s == "async" ? FiberWorker.new : super
        end
      end
    end
  end
end
