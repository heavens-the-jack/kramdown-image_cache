# Kramdown::ImageCache

[日本語版 / Japanese](./README.ja.md)

A small Kramdown extension for Markdown that stores images inline as base64 `data:` URIs. **The stored Markdown is never modified.** At render time, each embedded image is written once to a content-addressable file and the `<img src>` is rewritten to a plain, HTTP-cacheable URL.

Why: a `data:` URI has no URL, so browsers and CDNs cannot cache it, and every page view re-sends the image bytes (about 33% larger than the binary). Keeping the images inline in the source is still attractive, because the database row or the git repository stays a single, self-contained, portable blob of text. This gem keeps that property and fixes the delivery side.

For the design rationale, rejected alternatives and trade-offs, see [`doc/design.md`](./doc/design.md) ([Japanese version](./doc/design.ja.md)).

## Features

- Hooks into Kramdown's `convert_img`, so only images that the parser already identified as images are touched (no regex over the rendered HTML).
- Writes each image once as `<root>/<content_id>/<sha256>.<ext>`. Later renders reuse the file, so browsers and CDNs can cache it indefinitely.
- The cache is a derived artifact: it can be deleted at any time and is rebuilt on the next render.
- `sync` / `purge` / `sweep` keep the cache tidy as content changes (namespaced per `content_id`; an update removes only images that are no longer referenced).
- Optional ActiveRecord integration (`after_commit`).
- Runtime dependencies: `kramdown` and `base64` only. No Rails required.

## Supported image formats

Only **PNG, JPEG, GIF and WebP** are cached. Anything else (SVG, HTML, unknown types) is left in the output as a `data:` URI.

- The format is decided by the file's **signature (magic bytes)**, not by the declared MIME type. If the declaration and the bytes disagree, the image is not cached.
- The extension of the cached file comes from the detected format, never from the declaration. `image/jpg` is accepted as a declaration of JPEG.
- The `data:image/` scheme prefix must be lowercase. Format names are case-insensitive.

**Why an allowlist:** the delivery layer typically maps the file extension to a `Content-Type`. If arbitrary content could be written under an image extension (or SVG, which can carry scripts, were cached), the cache would become a way to serve active content from your origin.

## Installation

Not published to RubyGems yet. Reference a tag from GitHub in your Gemfile:

```ruby
gem "kramdown-image_cache", git: "https://github.com/heavens-the-jack/kramdown-image_cache", tag: "v0.1.0"
```

If you use `Bundler.require`, `kramdown/image_cache` is required automatically. Otherwise add `require "kramdown/image_cache"`. The ActiveRecord integration is **not** loaded by that; require `kramdown/image_cache/model` explicitly if you want it.

GitHub Flavored Markdown input (`input: "GFM"`) needs the `kramdown-parser-gfm` gem, which this gem does not depend on. Add it to your own Gemfile if you use it.

## Usage

### 1. Configure a store

```ruby
Kramdown::ImageCache.default_store =
  Kramdown::ImageCache::Store.new(root: "/var/app/storage/image_cache")
```

You can also pass `store:` to each call instead of setting a default.

### 2. Render

```ruby
html, warnings = Kramdown::ImageCache.render(post.body, content_id: post.id)
```

Embedded images are written on first render, and `src` becomes `/images/cache/<content_id>/<hash>.<ext>` (change the prefix with `url_prefix:`). The source Markdown is untouched.

Options: `store:`, `input:` (default `"kramdown"`, e.g. `"GFM"`), `url_prefix:` (default `"/images/cache"`).

If no store is configured, `render` raises `Kramdown::ImageCache::Error`. If you use `Converter` directly and `store` or `content_id` is not set, images are left as `data:` URIs.

`content_id` may be an Integer or a String made of word characters and hyphens (`/\A[\w-]+\z/`). Anything else raises `Kramdown::ImageCache::Error`, because the id becomes a directory name.

### 3. Clean up after changes

```ruby
Kramdown::ImageCache.sync(post.body, content_id: post.id)   # after create/update
Kramdown::ImageCache.purge(post.id)                          # after destroy
```

`sync` takes the *new* body and deletes only cached images that it no longer references. With ActiveRecord:

```ruby
require "kramdown/image_cache/model"

class Post < ApplicationRecord
  include Kramdown::ImageCache::Model
  image_cache_source :body
end
```

This uses `after_commit`, so a rolled-back transaction never deletes files.

As a safety net for changes that bypass these hooks (manual edits, migrations, restores), run an occasional sweep, for example weekly:

```ruby
Kramdown::ImageCache.default_store.sweep(Post.pluck(:id))
```

### Different URL prefix per context

`url_prefix` and `content_id` are per call, so the same Markdown can be rendered for different audiences:

```ruby
# Public page
Kramdown::ImageCache.render(post.body, content_id: post.id)

# Behind authentication, served by a controller that checks permissions
Kramdown::ImageCache.render(post.body, content_id: post.id, url_prefix: "/admin/images/cache")

# Served from a CDN host
Kramdown::ImageCache.render(post.body, content_id: post.id, url_prefix: "https://cdn.example.com/img")
```

To customize rendering, subclass `Kramdown::ImageCache::Converter`, override e.g. `convert_a`, and call `super`. Create it with `Converter.new(doc.root, doc.options)`, then set `store`, `content_id` and `url_prefix` before `convert`.

## Your responsibilities when serving the cache

This gem only writes files. Serving them safely is up to you:

- Derive `Content-Type` from the **file extension** (`.png`, `.jpg`, `.gif`, `.webp`) and nothing else.
- Send `X-Content-Type-Options: nosniff`. This is what prevents a file that is both a valid image and valid HTML (a polyglot) from being interpreted as HTML by the browser. The signature check cannot rule such files out; `nosniff` does.
- Send `Content-Security-Policy: sandbox` on image responses as defense in depth.
- Apply your own access control. Anyone who can reach the URL can read the image; the hash is not a secret.
- Validate request paths (for example `/\A[\w-]+\z/` for the id and `/\A[0-9a-f]{64}\.(png|jpg|gif|webp)\z/` for the file name) if you serve with your own code.
- File names are content hashes, so `Cache-Control: public, max-age=31536000, immutable` is accurate.

**Do not use this with encrypted content.** Cached files are written to disk in plaintext, which defeats the purpose of encrypting the source.

## Examples without Rails

### Sinatra

```ruby
require "sinatra"
require "kramdown/image_cache"

STORE = Kramdown::ImageCache::Store.new(root: File.join(__dir__, "image_cache"))
POSTS = { 1 => File.read("post1.md") }

get "/posts/:id" do
  id = Integer(params[:id])
  html, = Kramdown::ImageCache.render(POSTS.fetch(id), content_id: id, store: STORE)
  html
end

get "/images/cache/:id/:file" do
  halt 404 unless params[:id].match?(/\A[\w-]+\z/)
  halt 404 unless params[:file].match?(/\A[0-9a-f]{64}\.(png|jpg|gif|webp)\z/)

  path = File.join(STORE.root, params[:id], params[:file])
  halt 404 unless File.file?(path)

  content_type({ "png" => "image/png", "jpg" => "image/jpeg",
                 "gif" => "image/gif", "webp" => "image/webp" }.fetch(File.extname(path).delete(".")))
  headers "X-Content-Type-Options" => "nosniff",
          "Content-Security-Policy" => "sandbox",
          "Cache-Control" => "public, max-age=31536000, immutable"
  send_file path
end
```

### Static site generation

Point the store at a directory inside your output folder and render each page at build time:

```ruby
store = Kramdown::ImageCache::Store.new(root: "public/images/cache")

Dir["content/*.md"].each do |file|
  slug = File.basename(file, ".md")
  html, = Kramdown::ImageCache.render(File.read(file), content_id: slug, store: store)
  File.write("public/#{slug}.html", html)
end
```

Configure your static host to send the headers listed above for `/images/cache/`.

## Versioning and API stability

This gem follows [Semantic Versioning](https://semver.org/). The following public API is kept compatible; a breaking change to any of it bumps the **major** version:

- `Kramdown::ImageCache::Store` (`new(root:)`, `materialize`, `sync`, `purge_all`, `sweep`)
- `Kramdown::ImageCache::Converter` (`content_id`, `store`, `url_prefix`, and subclassing)
- `Kramdown::ImageCache.render`, `.sync`, `.purge` and `Kramdown::ImageCache::Scanner.data_uris`

Adding a format to the allowlist (for example AVIF) is a backward-compatible change and is released as a **minor** version. Every release is recorded in [`CHANGELOG.md`](./CHANGELOG.md).

## Testing

Tests run in Docker only, so nothing is installed on your machine:

```
bin/docker-test                       # Ruby 3.3 (default)
TEST_RUBY_VERSION=3.4 bin/docker-test # another Ruby version
```

`bin/docker-test` passes your UID/GID to the container so generated files are not owned by root. Dependencies are cached under `.bundle/` (git-ignored). Without Docker: `bundle install && bundle exec rake test`.

## License

MIT
