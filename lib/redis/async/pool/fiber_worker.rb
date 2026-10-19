# frozen_string_literal: true

class Redis
  module Async
    module Pool
      # A redis-cluster-client concurrent worker that runs each task (a node's share of a pipeline, a command sent
      # to every node, ...) in a fiber of its own on the current reactor, rather than in a thread (its :on_demand
      # and :pooled models) or one after another (:none, the default). Outside a reactor, tasks run inline.
      class FiberWorker
        def new_group(size:)
          ::RedisClient::Cluster::ConcurrentWorker::Group.new(worker: self, queue: ::Thread::Queue.new, size: size)
        end

        def push(task)
          if (current = ::Async::Task.current?)
            current.async { task.exec }
          else
            task.exec
          end
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
