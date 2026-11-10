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

  # --- R2: disallowed formats stay as data: URIs and never touch the disk ---

  def test_render_leaves_disallowed_formats_as_data_uris_and_writes_nothing
    [
      data_uri("html", HTML_BYTES),
      data_uri("php", "<?php echo 1; ?>".b),
      data_uri("svg+xml", "<svg xmlns='http://www.w3.org/2000/svg'/>".b),
      data_uri("png", HTML_BYTES), # declared png, actually html
      data_uri("png", jpeg_bytes)  # declared png, actually jpeg
    ].each do |uri|
      html, = Kramdown::ImageCache.render("![alt](#{uri})", content_id: 5, store: @store)

      assert_includes html, uri.sub("&", "&amp;"), "should be left as the original data: URI"
      refute_includes html, "/images/cache/"
    end

    refute Dir.exist?(File.join(@dir, "5")), "nothing should have been written for rejected images"
  end

  def test_render_rewrites_allowed_formats_with_the_detected_extension
    {
      "jpg" => data_uri("jpeg", jpeg_bytes),
      "gif" => gif_data_uri,
      "webp" => data_uri("webp", webp_bytes)
    }.each do |extension, uri|
      html, = Kramdown::ImageCache.render("![alt](#{uri})", content_id: 5, store: @store)

      assert_match(%r{src="/images/cache/5/[0-9a-f]{64}\.#{extension}"}, html)
    end
  end

  def test_render_raises_without_a_store
    assert_raises(Kramdown::ImageCache::Error) do
      Kramdown::ImageCache.render("![alt](#{png_data_uri})", content_id: 5, store: nil)
    end
  end
end
