# frozen_string_literal: true

module PrometheusExporter::Instrumentation
  class SidekiqQueue
    def self.start(client: nil, frequency: 30)
      client ||= PrometheusExporter::Client.default
      sidekiq_queue_collector = new

      Thread.new do
        loop do
          begin
            client.send_json(sidekiq_queue_collector.collect)
          rescue StandardError => e
            client.logger.error("Prometheus Exporter Failed To Collect Sidekiq Queue metrics #{e}")
          ensure
            sleep frequency
          end
        end
      end
    end

    def collect
      {
        type: 'sidekiq_queue',
        queues: collect_queue_stats
      }
    end

    def collect_queue_stats
      queues = collect_current_process_queues

      ::Sidekiq::Queue.all.map do |queue|
        next unless queues.include? queue.name
        {
          backlog: queue.size,
          latency_seconds: queue.latency.to_i,
          labels: { queue: queue.name }
        }
      end.compact
    end

    private

    def collect_current_process_queues
      pid = ::Process.pid
      ps = ::Sidekiq::ProcessSet.new
      hostname = Socket.gethostname

      process = ps.find do |sp|
        sp['hostname'] == hostname && sp['pid'] == pid
      end

      process.nil? ? [] : process['queues']
    end
  end
end
