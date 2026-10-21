# frozen_string_literal: true

# Every redis-rb command method, and the client API around them, must be exercised by a conformance
# case (as `r.<method>`, or a `# covers: <method>` comment) or be excluded here with a reason.
RSpec.describe("Conformance coverage") do
  excluded = {
    shutdown: "stops the server the specs run against",
    sync: "starts a replication stream",
    slaveof: "turns the server into a replica",
    migrate: "needs a second standalone server",
    _client: "redis-rb's internal client",
    dup: "copies the client object, not a command",
    inspect: "describes the client object, not a command",
    # Commands newer than the specs' servers (redis:7.4, see docker-compose.yml).
    lmovem: "needs Redis 8.10",
    blmovem: "needs Redis 8.10",
    sdiffcard: "needs Redis 8.10",
    sunioncard: "needs Redis 8.10",
    himport_prepare: "needs Redis 8.10",
    himport_set: "needs Redis 8.10",
    himport_discard: "needs Redis 8.10",
    himport_discard_all: "needs Redis 8.10",
    create_index: "needs the Query Engine, which redis:7.4 doesn't have"
  }
  # Whole modules redis:7.4 doesn't have, by their methods' prefix.
  excluded_prefixes = {
    "ft_" => "needs the Query Engine",
    "json_" => "needs the JSON module"
  }

  it "has a case for every redis-rb method" do
    methods = Redis::Commands.public_instance_methods + Redis.public_instance_methods(false) + [:method_missing]
    sources = Dir[File.join(__dir__, "*_spec.rb")].map { |file| File.read(file) }.join
    covered = sources.scan(/\br\.(\w+[?!]?)/).flatten.map(&:to_sym) + sources.scan(/# covers: (\w+)/).flatten.map(&:to_sym)
    uncovered = methods.uniq.sort - covered - excluded.keys

    expect(uncovered.reject { |method| method.start_with?(*excluded_prefixes.keys) }).to(be_empty)
  end

  it "doesn't exclude methods that are covered or don't exist" do
    methods = Redis::Commands.public_instance_methods + Redis.public_instance_methods(false)

    expect(excluded.keys - methods).to(be_empty)
    expect(excluded_prefixes.keys.reject { |prefix| methods.any? { |method| method.start_with?(prefix) } }).to(be_empty)
  end
end

RSpec.describe("Known gaps") do
  it "name only examples that exist" do
    groups = RSpec.world.example_groups.select { |group| group.file_path.include?("/conformance/") }
    examples = groups.flat_map { |group| group.descendants.flat_map(&:examples) }.map(&:full_description)
    loaded = groups.map(&:description)

    # Only gaps of the groups this run loaded can be checked.
    stale = Conformance::KNOWN_GAPS.keys.select { |example| loaded.any? { |group| example.start_with?("#{group} ") } } - examples

    expect(stale).to(be_empty)
  end
end
