# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-10

### Added
- Initial release: lazily materialize `data:image/...;base64,...` images in
  Kramdown-rendered Markdown into a content-addressable file cache, with
  `render`, `sync` and `purge` APIs.
- Contract tests covering `Converter` subclassing, the `GFM` input parser,
  behavior without a configured store or `content_id`, and `content_id` shapes.

### Security
- Only PNG, JPEG, GIF and WebP images are cached, verified by file signature
  rather than by the declared MIME type. Other data URIs (for example SVG) are
  left as `data:` URIs.

### Dependencies
- Add `base64` as a runtime dependency (no longer a default gem as of Ruby 3.4).
