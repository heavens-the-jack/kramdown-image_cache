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

      # The formats we are willing to write to disk: declared data URI
      # subtype (lowercase) -> file extension. Anything else (SVG, HTML, ...)
      # is left alone as a `data:` URI. The extension of the cached file is
      # decided from the sniffed bytes, never from the declaration, so a
      # delivery layer that maps extension -> Content-Type can't be tricked
      # into serving active content. Adding a format (e.g. AVIF) means adding
      # an entry here and a signature in .detect_extension.
      # "jpg" is accepted as a (non-standard but common) declaration of JPEG.
      ALLOWED_FORMATS = {
        "png" => "png",
        "jpeg" => "jpg",
        "jpg" => "jpg",
        "gif" => "gif",
        "webp" => "webp"
      }.freeze

      Result = Struct.new(:hash, :extension, :filename, :bytes, keyword_init: true)

      class << self
        # Parses +data_uri+. Returns a Result, or nil if it isn't a
        # recognizable base64-encoded image of an allowed format (a normal
        # http(s) URL, a malformed data URI, invalid base64, a format outside
        # ALLOWED_FORMATS, or bytes whose signature doesn't match the declared
        # format). Never raises - anything
        # that doesn't parse cleanly is treated as "not our concern, leave
        # it alone" so a single bad image can't break a whole render.
        def parse(data_uri)
          match = DATA_URI.match(data_uri.to_s)
          return nil unless match

          bytes = safe_decode(match[:data])
          return nil unless bytes

          declared = ALLOWED_FORMATS[match[:format].downcase]
          return nil unless declared
          return nil unless detect_extension(bytes) == declared

          extension = declared
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

        # Sniffs the leading bytes. Returns "png"/"jpg"/"gif"/"webp", or nil
        # if the signature is none of the allowed formats. This checks the
        # signature only - it does not decode the image.
        def detect_extension(bytes)
          head = bytes.byteslice(0, 12).to_s.b

          if head.start_with?("\x89PNG\r\n\x1A\n".b)
            "png"
          elsif head.start_with?("\xFF\xD8\xFF".b)
            "jpg"
          elsif head.start_with?("GIF87a".b, "GIF89a".b)
            "gif"
          elsif head.bytesize == 12 && head.start_with?("RIFF".b) && head.byteslice(8, 4) == "WEBP".b
            "webp"
          end
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
