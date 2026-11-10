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

  def png_bytes
    Base64.strict_decode64(FixtureImages::PNG_1X1)
  end

  def gif_bytes
    Base64.strict_decode64(FixtureImages::GIF_1X1)
  end
end
