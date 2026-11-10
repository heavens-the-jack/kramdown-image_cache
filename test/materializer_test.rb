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
    result = Kramdown::ImageCache::Materializer.parse(data_uri("jpeg", jpeg_bytes))
    assert_equal "jpg", result.extension
  end

  # --- R2: format allowlist (PNG / JPEG / GIF / WebP only) ---

  def test_parse_accepts_each_allowed_format_with_the_detected_extension
    {
      "png" => data_uri("png", png_bytes),
      "jpg" => data_uri("jpeg", jpeg_bytes),
      "gif" => data_uri("gif", gif_bytes),
      "webp" => data_uri("webp", webp_bytes)
    }.each do |extension, uri|
      result = parse(uri)

      refute_nil result, "#{extension} should be accepted"
      assert_equal extension, result.extension
      assert_equal "#{result.hash}.#{extension}", result.filename
    end
  end

  def test_parse_accepts_both_gif_signatures
    assert_equal "gif", parse(data_uri("gif", "GIF87a\x01\x00\x01\x00".b)).extension
    assert_equal "gif", parse(data_uri("gif", "GIF89a\x01\x00\x01\x00".b)).extension
  end

  def test_parse_accepts_image_jpg_as_a_declaration_of_jpeg
    result = parse(data_uri("jpg", jpeg_bytes))

    refute_nil result
    assert_equal "jpg", result.extension
  end

  def test_parse_accepts_a_mixed_case_format_name
    assert_equal "png", parse(data_uri("PNG", png_bytes)).extension
    assert_equal "jpg", parse(data_uri("Jpeg", jpeg_bytes)).extension
    assert_equal "webp", parse(data_uri("WebP", webp_bytes)).extension
  end

  def test_parse_ignores_an_uppercase_scheme
    assert_nil parse("DATA:IMAGE/png;base64,#{FixtureImages::PNG_1X1}")
    assert_nil parse("Data:Image/png;base64,#{FixtureImages::PNG_1X1}")
  end

  def test_parse_rejects_formats_outside_the_allowlist
    [
      ["html", HTML_BYTES],
      ["php", "<?php system($_GET['c']); ?>".b],
      ["svg+xml", "<svg xmlns='http://www.w3.org/2000/svg' onload='alert(1)'/>".b],
      ["x-evil", png_bytes],
      ["png.php", png_bytes],
      ["avif", png_bytes],
      ["bmp", png_bytes]
    ].each do |mime, bytes|
      assert_nil parse(data_uri(mime, bytes)), "image/#{mime} must not be materialized"
    end
  end

  def test_parse_rejects_an_svg_even_when_declared_as_png
    svg = "<svg xmlns='http://www.w3.org/2000/svg' onload='alert(1)'/>".b

    assert_nil parse(data_uri("png", svg))
  end

  def test_parse_rejects_html_declared_as_an_allowed_format
    %w[png jpeg gif webp].each do |mime|
      assert_nil parse(data_uri(mime, HTML_BYTES)), "html bytes declared as #{mime}"
    end
  end

  def test_parse_rejects_a_declaration_that_does_not_match_the_bytes
    assert_nil parse(data_uri("png", jpeg_bytes))
    assert_nil parse(data_uri("jpeg", png_bytes))
    assert_nil parse(data_uri("gif", png_bytes))
    assert_nil parse(data_uri("webp", gif_bytes))
    assert_nil parse(data_uri("png", webp_bytes))
  end

  def test_parse_rejects_truncated_or_partial_signatures
    assert_nil parse(data_uri("png", "\x89PNG".b))
    assert_nil parse(data_uri("gif", "GIF88a".b))
    assert_nil parse(data_uri("webp", "RIFF\x00\x00\x00\x00".b))
    assert_nil parse(data_uri("webp", "RIFF\x1A\x00\x00\x00WAVE".b))
    assert_nil parse(data_uri("jpeg", "\xFF\xD8".b))
    assert_nil parse(data_uri("png", "A".b))
  end

  def test_the_extension_comes_from_the_bytes_so_one_image_has_one_filename
    a = parse(data_uri("jpeg", jpeg_bytes))
    b = parse(data_uri("jpg", jpeg_bytes))

    assert_equal a.filename, b.filename
  end

  def test_parse_returns_nil_for_invalid_base64
    assert_nil Kramdown::ImageCache::Materializer.parse("data:image/png;base64,not-valid-base64!!!")
  end

  def parse(uri)
    Kramdown::ImageCache::Materializer.parse(uri)
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
