# frozen_string_literal: true

require "kramdown"

module Kramdown
  module ImageCache
    # A Kramdown::Converter::Html subclass that rewrites embedded
    # `data:image/...;base64,...` image sources into cached, URL-addressable
    # paths as it renders - without ever touching the original Markdown
    # source. Hooking in at `convert_img`, rather than post-processing the
    # rendered HTML, means we only ever look at bytes Kramdown has already
    # told us are an image - see doc/design.md for why that matters.
    #
    # Not usually instantiated directly - use Kramdown::ImageCache.render.
    class Converter < Kramdown::Converter::Html
      # Kramdown::Converter::Base makes .new private - the public API is the
      # .convert class method, which instantiates internally and never lets
      # you configure the instance first. We need to set content_id/store
      # before calling #convert, so we deliberately reopen .new as public on
      # this subclass only.
      public_class_method :new

      attr_accessor :content_id, :store, :url_prefix

      # Every data URI encountered during this render, in case a caller
      # wants them without a second parse pass (Kramdown::ImageCache.render
      # exposes this; Scanner is the cheaper option when you only need this
      # list and not the rendered HTML at all, e.g. for a post-save sync).
      attr_reader :seen_data_uris

      def initialize(root, options)
        super
        @seen_data_uris = []
        @url_prefix = "/images/cache"
      end

      def convert_img(el, indent)
        src = el.attr["src"]

        if src&.start_with?("data:image/")
          @seen_data_uris << src
          rewritten = store && content_id ? store.materialize(src, content_id: content_id) : nil

          if rewritten
            # Kramdown::Element exposes `attr` but not `attr=`, so we can't
            # dup-and-mutate in place - build a fresh element with the same
            # type/value/options instead, leaving the original (and its attr
            # Hash) completely untouched.
            new_attr = el.attr.merge("src" => File.join(url_prefix, rewritten))
            el = Kramdown::Element.new(el.type, el.value, new_attr, el.options)
          end
        end

        super(el, indent)
      end
    end
  end
end
