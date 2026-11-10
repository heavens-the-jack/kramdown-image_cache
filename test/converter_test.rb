# frozen_string_literal: true

require_relative "test_helper"

class ConverterTest < Minitest::Test
  include FixtureImages

  def setup
    @dir = Dir.mktmpdir
    @store = Kramdown::ImageCache::Store.new(root: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_render_rewrites_the_data_uri_to_a_cache_url
    markdown = "![alt](#{png_data_uri})"

    html, = Kramdown::ImageCache.render(markdown, content_id: 5, store: @store)

    refute_includes html, "base64"
    assert_match(%r{src="/images/cache/5/[0-9a-f]{64}\.png"}, html)
  end

  def test_render_actually_writes_the_cache_file
    markdown = "![alt](#{png_data_uri})"

    Kramdown::ImageCache.render(markdown, content_id: 5, store: @store)

    hash = Digest::SHA256.hexdigest(png_bytes)
    assert File.exist?(File.join(@dir, "5", "#{hash}.png"))
  end

  def test_render_does_not_mutate_the_source_markdown
    markdown = "![alt](#{png_data_uri})".freeze

    Kramdown::ImageCache.render(markdown, content_id: 5, store: @store)

    assert markdown.frozen? # would raise on any in-place mutation attempt
  end

  def test_render_leaves_ordinary_image_urls_untouched
    markdown = "![alt](https://example.com/a.png)"

    html, = Kramdown::ImageCache.render(markdown, content_id: 5, store: @store)

    assert_match(%r{src="https://example\.com/a\.png"}, html)
  end

  def test_render_uses_a_custom_url_prefix
    markdown = "![alt](#{png_data_uri})"

    html, = Kramdown::ImageCache.render(markdown, content_id: 5, store: @store, url_prefix: "/assets/img")

    assert_match(%r{src="/assets/img/5/[0-9a-f]{64}\.png"}, html)
  end

  def test_render_raises_without_a_store
    assert_raises(Kramdown::ImageCache::Error) do
      Kramdown::ImageCache.render("![alt](#{png_data_uri})", content_id: 5, store: nil)
    end
  end
end
