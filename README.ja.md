# Kramdown::ImageCache

[English](./README.md)

Base64の`data:` URIとして画像を本文に直接埋め込んでいるMarkdown向けの、kramdownの小さな拡張です。**保存してある本文は一切変更しません。** レンダリング時にだけ、埋め込み画像をcontent-addressableなファイルとして一度書き出し、`<img src>`をHTTPキャッシュ可能な通常のURLに書き換えます。

背景：`data:` URIにはURLがないため、ブラウザもCDNもキャッシュできず、ページを開くたびに画像バイト（バイナリより約33%大きい）を毎回転送することになります。一方で、画像を本文に埋め込んでおく方式は、DBの1行やgitリポジトリだけで完結する可搬性が魅力です。このgemはその性質を保ったまま、配信側の問題だけを解消します。

設計の背景・却下した案・トレードオフは [`doc/design.md`](./doc/design.md) にまとめています。

## できること

- kramdownの`convert_img`に割り込むため、パーサーが画像と判定した要素だけを処理します（出力HTMLへの正規表現スキャンはしません）。
- 画像を`<root>/<content_id>/<sha256>.<ext>`として一度だけ書き出し、以降は再利用します。ブラウザ・CDNで長期キャッシュできます。
- キャッシュは派生物です。いつ消しても、次のレンダリングで再生成されます。
- `sync`／`purge`／`sweep`でキャッシュを掃除します（`content_id`ごとに分割。更新時は参照されなくなった画像だけを削除）。
- ActiveRecord連携（`after_commit`）をオプションで同梱。
- 実行時の依存は`kramdown`と`base64`のみ。Railsは不要です。

## 対応する画像形式

キャッシュするのは**PNG・JPEG・GIF・WebPのみ**です。それ以外（SVG、HTML、不明な形式）は`data:` URIのまま出力に残します。

- 形式は宣言されたMIMEタイプではなく、ファイルの**シグネチャ（先頭バイト）**で判定します。宣言とバイト列が食い違う場合はキャッシュしません。
- キャッシュファイルの拡張子は、宣言ではなく判定した形式から決めます。`image/jpg`はJPEGの宣言として受け入れます。
- スキーム部の`data:image/`は小文字のみ対応です。形式名の大小文字は区別しません。

**許可リストにする理由：** 配信側は通常、拡張子から`Content-Type`を決めます。任意の内容を画像の拡張子で書き出せたり、スクリプトを含められるSVGをキャッシュしたりすると、キャッシュ経由で自分のオリジンからアクティブなコンテンツを配信できてしまうためです。

## インストール

まだRubyGemsには公開していません。GitHubのタグをGemfileで参照します。

```ruby
gem "kramdown-image_cache", git: "https://github.com/heavens-the-jack/kramdown-image_cache", tag: "v0.1.0"
```

`Bundler.require`を使う場合は`kramdown/image_cache`が自動で`require`されます。使わない場合は`require "kramdown/image_cache"`を追加してください。ActiveRecord連携はこれでは読み込まれません。使う場合は`kramdown/image_cache/model`を明示的に`require`します。

GFM入力（`input: "GFM"`）には`kramdown-parser-gfm`が必要です。このgemは依存していないので、利用側のGemfileに追加してください。

## 使い方

### 1. Storeを用意する

```ruby
Kramdown::ImageCache.default_store =
  Kramdown::ImageCache::Store.new(root: "/var/app/storage/image_cache")
```

デフォルトを設定せず、呼び出しごとに`store:`を渡すこともできます。

### 2. レンダリングする

```ruby
html, warnings = Kramdown::ImageCache.render(post.body, content_id: post.id)
```

埋め込み画像は初回レンダリング時に書き出され、`src`は`/images/cache/<content_id>/<hash>.<ext>`になります（`url_prefix:`で変更可）。元の本文は変更されません。

オプション：`store:`、`input:`（既定`"kramdown"`。例：`"GFM"`）、`url_prefix:`（既定`"/images/cache"`）。

Storeが未設定だと`render`は`Kramdown::ImageCache::Error`を送出します。`Converter`を直接使い、`store`か`content_id`が未設定の場合は、画像は`data:` URIのまま出力されます。

`content_id`は整数、または英数字・`_`・`-`だけの文字列（`/\A[\w-]+\z/`）です。IDはディレクトリ名になるため、それ以外は`Kramdown::ImageCache::Error`になります。

### 3. 変更後に掃除する

```ruby
Kramdown::ImageCache.sync(post.body, content_id: post.id)   # 作成・更新後
Kramdown::ImageCache.purge(post.id)                          # 削除後
```

`sync`には*新しい*本文を渡します。もう参照されていないキャッシュ画像だけが削除されます。ActiveRecordでは次のようにします。

```ruby
require "kramdown/image_cache/model"

class Post < ApplicationRecord
  include Kramdown::ImageCache::Model
  image_cache_source :body
end
```

`after_commit`を使うため、ロールバックされたトランザクションでファイルだけ消える不整合は起きません。

フックを経由しない変更（手動編集、データ移行、リストア）への保険として、週次などで安全網のスイープを実行してください。

```ruby
Kramdown::ImageCache.default_store.sweep(Post.pluck(:id))
```

### 文脈ごとにURLの接頭辞を変える

`url_prefix`と`content_id`は呼び出しごとに指定できるので、同じ本文を用途別にレンダリングできます。

```ruby
# 公開ページ
Kramdown::ImageCache.render(post.body, content_id: post.id)

# 認証の内側。権限を確認するコントローラで配信する
Kramdown::ImageCache.render(post.body, content_id: post.id, url_prefix: "/admin/images/cache")

# CDNのホストから配信する
Kramdown::ImageCache.render(post.body, content_id: post.id, url_prefix: "https://cdn.example.com/img")
```

描画をカスタマイズするには、`Kramdown::ImageCache::Converter`を継承して`convert_a`などを上書きし、`super`を呼びます。`Converter.new(doc.root, doc.options)`で生成し、`convert`の前に`store`・`content_id`・`url_prefix`を設定します。

## キャッシュを配信するときの責務

このgemはファイルを書き出すだけです。安全に配信する責務は利用側にあります。

- `Content-Type`は**ファイルの拡張子**（`.png`・`.jpg`・`.gif`・`.webp`）だけから決めてください。
- `X-Content-Type-Options: nosniff`を付けてください。画像としてもHTMLとしても有効なファイル（ポリグロット）をブラウザがHTMLとして解釈するのを防ぐのは、これです。シグネチャ判定ではそうしたファイルを排除できません。
- 多層防御として、画像のレスポンスに`Content-Security-Policy: sandbox`を付けてください。
- アクセス制御は利用側で行ってください。URLに到達できる人は画像を読めます。ハッシュは秘密ではありません。
- 自前のコードで配信する場合は、リクエストのパスを検証してください（例：IDは`/\A[\w-]+\z/`、ファイル名は`/\A[0-9a-f]{64}\.(png|jpg|gif|webp)\z/`）。
- ファイル名は内容のハッシュなので、`Cache-Control: public, max-age=31536000, immutable`が正確に使えます。

**暗号化したコンテンツには使わないでください。** キャッシュファイルは平文でディスクに書き出されるため、本文を暗号化する意味がなくなります。

## Railsを使わない例

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

### 静的サイト生成

Storeの場所を出力ディレクトリ内に向け、ビルド時にページごとにレンダリングします。

```ruby
store = Kramdown::ImageCache::Store.new(root: "public/images/cache")

Dir["content/*.md"].each do |file|
  slug = File.basename(file, ".md")
  html, = Kramdown::ImageCache.render(File.read(file), content_id: slug, store: store)
  File.write("public/#{slug}.html", html)
end
```

静的ホスティング側で、`/images/cache/`に上記のヘッダーを付けるよう設定してください。

## テスト

テストはDockerだけで実行します。ホストには何もインストールしません。

```
bin/docker-test                       # Ruby 3.3（既定）
TEST_RUBY_VERSION=3.4 bin/docker-test # 別のRubyの版
```

`bin/docker-test`は実行ユーザーのUID/GIDをコンテナに渡すので、生成物がroot所有になりません。依存gemは`.bundle/`（`.gitignore`済み）にキャッシュされます。Dockerを使わない場合は`bundle install && bundle exec rake test`です。

## ライセンス

MIT
