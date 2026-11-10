# frozen_string_literal: true

# Optional ActiveRecord integration - not loaded by `require "kramdown/image_cache"`,
# require it explicitly (`require "kramdown/image_cache/model"`) in a Rails app.
module Kramdown
  module ImageCache
    # Include in a model with a Markdown text column to wire up the
    # after_commit sync/purge lifecycle described in doc/design.md
    # automatically:
    #
    #   class Post < ApplicationRecord
    #     include Kramdown::ImageCache::Model
    #     image_cache_source :body
    #   end
    #
    # This uses after_commit (not after_save/after_update) deliberately: a
    # filesystem write/delete is a non-transactional side effect, so it must
    # only run once the database change it corresponds to is actually
    # durable - running it from after_update would leave cached files
    # deleted even if the surrounding transaction later rolled back.
    module Model
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def image_cache_source(attribute, store: Kramdown::ImageCache.default_store, input: "kramdown")
          after_commit(on: %i[create update]) do
            Kramdown::ImageCache.sync(public_send(attribute).to_s, content_id: id, store: store, input: input)
          end

          after_commit(on: :destroy) do
            Kramdown::ImageCache.purge(id, store: store)
          end
        end
      end
    end
  end
end
