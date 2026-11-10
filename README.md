# Kramdown::ImageCache

Markdownの本文にBase64エンコードされた画像を直接埋め込んで保存しているとき（物理ファイル管理を持たず、DB／gitリポジトリだけで完結させたいとき）に、**本文は一切変更せずに**、レンダリング時にだけそれをHTTPキャッシュ可能な物理ファイルへ変換する、kramdown用の小さな拡張です。

設計の背景・検討過程・却下した案とその理由は [`doc/design.md`](./doc/design.md) にまとめています。実装する／利用する前に、まずこちらに目を通してください。

## できること

- kramdownの`convert_img`フックに割り込み、`data:image/...;base64,...`形式の画像だけを検出し、初回レンダリング時に content-addressable（SHA256ハッシュをファイル名にした）ファイルとして書き出す
- 2回目以降のレンダリングでは既存ファイルを再利用するだけなので、以降はブラウザ・CDN側のHTTPキャッシュに任せられる
- DBやgitリポジトリ上の本文（Base64込み）はそのまま。**キャッシュはいつでも本文から再生成可能な派生物**という位置づけを崩さない
- コンテンツ更新・削除に合わせてキャッシュを掃除する`sync`／`purge`API（`content_id`ごとにネームスペース分割し、更新時は「もう参照されていない画像だけ」を差分削除）
- Railsで使う場合の`after_commit`連携（`Kramdown::ImageCache::Model`）をオプションで同梱

## インストール

まだRubyGemsには公開していません。GitHubリポジトリから、対象アプリのGemfileで参照します（タグ付きの版は公開準備中です）。

```ruby
gem "kramdown-image_cache", git: "https://github.com/heavens-the-jack/kramdown-image_cache"
```

`Bundler.require`は、gem名の`-`を`/`に置き換えて自動`require`するため（`kramdown-image_cache` → `kramdown/image_cache`）、通常は明示的な`require`文は不要です。

## 使い方

### 1. Storeを用意する

```ruby
# config/initializers/kramdown_image_cache.rb などで一度だけ
Kramdown::ImageCache.default_store =
  Kramdown::ImageCache::Store.new(root: Rails.root.join("storage", "image_cache"))
```

VPS上でKamalを使ってデプロイしている場合、このディレクトリを永続ボリュームにするかどうかはトレードオフです。詳しくは [`doc/design.md`](./doc/design.md) の「Kamalデプロイとの関係」を参照してください。

### 2. 表示時：レンダリングする

```ruby
html, warnings = Kramdown::ImageCache.render(post.body, content_id: post.id)
```

本文中のBase64画像は、初回アクセス時にだけ物理ファイル化され、`src`が`/images/cache/<content_id>/<hash>.<ext>`（`url_prefix:`で変更可）に書き換わったHTMLが返ります。ここでは`post.body`（DB上の本文）自体は一切変更されません。

配信は、`public/`配下に置いて静的配信させるか、`Cache-Control: public, max-age=31536000, immutable`を付けた専用コントローラで`send_file`するのがおすすめです（ハッシュ名＝内容不変なファイルなので`immutable`が文字通り正確です）。

### 3. 保存時：掃除する

Railsで`ActiveRecord`を使っているなら、`Model`をincludeするのが手軽です。

```ruby
class Post < ApplicationRecord
  include Kramdown::ImageCache::Model
  image_cache_source :body
end
```

これで、保存時（`create`／`update`のコミット後）に「新しい本文でもう参照されなくなった画像」だけが自動的に削除され、削除時（`destroy`のコミット後）にはそのコンテンツの画像が丸ごと削除されます。`after_commit`を使っているため、トランザクションがロールバックされた場合にファイルだけ消える、という不整合は起きません。

手動で呼ぶ場合は以下の2つのモジュール関数で同じことができます。

```ruby
Kramdown::ImageCache.sync(post.body, content_id: post.id)   # 更新後
Kramdown::ImageCache.purge(post.id)                          # 削除後
```

### 4. 保険：低頻度の安全網スイープ

`sync`／`purge`はあくまで「そのフックを通った更新・削除」でしか掃除しません。管理コンソールからの直接編集やデータ移行など、フックを経由しない変更が将来発生した場合に備え、週次〜月次程度で以下のような安全網タスクを用意しておくことを推奨します。

```ruby
# lib/tasks/image_cache.rake （例）
task sweep_image_cache: :environment do
  Kramdown::ImageCache.default_store.sweep(Post.pluck(:id))
end
```

## テスト

### Docker（推奨・ホストのRuby環境に何もインストールしない）

このgemディレクトリ内だけで完結する、テスト専用のDocker Compose構成を用意しています。ホストには公式`ruby:3.2-slim`イメージ以外何もインストールしません。

```
./bin/docker-test
```

初回は`bundle install`が走る分だけ時間がかかりますが、依存gemは`.bundle/`（`.gitignore`済み、ホスト側にbind mountされる）にキャッシュされるため、2回目以降は高速です。`bin/docker-test`は実行ユーザーのUID/GIDをコンテナに渡すので、生成される`Gemfile.lock`等がroot所有になる心配もありません。

直接`docker compose run --rm test`を呼んでも動きますが、その場合は`Gemfile.lock`等がroot所有で作られる可能性があります（気になる場合は`sudo chown -R $(id -u):$(id -g) .`で直せます）。

### ホストにRuby/kramdownが既にある場合

```
bundle install
bundle exec rake test
```

自動テストは、Docker上（Ruby 3.3.11、kramdown 2.5.2、minitest 5）で29件（51アサーション）すべて成功することを確認済みです。

## ライセンス

MIT
