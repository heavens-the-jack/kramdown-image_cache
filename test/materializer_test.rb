# frozen_string_literal: true

require_relative "test_helper"

class MaterializerTest < Minitest::Test
  include FixtureImages

  def test_parse_returns_nil_for_a_plain_url
    assert_nil Kramdown::ImageCache::Materializer.parse("https://example.com/a.png")
  end

  def test_parse_returns_nil_for_nil
    assert_nil Kramdown::ImageCache::Materializer.parse(nil)
  end

  def test_parse_extracts_hash_and_extension
    result = Kramdown::ImageCache::Materializer.parse(png_data_uri)

    refute_nil result
    assert_equal "png", result.extension
    assert_equal 64, result.hash.length
    assert_equal "#{result.hash}.png", result.filename
    assert_equal png_bytes, result.bytes
  end

  def test_parse_is_content_addressed
    a = Kramdown::ImageCache::Materializer.parse(png_data_uri)
    b = Kramdown::ImageCache::Materializer.parse(png_data_uri)
    c = Kramdown::ImageCache::Materializer.parse(gif_data_uri)

    assert_equal a.hash, b.hash
    refute_equal a.hash, c.hash
  end

  def test_parse_normalizes_jpeg_extension_to_jpg
    result = Kramdown::ImageCache::Materializer.parse("data:image/jpeg;base64,#{FixtureImages::PNG_1X1}")
    assert_equal "jpg", result.extension
  end

  def test_parse_returns_nil_for_invalid_base64
    assert_nil Kramdown::ImageCache::Materializer.parse("data:image/png;base64,not-valid-base64!!!")
  end

  def test_write_creates_the_file_with_the_given_bytes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sub", "out.png")
      Kramdown::ImageCache::Materializer.write(path, png_bytes)

      assert_equal png_bytes, File.binread(path)
    end
  end

  def test_write_is_a_no_op_when_the_file_already_exists
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.png")
      Kramdown::ImageCache::Materializer.write(path, png_bytes)
      mtime_before = File.mtime(path)

      sleep(0.01)
      Kramdown::ImageCache::Materializer.write(path, png_bytes)

      assert_equal mtime_before, File.mtime(path)
    end
  end
end
