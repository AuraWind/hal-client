require 'concurrent'
require 'connection_pool'
require 'multi_json'

class HalClient
  class UserAgent
    extend Forwardable
    attr_reader :http_client, :url, :executor, :promise

    def_delegators :current, :all_links

    def initialize(http_client: nil, executor: nil, url: nil, promise: nil)
      @http_client = http_client
      @executor = executor
      @url = url
      @promise = promise

      fail ArgumentError, '"url" or "promise" must be supplied' unless @url || @promise
    end

    def get
      @promise ||= thread_safe_execute do
        http_client_pool.with { |client| client.get(url) }
      end
      UserAgent.new(http_client: http_client_prototype, executor: executor,
        promise: promise)
    end

    def post(data)
      @promise ||= thread_safe_execute do
        http_client_pool.with{ |client| client.post(url, data) }
      end
      UserAgent.new(http_client: http_client_prototype, executor: executor,
        promise: promise)
    end

    def current
      @current ||= Representation.new(
        parsed_json: MultiJson.load(promise.value.to_s))
    end

    def follow_all(rel)
      links_for_rel(rel)
        .map { |rel_hal_link| UserAgent.new(http_client: http_client_prototype,
          executor: executor, url: rel_hal_link.target_url) }
    end

    def follow_first(rel)
      UserAgent.new(http_client: http_client_prototype,
        executor: executor, url: links_for_rel(rel).first.target_url)
    end

    private

    def thread_safe_execute
      Concurrent::Promise.execute(executor: executor) do
        yield
      end
    end

    def links_for_rel(rel)
      all_links.select { |hal_link| hal_link.literal_rel == rel }
    end

    def executor
      @executor ||= Concurrent::ImmediateExecutor.new
    end

    def http_client_pool
      @http_client_pool ||= ConnectionPool.new(size: 10, timeout: 60) do
        http_client_prototype.clone
      end
    end

    def http_client_prototype
      @http_client ||= HTTP::Client.new(follow: true)
    end

  end
end
