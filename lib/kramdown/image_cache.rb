# frozen_string_literal: true

require "kramdown"

require_relative "image_cache/version"
require_relative "image_cache/errors"
require_relative "image_cache/materializer"
require_relative "image_cache/store"
require_relative "image_cache/converter"
require_relative "image_cache/scanner"

module Kramdown
  # See doc/design.md in this gem for the full design rationale (why this
  # exists, alternatives considered and rejected, and the trade-offs of the
  # approach taken).
  module ImageCache
    class << self
      # A Store instance used by #render/#sync/#purge when no `store:` is
      # given explicitly. Typically set once at boot:
      #
      #   Kramdown::ImageCache.default_store =
      #     Kramdown::ImageCache::Store.new(root: Rails.root.join("storage", "image_cache"))
      attr_accessor :default_store
    end

    # Renders +markdown+ to HTML, lazily materializing any embedded
    # `data:image/...;base64,...` image into +store+ and rewriting its `src`
    # to the cached URL. The stored Markdown itself is never touched - call
    # this on every display/page view.
    #
    # Returns [html, warnings].
    def self.render(markdown, content_id:, store: default_store, input: "kramdown", url_prefix: "/images/cache")
      store ||= raise(Error, "no store configured (pass `store:` or set Kramdown::ImageCache.default_store)")

      doc = Kramdown::Document.new(markdown, input: input)
      converter = Converter.new(doc.root, doc.options)
      converter.content_id = content_id
      converter.store = store
      converter.url_prefix = url_prefix

      [converter.convert(doc.root), converter.warnings]
    end

    # Call once after a content record is created/updated (e.g. from an
    # after_commit hook - see Model), passing the *new* markdown body.
    # Purges any cached image under this content_id that the new body no
    # longer references. Unchanged images are left alone. Returns the
    # filenames removed.
    def self.sync(markdown, content_id:, store: default_store, input: "kramdown")
      store ||= raise(Error, "no store configured (pass `store:` or set Kramdown::ImageCache.default_store)")

      store.sync(content_id, Scanner.data_uris(markdown, input: input))
    end

    # Call once after a content record is destroyed (e.g. from an
    # after_commit hook - see Model). Removes every cached image that
    # belonged to it. Returns the filenames removed.
    def self.purge(content_id, store: default_store)
      store ||= raise(Error, "no store configured (pass `store:` or set Kramdown::ImageCache.default_store)")

      store.purge_all(content_id)
    end
  end
end
