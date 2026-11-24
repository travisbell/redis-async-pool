# frozen_string_literal: true

class Redis
  module Async
    module Pool
      # Sends each node's share of redis-cluster-client's pipelines (#pipelined, and the commands it splits across
      # nodes: mget, mset, del, ...) through the node's pool's auto-pipelining (AsyncPooled#auto_pipelined), when its
      # connections are busy. What redis-cluster-client then gets back is what it would have from that share alone:
      # its replies, or the RedirectionNeeded (MOVED, ASK), StaleClusterState (CLUSTERDOWN) or first error that
      # RedisClient::ConnectionMixin#call_pipelined_aware_of_redirection raises, so it follows redirections as usual.
      module ClusterPipelining
        private

        def do_pipelining(client, pipeline)
          # Blocking commands, and commands that mustn't be retried, go out on a connection of their own.
          if client.is_a?(::RedisClient::Pooled) && pipeline._timeouts.nil? && pipeline._retryable?
            replies = client.auto_pipelined(pipeline._commands)
          end
          return super unless replies

          redirections = stale = first_error = nil
          replies.each_with_index do |reply, index|
            next unless reply.is_a?(::RedisClient::Error)

            # Its next error would be another fiber's.
            reply._set_next_error(nil)
            if reply.is_a?(::RedisClient::CommandError) && reply.message.start_with?("MOVED", "ASK")
              (redirections ||= []) << index
            elsif @exception
              first_error ||= reply
            end
            stale = true if reply.message.start_with?("CLUSTERDOWN")
          end

          if redirections
            error = ::RedisClient::Cluster::Pipeline::RedirectionNeeded.new
            error.indices = redirections
          elsif stale
            error = ::RedisClient::Cluster::Pipeline::StaleClusterState.new
          end
          if error
            error.replies = replies
            error.first_exception = first_error
            raise error
          end
          raise first_error if first_error

          pipeline._coerce!(replies)
        end
      end
    end
  end
end
