# frozen_string_literal: true

# Open-source Redis has no search coordinator: on a cluster, indexes, aliases, synonyms, dictionaries, cursors
# and FT.CONFIG settings are local to each node, and FT.* commands other than the suggestion ones name no key, so
# redis-cluster-client sends each to a random node (whose address also ends up in error messages). Those cases
# run on the standalone server only; the keyed suggestion commands and client-side errors run on both.
#
# Indexes, aliases, dictionaries and the FT.CONFIG settings are server state rather than keys, so each case uses
# its own names, removes what it creates as its last commands (which also runs in the pipelined and multi
# modes) and again in an ensure, through Conformance.side, in case it fails partway.
#
# FT.SEARCH, FT.AGGREGATE, FT.CURSOR READ and FT.HYBRID replies are result objects without value equality, so
# those cases run in the direct mode only, where the block turns them into plain values.
RSpec.describe("Search") do
  search = Redis::Commands::Search

  products = search::Schema.build do
    text_field :title, weight: 2.0, sortable: true
    numeric_field :price, sortable: true
    tag_field :tags
    geo_field :location
  end

  class << self
    def cleanup(indexes: [], dicts: {}, config: {})
      yield
    ensure
      side = Conformance.side
      indexes.each { |index| side.ft_dropindex(index) if side.call("FT._LIST").include?(index) }
      dicts.each { |dict, terms| side.ft_dictdel(dict, *terms) }
      config.each { |option, value| side.ft_config_set(option, value) }
    end

    # Documents that exist before FT.CREATE are indexed in the background.
    def wait_for_indexing(r, index)
      sleep(0.01) until r.ft_info(index).values_at("indexing", "percent_indexed") == [0, 1.0]
    end

    def add_products(r, prefix)
      [
        r.hset("#{prefix}:1", "title", "hello world", "price", 10, "tags", "red,blue", "location", "13.361389,38.115556"),
        r.hset("#{prefix}:2", "title", "hello there friend", "price", 20, "tags", "blue", "location", "15.087269,37.502669"),
        r.hset("#{prefix}:3", "title", "goodbye world", "price", 30, "tags", "green")
      ]
    end

    def plain(result)
      [result.total, result.documents.map(&:to_h)]
    end
  end

  conform "ft_create, create_index, ft_alter, ft_explain, ft_tagvals and ft_dropindex", targets: [:standalone] do |r|
    cleanup(indexes: ["create-hash", "create-json"]) do
      json = search::Schema.build do
        text_field "$.name", as: "name"
        tag_field "$.kind", as: "kind", separator: ";", case_sensitive: true
      end
      index = r.create_index("create-json", json, storage_type: "json", prefix: "cj")
      [
        r.ft_create("create-hash", products, "hash", prefix: "ch", stopwords: ["the"], max_text_fields: true, no_highlight: true),
        index.name, index.prefix, *add_products(r, "ch"),
        r.json_set("cj:1", "$", { "name" => "a", "kind" => "X;y" }), r.json_set("cj:2", "$", { "name" => "b", "kind" => "y" }),
        r.ft_tagvals("create-hash", "tags"), r.ft_tagvals("create-json", "kind"),
        r.ft_alter("create-hash", search::NumericField.new("stock", sortable: true)), r.ft_alter("create-hash", ["color", "TAG"]),
        r.ft_explain("create-hash", "@title:hello @price:[0 15] @tags:{red}"),
        r.ft_dropindex("create-hash"), r.ft_dropindex("create-json", delete_documents: true), r.exists("ch:1", "cj:1", "cj:2")
      ]
    end
  end

  conform "ft_create with a definition, temporary and skip_initial_scan", targets: [:standalone] do |r|
    cleanup(indexes: ["definition", "skipped"]) do
      definition = search::IndexDefinition.new(prefix: ["def:"], filter: "@price > 15", score_field: "score")
      [
        *add_products(r, "def"),
        r.ft_create("definition", products, "hash", definition: definition, temporary: 60, no_term_offsets: true, no_field_flags: true),
        r.ft_create("skipped", products, prefix: "def", skip_initial_scan: true, no_term_frequencies: true),
        r.ft_dropindex("definition"), r.ft_dropindex("skipped")
      ]
    end
  end

  # FT.INFO carries memory sizes and timings, which differ between runs.
  conform "ft_info", targets: [:standalone], modes: [:direct] do |r|
    cleanup(indexes: ["info", "info-skipped"]) do
      add_products(r, "info")
      r.ft_create("info", products, prefix: "info")
      r.ft_create("info-skipped", products, prefix: "info", skip_initial_scan: true)
      wait_for_indexing(r, "info")
      wait_for_indexing(r, "info-skipped")
      ["info", "info-skipped"].map do |index|
        r.ft_info(index).slice("index_name", "index_options", "index_definition", "attributes", "num_docs", "max_doc_id", "num_terms",
          "hash_indexing_failures", "indexing", "percent_indexed")
      end
    end
  end

  conform "ft_info of a missing index", targets: [:standalone], raises: true do |r|
    r.ft_info("missing")
  end

  conform "ft_create of an existing index", targets: [:standalone], raises: true do |r|
    cleanup(indexes: ["duplicate"]) do
      [r.ft_create("duplicate", products), r.ft_create("duplicate", products), r.ft_dropindex("duplicate")]
    end
  end

  conform "create_index without a schema", raises: true do |r|
    r.create_index("noschema", [])
  end

  conform "ft_dropindex of a missing index", targets: [:standalone], raises: true do |r|
    r.ft_dropindex("missing")
  end

  conform "ft_search", targets: [:standalone], modes: [:direct] do |r|
    cleanup(indexes: ["search"]) do
      r.ft_create("search", products, prefix: "search")
      add_products(r, "search")
      [
        plain(r.ft_search("search", "hello", sortby: ["price", "ASC"])),
        plain(r.ft_search("search", "*", sort_by: "price", asc: false, limit: [1, 1])),
        plain(r.ft_search("search", "world", no_content: true, sort_by: "price")),
        plain(r.ft_search("search", "hello", with_scores: true, verbatim: true, return: ["title"], sort_by: "price")),
        plain(r.ft_search("search", "@price:[$min $max]", params: { min: 15, max: 40 }, return: ["price"], sort_by: "price")),
        plain(r.ft_search("search", "*", filter: [["price", 0, 15]], geo_filter: [["location", 13.36, 38.11, 10, "km"]], return: ["title"])),
        plain(r.ft_search("search", "@tags:{blue}", limit_ids: ["search:2", "search:3"], no_content: true)),
        plain(r.ft_search("search", "hello friend", slop: 1, in_order: true, limit_fields: ["title"], no_stopwords: true, return: ["title"])),
        plain(r.ft_search("search", "hello", highlight: { fields: ["title"], tags: ["<b>", "</b>"] }, return: ["title"], sort_by: "price")),
        plain(r.ft_search("search", "world", summarize: { fields: ["title"], frags: 1, len: 2, separator: "..." }, return: ["title"],
          sort_by: "price", language: "english", scorer: "TFIDF", dialect: 2)),
        plain(r.ft_search("search", "nothing")), r.ft_dropindex("search")
      ]
    end
  end

  conform "ft_search with a syntax error", targets: [:standalone], raises: true do |r|
    cleanup(indexes: ["syntax"]) do
      r.ft_create("syntax", products)
      r.ft_search("syntax", "@title:(")
    end
  end

  conform "ft_aggregate, ft_cursor_read and ft_cursor_del", targets: [:standalone], modes: [:direct] do |r|
    cleanup(indexes: ["aggregate"]) do
      r.ft_create("aggregate", products, prefix: "agg")
      add_products(r, "agg")
      grouped = search::AggregateRequest.new("*")
        .group_by("@tags", search::Reducers.count.as("n"), search::Reducers.sum("@price").as("total"))
        .sort_by(search::Desc.new("@total"), max: 10)
        .apply(double: "@total * 2").filter("@double > 10").limit(0, 5)
      paged = r.ft_aggregate("aggregate", search::AggregateRequest.new("*", with_cursor: true, cursor_count: 1).load("@title").sort_by("@title"))
      first = r.ft_cursor_read("aggregate", paged.cursor)
      second = r.ft_aggregate("aggregate", search::Cursor.new(first.cursor))
      last = r.ft_cursor_read("aggregate", second.cursor)
      reopened = r.ft_aggregate("aggregate", search::AggregateRequest.new("*", with_cursor: true, cursor_count: 1).load("@title"))
      [
        r.ft_aggregate("aggregate", grouped).rows, r.ft_aggregate("aggregate", "hello", "LOAD", "1", "@price", "SORTBY", "1", "@price").rows,
        r.ft_aggregate("aggregate", "*", "GROUPBY", "0", "REDUCE", "COUNT", "0", "AS", "n", "DIALECT", "2").rows,
        paged.rows, paged.cursor.positive?, first.rows, second.rows, last.rows, last.cursor,
        reopened.cursor.positive?, r.ft_cursor_del("aggregate", reopened.cursor), r.ft_dropindex("aggregate")
      ]
    end
  end

  conform "ft_cursor_del of a missing cursor", targets: [:standalone], raises: true do |r|
    cleanup(indexes: ["cursor"]) do
      [r.ft_create("cursor", products), r.ft_cursor_del("cursor", 12_345), r.ft_dropindex("cursor")]
    end
  end

  # The profile carries timings, which differ between runs.
  conform "ft_profile", targets: [:standalone], modes: [:direct] do |r|
    cleanup(indexes: ["profile"]) do
      r.ft_create("profile", products, prefix: "profile")
      add_products(r, "profile")
      [
        r.ft_profile("profile", "SEARCH", "QUERY", "hello", "SORTBY", "price").fetch("Results"),
        r.ft_profile("profile", "AGGREGATE", "LIMITED", "QUERY", "*", "GROUPBY", "0", "REDUCE", "COUNT", "0", "AS", "n").fetch("Results"),
        r.ft_profile("profile", "SEARCH", "QUERY", "*").fetch("Profile").keys
      ]
    end
  end

  # FT.HYBRID's reply carries its execution time, which differs between runs.
  conform "ft_hybrid_search", targets: [:standalone], modes: [:direct] do |r|
    cleanup(indexes: ["hybrid"]) do
      schema = search::Schema.build do
        text_field :title
        numeric_field :price, sortable: true
        vector_field :vec, "FLAT", type: "FLOAT32", dim: 2, distance_metric: "L2"
      end
      r.ft_create("hybrid", schema, prefix: "hy")
      r.hset("hy:1", "title", "hello world", "price", 10, "vec", [0.1, 0.2].pack("e*"))
      r.hset("hy:2", "title", "hello there", "price", 20, "vec", [0.9, 0.8].pack("e*"))
      r.hset("hy:3", "title", "goodbye", "price", 30, "vec", [0.1, 0.25].pack("e*"))
      query = search::HybridQuery.new(
        search::HybridSearchQuery.new("hello", scorer: "BM25STD", yield_score_as: "text_score"),
        search::HybridVsimQuery.new(vector_field_name: "@vec", vector_data: "$v", vsim_search_method: "KNN",
          vsim_search_method_params: { k: 2 }, yield_score_as: "vector_score")
      )
      post = search::HybridPostProcessingConfig.new.load("@title", "@price").sort_by(search::SortbyField.new("@price", asc: false)).limit(0, 10)
      simple = search::HybridQuery.new(search::HybridSearchQuery.new("goodbye"), search::HybridVsimQuery.new(vector_field_name: "@vec", vector_data: "$v"))
      with_post = r.ft_hybrid_search("hybrid", query: query, combine_method: search::CombineResultsMethod.linear(alpha: 0.5, beta: 0.5),
        post_processing: post, params_substitution: { v: [0.1, 0.2].pack("e*") }, timeout: 1000)
      ranked = r.ft_hybrid_search("hybrid", query: simple, combine_method: search::CombineResultsMethod.rrf(window: 10, constant: 60),
        params_substitution: { v: [0.9, 0.8].pack("e*") })
      [
        with_post.rows.map { |row| row.slice("title", "price") }, with_post.total, with_post.warnings,
        ranked.rows.map { |row| row["__key"] }.sort, ranked.total, ranked.cursor?
      ]
    end
  end

  conform "ft_spellcheck, ft_dictadd, ft_dictdel and ft_dictdump", targets: [:standalone] do |r|
    cleanup(indexes: ["spell"], dicts: { "spell-dict" => ["helo", "wrld"] }) do
      [
        r.ft_create("spell", products, prefix: "spell"), *add_products(r, "spell"),
        r.ft_dictadd("spell-dict", "helo", "wrld"), r.ft_dictadd("spell-dict", "helo"), r.ft_dictdump("spell-dict"), r.ft_dictdump("missing-dict"),
        r.ft_spellcheck("spell", "helo wrld"), r.ft_spellcheck("spell", "helo wrld", distance: 2),
        r.ft_spellcheck("spell", "helo wrld", exclude: "spell-dict"), r.ft_spellcheck("spell", "frend", include: "spell-dict"),
        r.ft_spellcheck("spell", "hello"),
        r.ft_dictdel("spell-dict", "helo", "missing"), r.ft_dictdump("spell-dict"), r.ft_dictdel("spell-dict", "wrld"), r.ft_dictdump("spell-dict"),
        r.ft_dropindex("spell")
      ]
    end
  end

  conform "ft_synupdate and ft_syndump", targets: [:standalone] do |r|
    cleanup(indexes: ["synonyms"]) do
      [
        r.ft_create("synonyms", products, prefix: "syn"), *add_products(r, "syn"), r.ft_syndump("synonyms"),
        r.ft_synupdate("synonyms", "greeting", "hello", "hi"), r.ft_synupdate("synonyms", "planet", "world", "earth", skip_initial_scan: true),
        r.ft_synupdate("synonyms", "greeting", "hey"), r.ft_syndump("synonyms"), r.ft_dropindex("synonyms")
      ]
    end
  end

  conform "ft_sugadd, ft_sugget, ft_suglen and ft_sugdel" do |r|
    [
      r.ft_sugadd("{s}sug", "hello world", 1), r.ft_sugadd("{s}sug", "help", 2, payload: "p"), r.ft_sugadd("{s}sug", "hello world", 3, incr: true),
      r.ft_sugadd("{s}sug", "goodbye", 1), r.ft_suglen("{s}sug"), r.ft_suglen("{s}missing"),
      r.ft_sugget("{s}sug", "hel"), r.ft_sugget("{s}sug", "hel", max: 1), r.ft_sugget("{s}sug", "hrl", fuzzy: true),
      r.ft_sugget("{s}sug", "hel", withscores: true, with_payloads: true), r.ft_sugget("{s}sug", "hel", with_scores: true, withpayloads: true),
      r.ft_sugget("{s}sug", "zzz"), r.ft_sugget("{s}missing", "a"),
      r.ft_sugdel("{s}sug", "help"), r.ft_sugdel("{s}sug", "help"), r.ft_suglen("{s}sug"), r.ft_sugdel("{s}sug", "hello world"), r.ft_sugdel("{s}sug", "goodbye"),
      r.ft_suglen("{s}sug")
    ]
  end

  conform "ft_aliasadd, ft_aliasupdate, ft_aliaslist and ft_aliasdel", targets: [:standalone] do |r|
    cleanup(indexes: ["alias-a", "alias-b"]) do
      [
        r.ft_create("alias-a", products, prefix: "aa"), r.ft_create("alias-b", products, prefix: "ab"),
        r.ft_aliasadd("alias-1", "alias-a"), r.ft_aliasadd("alias-2", "alias-a"), r.ft_aliaslist("alias-a"), r.ft_aliaslist("alias-b"),
        r.hset("aa:1", "title", "via alias", "tags", "aliased"), r.ft_tagvals("alias-1", "tags"),
        r.ft_aliasupdate("alias-2", "alias-b"), r.ft_aliasupdate("alias-3", "alias-b"), r.ft_aliaslist("alias-a"), r.ft_aliaslist("alias-b"),
        r.ft_aliasdel("alias-1"), r.ft_aliasdel("alias-2"), r.ft_aliasdel("alias-3"), r.ft_aliaslist("alias-a"), r.ft_aliaslist("alias-b"),
        r.ft_dropindex("alias-a"), r.ft_dropindex("alias-b")
      ]
    end
  end

  conform "ft_aliasadd of an existing alias", targets: [:standalone], raises: true do |r|
    cleanup(indexes: ["alias-taken"]) do
      [r.ft_create("alias-taken", products), r.ft_aliasadd("taken", "alias-taken"), r.ft_aliasadd("taken", "alias-taken"), r.ft_dropindex("alias-taken")]
    end
  end

  conform "ft_aliasdel of a missing alias", targets: [:standalone], raises: true do |r|
    r.ft_aliasdel("missing")
  end

  conform "ft_config_get and ft_config_set", targets: [:standalone] do |r|
    original = Conformance.side.ft_config_get("MINPREFIX").fetch("MINPREFIX")
    cleanup(config: { "MINPREFIX" => original }) do
      [
        r.ft_config_get("MINPREFIX"), r.ft_config_set("MINPREFIX", 3), r.ft_config_get("MINPREFIX"), r.ft_config_get("NOSUCHOPTION"),
        r.ft_config_set("MINPREFIX", original), r.ft_config_get("MINPREFIX")
      ]
    end
  end

  conform "ft_config_set of an unknown option", targets: [:standalone], raises: true do |r|
    r.ft_config_set("NOSUCHOPTION", 1)
  end
end
