# frozen_string_literal: true

require_relative "test_helper"

class StoreTest < Minitest::Test
  include FixtureImages

  def setup
    @dir = Dir.mktmpdir
    @store = Kramdown::ImageCache::Store.new(root: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_materialize_writes_the_file_under_the_content_id_and_returns_its_relative_path
    relative = @store.materialize(png_data_uri, content_id: 42)

    assert_match(%r{\A42/[0-9a-f]{64}\.png\z}, relative)
    assert File.exist?(File.join(@dir, relative))
    assert_equal png_bytes, File.binread(File.join(@dir, relative))
  end

  def test_materialize_returns_nil_for_a_non_image_data_uri
    assert_nil @store.materialize("https://example.com/a.png", content_id: 42)
  end

  def test_materialize_returns_nil_and_writes_nothing_for_a_disallowed_format
    [
      data_uri("html", HTML_BYTES),
      data_uri("svg+xml", "<svg/>".b),
      data_uri("png", HTML_BYTES)
    ].each do |uri|
      assert_nil @store.materialize(uri, content_id: 42)
    end

    refute Dir.exist?(File.join(@dir, "42"))
  end

  def test_sync_does_not_treat_a_disallowed_data_uri_as_a_reference
    @store.materialize(png_data_uri, content_id: 1)

    removed = @store.sync(1, [data_uri("svg+xml", "<svg/>".b)])

    assert_equal 1, removed.size
    assert_empty Dir.children(File.join(@dir, "1"))
  end

  def test_sync_removes_files_no_longer_referenced_but_keeps_the_rest
    @store.materialize(png_data_uri, content_id: 1)
    @store.materialize(gif_data_uri, content_id: 1)

    removed = @store.sync(1, [png_data_uri]) # body was edited: gif was dropped, png stays

    assert_equal 1, removed.size
    assert File.exist?(File.join(@dir, "1", "#{Digest::SHA256.hexdigest(png_bytes)}.png"))
    refute File.exist?(File.join(@dir, "1", "#{Digest::SHA256.hexdigest(gif_bytes)}.gif"))
  end

  def test_sync_with_no_referenced_images_clears_out_the_content_id
    @store.materialize(png_data_uri, content_id: 1)

    @store.sync(1, [])

    assert_empty Dir.children(File.join(@dir, "1"))
  end

  def test_sync_never_touches_other_content_ids
    @store.materialize(png_data_uri, content_id: 1)
    @store.materialize(png_data_uri, content_id: 2)

    @store.sync(1, [])

    assert_equal 1, Dir.children(File.join(@dir, "2")).size
  end

  def test_purge_all_removes_the_whole_content_directory
    @store.materialize(png_data_uri, content_id: 7)

    @store.purge_all(7)

    refute Dir.exist?(File.join(@dir, "7"))
  end

  def test_purge_all_on_a_content_id_with_nothing_cached_is_a_safe_no_op
    assert_equal [], @store.purge_all(999)
  end

  def test_sweep_removes_directories_for_content_ids_that_are_no_longer_live
    @store.materialize(png_data_uri, content_id: 1)
    @store.materialize(png_data_uri, content_id: 2)

    removed = @store.sweep([2])

    assert_equal ["1"], removed
    refute Dir.exist?(File.join(@dir, "1"))
    assert Dir.exist?(File.join(@dir, "2"))
  end

  def test_rejects_a_content_id_that_looks_like_a_path
    assert_raises(Kramdown::ImageCache::Error) do
      @store.materialize(png_data_uri, content_id: "../../etc")
    end
  end
end
