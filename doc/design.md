# Design Document: Kramdown::ImageCache

[日本語版 / Japanese](./design.ja.md)

**Created**: 2026-09-09
**Author**: Jack
**Purpose**: This is a design document that doubles as the minutes of the technical discussion. It records not only the conclusion but also the alternatives that were considered and rejected along the way, with the reasons.

---

## 0. Requirements and acceptance criteria

### Requirements

| ID | Requirement |
|---|---|
| R1 | Usable from a public Git tag (`v0.1.0`) via `git:` / `tag:` in a Gemfile (the gemspec has `source_code_uri` and `changelog_uri`, and `CHANGELOG.md` is shipped) |
| R2 | Only PNG / JPEG / GIF / WebP are cached. The format is decided by signature, not by declaration; anything outside the allowlist stays as a `data:` URI |
| R3 | Works without warnings on Ruby 3.4 and later (`base64` is an explicit dependency) |
| R4 | Rendering can be extended by subclassing `Converter`, and `url_prefix` / `content_id` can change per render. `input: "GFM"` works. If `store` / `content_id` is not set, output stays as `data:` |
| R5 | `content_id` works as an Integer or a String. An invalid id raises `Error` and writes nothing |
| R6 | Usable without Rails (Sinatra, static site generation). Dependencies are `kramdown` and `base64` only |
| R7 | The README documents the allowlist and its rationale, the delivery layer's responsibilities, that the gem must not be used with encrypted content, and minimal examples (English is canonical; a Japanese version sits alongside) |

### Acceptance criteria

- `bin/docker-test` passes on both Ruby 3.3 and 3.4, with no warnings originating from this gem
- Formats outside the allowlist (SVG, HTML, ...) and images whose declaration disagrees with their signature stay as `data:` and no file is written (`test/materializer_test.rb`, `test/converter_test.rb`)
- The public contract (subclassing, GFM, pass-through when unconfigured, `content_id` shapes) is pinned by `test/contract_test.rb`
- `gem build` succeeds without warnings, and the built gem contains `CHANGELOG.md`, the READMEs and the LICENSE

---

## 1. Background and problem

In the target application, Markdown user content does not manage images as separate physical files. Instead, **images are base64-encoded and embedded directly in the Markdown body**. Metadata lives in the database, and the content itself (base64 included) is committed to a local git repository the application carries with it.

The goal of this approach is clear: **high portability, where "the body (plus the git repository) alone contains everything."** There is a consistent philosophy behind it: no external object storage (S3 and the like) as a place to put files, and no responsibility on the application side for managing image files separately at all.

The approach has a side effect, though. Because **the image bytes are embedded as text in the rendered HTML**, the following happens:

- Neither browser caches nor CDN caches can help (`<img src="data:...">` has no URL, so it is not subject to HTTP caching)
- Every page view transfers the full image bytes again (about 33% larger because of base64)

Eliminating this side effect was the starting point.

---

## 2. Alternatives considered and rejected

### 2-1. A Rack middleware that rewrites the whole response

The first idea raised: after the HTTP response is generated, a middleware scans the entire response body with a regular expression or similar, detects base64 images, writes them to files and replaces them with URLs.

**Reasons for rejection**:
- With streaming responses the body is only visible chunk by chunk, so a base64 string may be split across a chunk boundary
- There is a risk of false positives on strings that merely look like base64
- Scanning the whole response on every request is inefficient
- The Markdown parser already knows exactly where the images are, so guessing from the HTML string afterwards without using that information is the wrong approach

### 2-2. Rewrite the body at save time into physical file references

The alternative of "converting once at save time rather than at response time." A save hook detects base64 images, writes them out as files, and then **rewrites the body in the database itself into URL references**.

**Reasons for rejection** (learned from feedback):
- The **portability** of "the database (or git repository) alone is enough" is lost. Once the body holds URL references, the content no longer stands without the physical files those URLs point to, breaking the premise that the database content is the only source of truth
- It also contradicts the original key design principle that "the cache can always be rebuilt from the database content"

---

## 3. Adopted approach

**Convert base64 images into physical files only inside Kramdown's HTML conversion (`convert_img`). The body in the database or git repository is never modified.**

Kramdown is designed so that you can subclass `Converter::Html` and override methods following the `convert_#{element type}` naming convention to replace the conversion logic per element. We override `convert_img` for image elements (`:img`); if `src` has the form `data:image/...;base64,...`, we write it out as a physical file and swap in a reference to it.

```ruby
class Converter < Kramdown::Converter::Html
  def convert_img(el, indent)
    src = el.attr["src"]
    if src&.start_with?("data:image/")
      rewritten = store.materialize(src, content_id: content_id)
      # copy el with src replaced, then delegate to super to build the <img> tag
    end
    super(el, indent)
  end
end
```

**Pitfalls found during implementation (both surfaced only by actually running the tests in Docker; code review alone would not have caught them)**:

1. `Kramdown::Converter::Base.new` is made `private_class_method`, and the public API is limited to the `.convert` class method (which instantiates internally and immediately runs `#convert`). Here we want to set `content_id` / `store` on the instance before calling `#convert`, so the `Converter` subclass declares `public_class_method :new` to re-expose `new` on this subclass only
2. `Kramdown::Element` exposes `attr` (read) but not `attr=` (write). The original implementation, which copied the element and rewrote only `src` (`el.dup; el.attr = el.attr.dup`), did not work. Instead we build a new element with the same type / value / options via `Kramdown::Element.new(el.type, el.value, new_attr, el.options)`

Advantages of this approach over 2-1 and 2-2:

- Processing happens only where the Markdown parser has already told us "this is an image," so there are no false positives and no streaming-split problem
- **The body (database / git repository) stays completely unchanged**. Both portability and the premise that "the cache can always be regenerated from the body" are satisfied
- The cache directory can be treated as a fully disposable, regenerable derived artifact (even after `rm -rf`, re-rendering all content restores it)

---

## 4. Components

| Component | Role |
|---|---|
| `Materializer` | Parses base64 data URIs, computes the SHA256 hash, and writes files atomically. The lowest-level part; knows nothing about `content_id` |
| `Store` | Manages the content-addressable cache, namespaced per `content_id` (materialize / sync / purge_all / sweep) |
| `Converter` | Kramdown's `convert_img` hook. Calls `Store` during rendering and rewrites `src` |
| `Scanner` | Returns only the list of base64 image URIs in the body, without generating HTML (used for sync at save time; avoids the waste of a full render) |
| `Model` (optional) | A mixin that wires sync / purge automatically into ActiveRecord's `after_commit` |

### File path design: content-addressable + content_id namespace

```
<root>/<content_id>/<sha256>.<ext>
```

Using the hash as the file name means **replacing an image automatically changes its file name** (no cache invalidation logic is needed). Splitting directories by `content_id` makes it obvious which content owns each cache file, so cleanup can be tied naturally to the content's own lifecycle events: update and destroy.

**Trade-off**: Namespacing by `content_id` means that when several contents reuse the same image (the same logo, for example), it cannot be deduplicated. Combining global hash-only deduplication with clear per-`content_id` ownership requires a "reference counting" scheme (real files live at a global hash path, and only the `content_id → hash` references are recorded separately), which makes the implementation one level more complex. Given the expected scale of use (images are mostly unique per content), **we chose the content_id namespace scheme for simplicity**. If image reuse turns out to be common, we will consider moving to reference counting.

### Design decisions behind the allowlist

Only **PNG / JPEG / GIF / WebP** are cached; everything else stays as a `data:` URI.

- **Decide by signature**: the `data:image/<format>` declaration can be written freely by an attacker, so it is not trusted. We look at the leading bytes of the decoded data (the 8-byte PNG signature, JPEG's `FF D8 FF`, `GIF87a` / `GIF89a`, `RIFF....WEBP`) and write out only what matches the declaration. We do not decode (render) the image
- **The extension comes from the detection result**: a delivery layer usually decides `Content-Type` from the file extension. If the extension came from the declaration, HTML or similar could be served under an image extension. `image/jpg` is accepted as a (non-standard but common) declaration of JPEG, and the extension is `jpg`
- **The scheme part is lowercase only**: `data:image/` is supported in lowercase only. Format names are case-insensitive
- **Polyglots are stopped by the delivery layer**: a file that is valid both as an image and as HTML cannot be excluded by signature checking. We rely on the delivery layer's `X-Content-Type-Options: nosniff` (and `Content-Security-Policy: sandbox`) to stop them, and state this explicitly in the README as a delivery-side responsibility
- **How to extend**: to add a format, add its declared name and extension to `Materializer::ALLOWED_FORMATS`, and add its signature to `Materializer.detect_extension`

---

## 5. Cache cleanup (differential deletion)

### 5-1. Considered but not adopted: using git diff

Given that every content update necessarily involves a git commit, the idea was raised that "the `git diff` between the commits before and after the update could pinpoint the images to delete (the lines that disappeared), which is more efficient than parsing the whole body every time."

**Technically this works** (a pathspec narrows it to changes in the target file, and if the commit SHA is kept on the database side, `git diff <old_sha> <new_sha> -- <path>` yields the difference, and so on).

**Reasons we did not adopt it**:

1. **Efficiency is reversed**: the current implementation shells out to the git binary via `fork` / `exec` every time. Process startup adds overhead of a few to a dozen-odd ms (depending on the OS and the state of the repository). Meanwhile, "scan the body with a regular expression and hash the embedded images with SHA256" finishes as an in-process computation in under a millisecond for compressed images. **So the naive full parse is faster than a git-diff-based approach**
2. git diff is fundamentally about line-level change detection, and if the premise that one base64 image is stored as one line breaks (for example, lines get wrapped partway), the diff may not have the expected granularity
3. For content deletion (destroy), diff cannot be used anyway, so separate logic is needed, and the implementation would split into two paths

(If git operations as a whole are moved to `rugged`, the in-process libgit2 binding, in the future, the process startup cost disappears and this conclusion could change. We judged that this alone did not justify such a migration.)

### 5-2. Adopted: full parse of the new body + diff against files on disk

```ruby
def sync(content_id, referenced_data_uris)
  keep = referenced_data_uris.filter_map { |uri| Materializer.parse(uri)&.filename }.to_set
  # delete only the files under content_id that are not in keep
end
```

- Parse the new body to build "the set of hashes currently referenced" (`Scanner` does only a lightweight parse with no HTML generation)
- Compare with the list of files under `content_id` on disk, and delete only those that are no longer referenced
- **Delete only the difference, rather than deleting everything on every update**. Unchanged images are re-hashed, but because the file already exists no write occurs (`Materializer.write` returns immediately if the file exists)

### 5-3. Why `after_commit`

If file deletion runs in a callback before the database commit, such as `after_update`, **the filesystem deletion cannot be undone even if the transaction later fails and is rolled back**. The database returns to its original state, but the cache files are gone. Non-transactional side effects such as file operations belong in `after_commit` (for both `update` and `destroy`), and `Model` follows this.

### 5-4. A low-frequency sweep as insurance

`sync` / `purge_all` only work for "updates and deletions that went through the hook." If a change bypasses the hook (direct edits from an admin console, data migration scripts, restores from backup, or plain bugs), cache files quietly become orphaned.

The only remedy is **a low-frequency (roughly weekly to monthly) safety-net sweep (`Store#sweep`) that compares "the complete list of currently live content_ids" with the actual cache directory and deletes directories of content_ids that are not live**. It does not replace the main path (`sync` / `purge_all`); it is positioned strictly as insurance.

---

## 6. Relationship to Kamal deployment

This cache directory raises the same kind of question as the volume configuration when deploying SQLite3 with Kamal.

- **Without a persistent volume**: the cache disappears on every deploy. It is fully regenerable, so **nothing breaks**, but right after a deploy every content has to pay the "first access = regeneration" cost again, which can cause a temporary latency increase
- **With a persistent volume**: the cache survives across deploys, avoiding that cold start. The advantage that only the database (or git repository) needs to be backed up is not lost

Which to choose depends on deploy frequency and the first-access latency you can tolerate.

---

## 7. Other notes and future considerations

- **SVG support**: SVG can contain scripts, so it is outside the allowlist (chapter 4), and `data:image/svg+xml;base64,...` is output as a `data:` URI (not cached). Supporting it would require, in addition to sanitization (`Loofah` or similar), a separate design that adds `Content-Security-Policy` on the delivery side
- **Format extensibility**: because everything is controlled inside `convert_img`, supporting a new format such as JXL only requires "transcoding the decoded binary into another format before writing it." Extensions such as listing several formats in a `<picture>` element and letting the browser choose also fit naturally inside the same hook
- **Deduplication**: as noted in chapter 4, namespacing by `content_id` gives up deduplication of the same image across contents. Depending on actual usage patterns, consider moving to reference counting if needed
- **Automated test results**: all 54 tests (166 assertions) pass in Docker (Ruby 3.3 / 3.4, kramdown 2.5.2, minitest 5) (2026-11-10). Run with `bin/docker-test` (switch versions with `TEST_RUBY_VERSION=3.4 bin/docker-test`)
