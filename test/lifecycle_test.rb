# frozen_string_literal: true

require_relative "test_helper"

# Exercises Kramdown::ImageCache.sync / .purge - the module-level entry
# points meant to be called from an after_commit hook (see
# Kramdown::ImageCache::Model) - end to end against a real Store.
class LifecycleTest < Minitest::Test
  include FixtureImages

  def setup
    @dir = Dir.mktmpdir
    @store = Kramdown::ImageCache::Store.new(root: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_sync_purges_images_dropped_from_an_edit_but_keeps_unchanged_ones
    original = "![a](#{png_data_uri})\n\n![b](#{gif_data_uri})"
    Kramdown::ImageCache.render(original, content_id: 9, store: @store) # simulate first display

    edited = "![a](#{png_data_uri})" # the gif was removed in this edit
    removed = Kramdown::ImageCache.sync(edited, content_id: 9, store: @store)

    assert_equal 1, removed.size
    assert File.exist?(File.join(@dir, "9", "#{Digest::SHA256.hexdigest(png_bytes)}.png"))
    refute File.exist?(File.join(@dir, "9", "#{Digest::SHA256.hexdigest(gif_bytes)}.gif"))
  end

  def test_purge_removes_everything_for_a_destroyed_content_id
    Kramdown::ImageCache.render("![a](#{png_data_uri})", content_id: 3, store: @store)

    Kramdown::ImageCache.purge(3, store: @store)

    refute Dir.exist?(File.join(@dir, "3"))
  end

  def test_default_store_is_used_when_none_is_passed_explicitly
    Kramdown::ImageCache.default_store = @store
    Kramdown::ImageCache.render("![a](#{png_data_uri})", content_id: 1)

    assert File.exist?(File.join(@dir, "1", "#{Digest::SHA256.hexdigest(png_bytes)}.png"))
  ensure
    Kramdown::ImageCache.default_store = nil
  end
end
