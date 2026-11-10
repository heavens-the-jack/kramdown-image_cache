# frozen_string_literal: true

require_relative "test_helper"
require "kramdown-parser-gfm"

# Pins the behavior that applications embedding this gem rely on: subclassing
# Converter, switching the input parser, running without a store, and the
# accepted shapes of content_id. These are public-contract tests - if one
# fails, the gem's interface changed.
class ContractTest < Minitest::Test
  include FixtureImages

  # A typical host-app customization: extend a link's rendering while keeping
  # the image rewriting inherited from Converter.
  class LinkMarkingConverter < Kramdown::ImageCache::Converter
    def convert_a(el, indent)
      el.attr["data-marked"] = "true"
      super
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @store = Kramdown::ImageCache::Store.new(root: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def render_with(converter_class, markdown, content_id:, url_prefix:)
    doc = Kramdown::Document.new(markdown)
    converter = converter_class.new(doc.root, doc.options)
    converter.store = @store
    converter.content_id = content_id
    converter.url_prefix = url_prefix
    converter.convert(doc.root)
  end

  # --- Converter subclassing -------------------------------------------------

  def test_subclass_keeps_image_rewriting_and_applies_its_own_overrides
    markdown = "[link](https://example.com) ![alt](#{png_data_uri})"

    html = render_with(LinkMarkingConverter, markdown, content_id: 7, url_prefix: "/cache")

    assert_includes html, 'data-marked="true"'
    assert_match(%r{src="/cache/7/[0-9a-f]{64}\.png"}, html)
    refute_includes html, "base64"
  end

  def test_subclass_can_change_url_prefix_and_content_id_on_every_render
    markdown = "![alt](#{png_data_uri})"

    first = render_with(LinkMarkingConverter, markdown, content_id: 1, url_prefix: "/a")
    second = render_with(LinkMarkingConverter, markdown, content_id: 2, url_prefix: "https://cdn.example.com/b")

    assert_match(%r{src="/a/1/[0-9a-f]{64}\.png"}, first)
    assert_match(%r{src="https://cdn\.example\.com/b/2/[0-9a-f]{64}\.png"}, second)
  end

  # --- Input parser (GFM) ----------------------------------------------------

  def test_render_accepts_the_gfm_input_parser
    markdown = "~~gone~~\n\n![alt](#{png_data_uri})"

    html, = Kramdown::ImageCache.render(markdown, content_id: 3, store: @store, input: "GFM")

    assert_includes html, "<del>gone</del>"
    assert_match(%r{src="/images/cache/3/[0-9a-f]{64}\.png"}, html)
  end

  def test_scanner_accepts_the_gfm_input_parser
    uris = Kramdown::ImageCache::Scanner.data_uris("![alt](#{png_data_uri})", input: "GFM")

    assert_equal [png_data_uri], uris
  end

  def test_sync_accepts_the_gfm_input_parser
    Kramdown::ImageCache.render("![a](#{png_data_uri})![b](#{gif_data_uri})", content_id: 4, store: @store, input: "GFM")

    removed = Kramdown::ImageCache.sync("![a](#{png_data_uri})", content_id: 4, store: @store, input: "GFM")

    assert_equal ["#{Digest::SHA256.hexdigest(gif_bytes)}.gif"], removed
  end

  # --- Not configured: data URIs pass through --------------------------------

  def test_converter_without_a_store_leaves_the_data_uri_in_place
    doc = Kramdown::Document.new("![alt](#{png_data_uri})")
    converter = Kramdown::ImageCache::Converter.new(doc.root, doc.options)
    converter.content_id = 5

    html = converter.convert(doc.root)

    assert_includes html, png_data_uri
    assert_empty Dir.children(@dir)
  end

  def test_converter_without_a_content_id_leaves_the_data_uri_in_place
    doc = Kramdown::Document.new("![alt](#{png_data_uri})")
    converter = Kramdown::ImageCache::Converter.new(doc.root, doc.options)
    converter.store = @store

    html = converter.convert(doc.root)

    assert_includes html, png_data_uri
    assert_empty Dir.children(@dir)
  end

  # --- content_id shapes -----------------------------------------------------

  def test_content_id_works_as_an_integer_and_as_the_same_string
    markdown = "![alt](#{png_data_uri})"

    as_integer, = Kramdown::ImageCache.render(markdown, content_id: 42, store: @store)
    as_string, = Kramdown::ImageCache.render(markdown, content_id: "42", store: @store)

    assert_equal as_integer, as_string
    assert_equal ["42"], Dir.children(@dir)
  end

  def test_content_id_accepts_a_string_slug_of_word_characters_and_hyphens
    html, = Kramdown::ImageCache.render("![alt](#{png_data_uri})", content_id: "post-2026_a", store: @store)

    assert_match(%r{src="/images/cache/post-2026_a/[0-9a-f]{64}\.png"}, html)
  end

  def test_an_unsafe_content_id_raises_an_error_and_writes_nothing
    ["../escape", "a/b", "", "id with space", "42\n"].each do |bad_id|
      assert_raises(Kramdown::ImageCache::Error, "expected #{bad_id.inspect} to be rejected") do
        Kramdown::ImageCache.render("![alt](#{png_data_uri})", content_id: bad_id, store: @store)
      end
    end

    assert_empty Dir.children(@dir)
    refute File.exist?(File.join(File.dirname(@dir), "escape"))
  end
end
