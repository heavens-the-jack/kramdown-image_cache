# frozen_string_literal: true

require "digest"
require "base64"
require "fileutils"
require "securerandom"

module Kramdown
  module ImageCache
    # Pure, storage-agnostic building block: parses a `data:image/...;base64,...`
    # URI and writes its decoded bytes to disk under a content-addressable
    # filename (the SHA256 of the bytes). Knows nothing about content ids or
    # Markdown - see Store for that layer.
    class Materializer
      DATA_URI = %r{\Adata:image/(?<format>[a-zA-Z0-9.+-]+);base64,(?<data>.+)\z}m.freeze

      # data URI format -> file extension, for the handful of cases where
      # they differ.
      FORMAT_ALIASES = {
        "jpeg" => "jpg",
        "svg+xml" => "svg"
      }.freeze

      Result = Struct.new(:hash, :extension, :filename, :bytes, keyword_init: true)

      class << self
        # Parses +data_uri+. Returns a Result, or nil if it isn't a
        # recognizable base64-encoded image (a normal http(s) URL, a
        # malformed data URI, invalid base64, ...). Never raises - anything
        # that doesn't parse cleanly is treated as "not our concern, leave
        # it alone" so a single bad image can't break a whole render.
        def parse(data_uri)
          match = DATA_URI.match(data_uri.to_s)
          return nil unless match

          bytes = safe_decode(match[:data])
          return nil unless bytes

          extension = FORMAT_ALIASES.fetch(match[:format].downcase, match[:format].downcase)
          hash = Digest::SHA256.hexdigest(bytes)

          Result.new(hash: hash, extension: extension, filename: "#{hash}.#{extension}", bytes: bytes)
        end

        # Writes +bytes+ to +path+ if it isn't already there. Because the
        # filename is content-addressed, a file that already exists is
        # guaranteed to already hold the right bytes, so this is a cheap
        # no-op on every render after the first.
        #
        # Writes go to a sibling temp file and then File.rename into place,
        # which is atomic on the same filesystem - concurrent first-renders
        # of the same image race harmlessly (both would write identical
        # bytes) instead of producing a corrupt partial file.
        def write(path, bytes)
          FileUtils.mkdir_p(File.dirname(path))
          return if File.exist?(path)

          tmp_path = "#{path}.#{Process.pid}-#{SecureRandom.hex(4)}.tmp"
          File.binwrite(tmp_path, bytes)
          File.rename(tmp_path, path)
        end

        private

        def safe_decode(base64_data)
          Base64.strict_decode64(base64_data)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
