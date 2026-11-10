# frozen_string_literal: true

require_relative "test_helper"

class ScannerTest < Minitest::Test
  include FixtureImages

  def test_finds_every_embedded_data_uri
    markdown = <<~MD
      # Title

      ![first](#{png_data_uri})

      Some text in between.

      ![second](#{gif_data_uri})
    MD

    uris = Kramdown::ImageCache::Scanner.data_uris(markdown)

    assert_equal [png_data_uri, gif_data_uri], uris
  end

  def test_ignores_ordinary_image_urls
    uris = Kramdown::ImageCache::Scanner.data_uris("![alt](https://example.com/a.png)")
    assert_empty uris
  end

  def test_returns_an_empty_array_for_content_with_no_images
    assert_empty Kramdown::ImageCache::Scanner.data_uris("just some text, no images at all")
  end
end
