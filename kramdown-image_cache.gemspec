# frozen_string_literal: true

require_relative "lib/kramdown/image_cache/version"

Gem::Specification.new do |spec|
  spec.name = "kramdown-image_cache"
  spec.version = Kramdown::ImageCache::VERSION
  spec.authors = ["Jack.G.Mutsuen"]
  spec.email = ["heavens.the.jack@gmail.com"]

  spec.summary = "Materialize base64-embedded images in Kramdown-rendered Markdown into a content-addressable file cache."
  spec.description = <<~DESC
    Kramdown::ImageCache lets you keep base64-encoded images inline in Markdown
    content (so the stored source stays a single, portable, self-contained blob
    of text) while still getting real, HTTP-cacheable image URLs at render time.
    It hooks into Kramdown's HTML converter to lazily materialize each embedded
    image into a content-addressable file the first time it's rendered, and
    provides a small sync/purge API for keeping that cache tidy as content
    changes - without ever mutating the stored Markdown itself.
  DESC
  spec.homepage = "https://github.com/heavens-the-jack/kramdown-image_cache"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*.rb", "doc/**/*.md", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", ">= 0.1"
  spec.add_dependency "kramdown", ">= 2.3"

  spec.add_development_dependency "kramdown-parser-gfm", "~> 1.1"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
