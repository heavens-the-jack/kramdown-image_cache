# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "kramdown/image_cache"

module FixtureImages
  # A real, valid 1x1 PNG and 1x1 GIF, base64-encoded - small enough to
  # inline here, but real enough to exercise actual decode/hash logic.
  PNG_1X1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
  GIF_1X1 = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBTAA7"

  def png_data_uri
    "data:image/png;base64,#{FixtureImages::PNG_1X1}"
  end

  def gif_data_uri
    "data:image/gif;base64,#{FixtureImages::GIF_1X1}"
  end

  # Signature-valid JPEG / WebP byte strings. Only the leading bytes matter to
  # the format check (we sniff signatures, we don't decode), so these are
  # minimal containers rather than renderable images.
  JPEG_BYTES = "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xFF\xD9".b.freeze
  WEBP_BYTES = "RIFF\x1A\x00\x00\x00WEBPVP8L\x0D\x00\x00\x00\x2F\x00\x00\x00\x10\x07\x10\x11\x11\x88\x88\xFE\x07\x00".b.freeze
  HTML_BYTES = "<script>alert(1)</script>".b.freeze

  def data_uri(mime, bytes)
    "data:image/#{mime};base64,#{Base64.strict_encode64(bytes)}"
  end

  def jpeg_bytes
    JPEG_BYTES
  end

  def webp_bytes
    WEBP_BYTES
  end

  def png_bytes
    Base64.strict_decode64(FixtureImages::PNG_1X1)
  end

  def gif_bytes
    Base64.strict_decode64(FixtureImages::GIF_1X1)
  end
end
