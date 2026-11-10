# frozen_string_literal: true

require "kramdown"

module Kramdown
  module ImageCache
    # Walks a Kramdown AST collecting the `src` of every embedded
    # `data:image/...;base64,...` image, without rendering any HTML.
    #
    # Kramdown::ImageCache.render already collects this list as a side
    # effect (Converter#seen_data_uris), so Scanner only matters when you
    # want *just* the list - typically at save time, to hand to
    # Store#sync/Kramdown::ImageCache.sync, where building the HTML output
    # would be wasted work.
    module Scanner
      class << self
        def data_uris(markdown, input: "kramdown")
          doc = Kramdown::Document.new(markdown, input: input)
          [].tap { |uris| walk(doc.root, uris) }
        end

        private

        def walk(element, uris)
          if element.type == :img && element.attr["src"]&.start_with?("data:image/")
            uris << element.attr["src"]
          end

          element.children.each { |child| walk(child, uris) }
        end
      end
    end
  end
end
