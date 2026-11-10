# frozen_string_literal: true

require "fileutils"
require "set"

module Kramdown
  module ImageCache
    # Content-addressable, per-content-namespaced cache of materialized images.
    #
    # Layout on disk:
    #
    #   <root>/<content_id>/<sha256>.<ext>
    #
    # Namespacing by +content_id+ gives every cached file a clear owner, so
    # cleanup can be tied to that content's own update/destroy lifecycle
    # instead of a separate periodic sweep over the whole cache. The
    # trade-off (and why full-parse diffing, not `git diff`, drives it) is
    # written up in doc/design.md.
    class Store
      SAFE_ID = /\A[\w-]+\z/.freeze

      attr_reader :root

      def initialize(root:)
        @root = root.to_s
      end

      # Materializes a single data URI for +content_id+ if it's a
      # recognized base64 image, returning the relative path (e.g.
      # "42/ab12...ef.png") to use as an <img src>. Returns nil for
      # anything Materializer doesn't recognize (ordinary URLs, malformed
      # data URIs, ...), so callers can just skip rewriting in that case.
      def materialize(data_uri, content_id:)
        result = Materializer.parse(data_uri)
        return nil unless result

        Materializer.write(absolute_path(content_id, result.filename), result.bytes)
        relative_path(content_id, result.filename)
      end

      # Call once after a content record is created/updated, passing every
      # data URI still present in its *current* body (see
      # Kramdown::ImageCache.sync / Scanner). Deletes any cached file under
      # this content_id that isn't in that list - i.e. images that were
      # removed or replaced in this edit - and leaves everything else
      # (including unchanged images) untouched. Returns the filenames removed.
      def sync(content_id, referenced_data_uris)
        keep = referenced_data_uris.filter_map { |uri| Materializer.parse(uri)&.filename }.to_set
        purge(content_id) { |filename| !keep.include?(filename) }
      end

      # Call once after a content record is destroyed. Removes every cached
      # file that belonged to it. Returns the filenames removed.
      def purge_all(content_id)
        dir = content_dir(content_id)
        return [] unless Dir.exist?(dir)

        removed = Dir.children(dir)
        FileUtils.rm_rf(dir)
        removed
      end

      # Low-frequency safety-net sweep - NOT the primary cleanup path (that's
      # #sync/#purge_all above, called from a real lifecycle hook). Given the
      # complete set of currently-live content ids, removes any content_id
      # directory left behind by an update/destroy that, for whatever reason
      # (a bug, a manual DB edit, a migration, a skipped hook), never called
      # #sync or #purge_all. Meant to run occasionally (e.g. a weekly rake
      # task), not on every request. Returns the content ids removed.
      def sweep(live_content_ids)
        return [] unless Dir.exist?(root)

        live = live_content_ids.map(&:to_s).to_set
        orphaned = Dir.children(root).reject { |name| live.include?(name) }
        orphaned.each { |name| FileUtils.rm_rf(File.join(root, name)) }
        orphaned
      end

      private

      def purge(content_id)
        dir = content_dir(content_id)
        return [] unless Dir.exist?(dir)

        removed = Dir.children(dir).select { |filename| yield(filename) }
        removed.each { |filename| File.delete(absolute_path(content_id, filename)) }
        removed
      end

      def content_dir(content_id)
        File.join(root, sanitized_id(content_id))
      end

      def absolute_path(content_id, filename)
        File.join(content_dir(content_id), filename)
      end

      def relative_path(content_id, filename)
        File.join(sanitized_id(content_id), filename)
      end

      # content_id is expected to be a DB primary key, but we validate it
      # anyway before it touches a file path - cheap insurance against a
      # future caller passing something like a user-supplied slug.
      def sanitized_id(content_id)
        id = content_id.to_s
        raise Error, "unsafe content_id: #{content_id.inspect}" unless SAFE_ID.match?(id)

        id
      end
    end
  end
end
