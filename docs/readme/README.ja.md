<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Hop アプリアイコン — 4本線のアスタリスク">

# Hop

**macOS のメニューバーに住む小さな相棒。タイマー、タイムトラッカー、
やること、スリープ防止、システムモニター、クリップボード履歴、
ファイル変換、ウィンドウ管理、そして軽量トレントクライアント——
アイコン上の最大4つのタブに振り分けて。ワンクリックで、必要なものが
すべてそこに。**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Installs](https://img.shields.io/endpoint?url=https%3A%2F%2Fwww.antonshakirov.com%2Fapi%2Fhop%2Finstalls&color=ffd60a)](https://www.antonshakirov.com/api/hop/installs)
[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · **日本語**

<img src="https://www.antonshakirov.com/products/hop/screens/ja/overview.png" width="360" alt="Hop パネル — ドットマトリクス表示のメニューバータイマー、プリセットとワーク・レストサイクル">

</div>

Hop は Mac のメニューバーに常駐し、こまごましたユーティリティを
まとめて置き換えます。ポモドーロ式タイマー、やることリスト付きの
タイムトラッカー、caffeinate 風のスリープブロッカー、システムモニター、
クリップボードマネージャー、ドラッグ＆ドロップのファイル変換、
ウィンドウスナップ、そして軽量トレントクライアント——軽量な
ネイティブアプリ 1 本に、よく使うモジュールをアイコン上の最大4つの
タブへ振り分けて。

## ダウンロード

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — 開いて `Hop.app` をアプリケーションフォルダへドラッグ（推奨）
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — 同じアプリの素のアーカイブ（内蔵アップデーターが使用）。[最新リリース](https://github.com/antonyshakirov/hop/releases/latest)を参照
- 高速ミラー: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

macOS 15 以降での初回起動：まず Hop を一度開こうとしてから、
**システム設定 → プライバシーとセキュリティ → このまま開く**へ進み、
**開く**を確認してください。作者が Apple Developer Program のメンバー
シップを利用できないため、Hop は公証されていません。ソースコードは公開
されており、内蔵アップデートは Ed25519 で検証されます。macOS 14 以降が
必要です。

## 機能

### スペース

アイコンには最大4つのタブを持て、各モジュールを好きなタブへドラッグ
できます。タイマーを一つ、モニターをもう一つ、めったに開かないものは
脇へ。「非アクティブ」の棚は、脇へ置いたものを削除せずに取っておきます。

### タイマーとサイクル

ワンジェスチャーで設定できるドットマトリクスのカウントダウン。数字を
ドラッグする、電子レンジのように時間を打ち込む、プリセットを選ぶ——
どれでも。ワーク・レストサイクル（25/5 のポモドーロ、52/17、90/15、
もちろん自分好みにも）、ストップウォッチ、別のタイマーを試す間も
進行中のタイマーを取っておけるスタッシュ、そして再生中のメディアを
一時停止もできる終了アラート。カウントダウンが終わると一度だけ音が鳴り、
リセットするまで数字が点滅し続けます。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/timer.png" width="420" alt="Hop — タイマーとサイクル">
</div>

### タイムトラッカーとやること

フラットなタスク一覧で時間を記録。各行に今日の時間と累計が表示され、
今日の値は手で直せます。長く回りすぎたら、8時間でバナーが知らせます。
隣には独立したやることリストがあり、完了したものは下へ沈みます。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/tracker.png" width="420" alt="Hop — タイムトラッカーとやること">
</div>

### スリープ防止

Mac を 15 分、8 時間、あるいはずっと起こしておく——ワンクリック、
パスワード不要。ディスプレイを点けたままにも、蓋を閉じたまま作業を
続けることもできます（ダウンロード、長いビルド、外部ディスプレイに
便利）。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/awake.png" width="420" alt="Hop — スリープ防止">
</div>

### システムモニター

CPU と GPU の負荷・温度、メモリとスワップ、ネットワーク、ディスク、
バッテリーの状態と消費電力——スパークラインチャート付きのライブ値、
自分で決める色のしきい値、°C/°F 切り替え、稼働時間の表示。値は
macOS から直接取得し、タブを開いている間だけ更新されます。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/system.png" width="420" alt="Hop — システムモニター">
</div>

### クリップボード履歴

コピーした直近 100 件（最大 300 件）を、テキストも画像もファイルも保持。
ワンクリックでコピーし直すことも、直前のアプリへそのままペーストする
ことも。コピーしたファイルは名前で覚え（複数なら「名前 +N」）、
ペーストするとファイルそのものが戻ります。パスワードなどの秘匿入力は
一切保存されません。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/clipboard.png" width="420" alt="Hop — クリップボード履歴">
</div>

### ファイル変換

画像・PDF・動画・音声をまとめてパネルへドロップ。JPEG、PNG、HEIC、
AVIF、WebP へ出力、PDF 圧縮、HEVC による動画の軽量化——変換前に
リアルタイムで正直なサイズ見積もりを表示します。処理はすべて
ローカルで完結。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/converter.png" width="480" alt="Hop — ファイル変換">
</div>

### ウィンドウ管理

ゾーングリフをクリックするか ⌃⌥ ホットキーを押すだけで、ウィンドウを
2 分の 1、4 分の 1、3 分の 1、中央へスナップ——追加アプリは不要です。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/windows.png" width="420" alt="Hop — ウィンドウ管理">
</div>

### トレント

同じパネルに収まる軽量 BitTorrent クライアント。.torrent ファイルを
ドロップするか magnet リンクをペーストして、ダウンロードするファイルを
正確に選べます——開始前でも、ダウンロードの最中でも。一時停止、再開、
シードに対応し、レシオ 1.0 で自動停止するオプションも。モジュールは
デフォルトでオフになっており、有効化するとオープンソースのエンジンを
小さな別ダウンロード（約 26 MB、署名検証済み）として取得します。
エンジンはローカルポート経由でのみ Hop と通信します。Hop を .torrent
ファイルと magnet リンクのデフォルトアプリにすることもできます。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/torrents.png" width="420" alt="Hop トレント — メニューバーパネルの軽量 BitTorrent クライアント">
</div>

### ファイルアーカイブ

モジュールの行がウインドウを開き、ドロップはそのウインドウで行います。⌘V も使え、複数ファイルもまとめて
渡せます。追加したものはリストに並び、ボタンを押すまで待ちます。アーカイブは展開され、それ以外はまとめて
1 つのアーカイブになります。出力先は既定でデスクトップ、元の隣や好きなフォルダも選べます。対応形式は
zip・rar・7z・tar・tar.gz・tar.bz2・tar.xz・gz。rar と 7z は初回に約 6 MB の小さなヘルパーを署名検証
つきでダウンロードします。Hop は rar を展開しますが作成はしません（プロプライエタリな形式のため）。
設定の「アーカイブの既定を Hop に」が扱うのは、Apple 製アプリが担当していない rar だけで、
rar はサードパーティ製アプリから取り返せます。zip・7z・標準形式はアーカイブユーティリティのまま。モジュールが
隠れていても働き、カードは実際の状態を表示します。 Finder でアーカイブをダブルクリックすると、そのファイルのすぐ隣に展開され、専用の小さな進捗ウインドウが出ます。失敗しても隠しものは残りません。Hop が開くファイルには形式を記した独自のアイコンが付くので、フォルダを一目で見分けられます。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/archives.png" width="480" alt="Hop — ファイルアーカイブ">
</div>

### 書類

コンバータが書類に対応しました。markdown → PDF は Hop 自身が組版し、Word ファイル
（.docx、.doc、.rtf）→ PDF または markdown、PDF の本文を markdown として抽出
できます。スキャンされたページは Apple の Vision が読み取ります。すべてネイティブ
かつオフラインで、オフィススイートの同梱も追加ダウンロードもありません。

### カラーピッカー

システムのルーペで画面のどんな色も拾えます。拾った色はリストに残り、各行の hex・rgb・hsl がそれぞれ
列に並び、押したものがコピーされます。並び順はカーソルの下で変わらず、何色まで残すか・何行見せるかは
設定でき、画面収録の許可も不要です。ルーペが返すのは色ひとつだけだからです。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/colors.png" width="420" alt="Hop — カラーピッカー">
</div>

### 文字認識

画面の範囲を囲むか、ウインドウに画像をドラッグするか ⌘V で貼り付けてください。中の文字と QR コードは
読んで直してコピーできるウインドウに出て、同時にクリップボード履歴にも入ります。改行は保たれるので
表も読める形で残ります。認識は Apple の Vision で、すべてこの Mac 内で完結します。

認識結果にウェブアドレスが含まれていると「リンクを開く」ボタンが出ます。請求書の QR コードのリン
クが、スマホを取り出さずにブラウザで開きます。対象はウェブアドレスだけです。読み取ったコードは外
部からの入力なので、電話番号や Wi-Fi のパスワード、連絡先カードはそのまま文字として残ります。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/recognition.png" width="480" alt="Hop — 文字認識">
</div>

### キーボードロック

1・5・15 分、または ∞ を押すとキーボード全体が反応しなくなり、Mac を切ったりふたを閉じたりせずに
拭けます。全画面のカバーが状況を説明し、メニューバーのアイコンはキーボードに変わります。解除は 4 通り
— カバーのボタン、パネルのボタン、パネルを開くこと、esc + shift の 5 秒長押し。電源キーの短押しも飲み込まれ
ますが、長押しは今も Mac を強制的に切ります。ハードウェアが処理しているからです。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/keyboard.png" width="480" alt="Hop — キーボードロック">
</div>

### そのほか

アイコンに表示される小さなステータスインジケータ——時間、スリープ防止、
警告、トレントの動き、カラーまたはモノクロ——、内蔵スピードテスト
（Apple の networkQuality）、フィルムグレインの質感を持つダーク／
ライトテーマ、グローバルホットキー、ログイン時に起動、クラッシュループ
からアプリを復旧させるセーフモード。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/system.png" width="280" alt="Hop システムモニター — CPU、GPU、メモリ、ネットワーク、ディスク、バッテリーのチャート">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/converter.png" width="280" alt="Hop ファイル変換 — 画像、PDF、動画、音声の一括変換">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/settings.png" width="280" alt="Hop 設定 — テーマ、モジュール、ホットキー、22言語">
</div>

## 22 言語

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — アプリは最初からシステム言語に自動で従います。

## プロジェクトを応援する

Hop は無料で、これからも無料です。メニューバーの一席に値すると思えたら、任意の支援が
新しい機能を出し、既存のものを磨く助けになります。買っているのは時間だけです。

**[→ Hop を支援する](https://web.tribute.tg/d/Nvk)**

## プライバシー — 許可を与えても安全な理由

**Hop は何も集めません。いまも、これからも。** 自前のサーバーも、解析も、テレメトリも、
アカウントも、クラッシュレポートもありません。下の許可はどれも、それを必要とする機能を実際に
使うときにだけ macOS が尋ね、まさにその機能のためだけに存在します。ついでに何かを集める
ことはありません。信じてもらう必要もありません。アプリはオープンソースで、集めるための
コードはそもそも存在しないからです。このリポジトリでトラッキング SDK や解析の呼び出しを
探してみてください。見つかりません。

すべてローカルで動作します。サーバーなし、アナリティクスなし、
アカウントなし。アプリがネットワークに触れるのはアップデートの確認時、
内蔵スピードテストを実行した時、そして——トレントモジュールを有効に
した場合——エンジンを一度取得する時とトレント通信そのものの時だけ。
アップデートの確認で送るのは使用中のバージョンだけで、あなたや Mac を
識別するものは含まれません。アップデートとトレントエンジンは署名付き
アーカイブで配信され、インストール前に Ed25519 署名で検証されます。

## 許可

Hop が許可を求めるのは、それを必要とする機能を実際に使うときだけです。アプリの
情報ウインドウに、すべての許可と現在の状態が並んでいます。

- **ネットワーク — antonshakirov.com** — アップデートの確認とダウンロード、そして
  任意の補助ツール 2 つ（トレントエンジンと 7-Zip アーカイバ）
- **ネットワーク — トレント、速度テスト** — トレントモジュール有効時のほかの参加者
  との通信。速度テストは macOS の networkQuality で Apple のサーバーに対して行います
- **アクセシビリティ** — 下のアプリへの貼り付け、ウインドウマネージャ、キーボード
  ロック
- **画面収録** — 文字認識モジュールのみ、しかも範囲を囲むときだけ。カラーピッカーには不要です
- **通知** — タイマー終了のお知らせと、トレント完了の通知
- **管理者パスワード** — 一度だけ、蓋を閉じたままのモードのため（pmset は root 専用）
- **ログイン時に開く** — 自分でオンにするまでは無効

起動時には何も要求せず、あなたが有効にしていないモジュールのために何かを求めることもありません。
解析も、テレメトリも、アカウントも、クラッシュレポートもありません。antonshakirov.com へは、
新しいバージョンがあるかを尋ねるためだけに接続し、あなたが同意したときにそれ、または任意の 2 つの
ヘルパーのどちらかをダウンロードします。ほかはすべてこの Mac の中に残ります。クリップボード履歴、
記録した時間、やることリスト、認識した文字、拾った色。

上の許可はどれも、機能が動くためだけのものです。信じてもらう必要はありません。Hop はオープンソースで、
集めるためのコードはそもそも存在しません。このリポジトリで読めます。アプリの情報ウインドウには
「アプリの許可」タブがあり、同じ一覧と、それぞれの現在の状態が並んでいます。

ウェブサイト: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## 無料である理由

Hop は完全に無料です。試用期間も、Pro 版も、アプリ内課金もありません。広告もデータ収集もアカウントもなく、収益化するものも売るものもありません。これは個人プロジェクトです。自分のために Hop を作り、毎日使っていて、ただ共有しているだけです。役に立ったら、誰かに教えてあげてください。そして、もし力を貸したくなったら、いまは Hop を応援する方法もあります——ただの贈り物で、見返りは何もありません。

## ソースからのビルド

Swift Package Manager、macOS 14+、外部依存なし:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

開発ワークフロー、リリースパイプライン、動作仕様は
[docs/development.md](../development.md) と [docs/spec.md](../spec.md) に
あります。

## プロジェクトを応援する

方法は三つ、どれも歓迎です。

- **[支援して Hop を助ける](https://web.tribute.tg/d/Nvk)** — そのまま新機能と修正に
  なります。任意で、特典はなく、有料の機能もありません。どのモジュールも全員に同じです。
- **[リポジトリにスターを付ける](https://github.com/antonyshakirov/hop/stargazers)** —
  ほかの人はスターから見つけます。
- **[Issue を立てる](https://github.com/antonyshakirov/hop/issues)** — 不具合の報告や
  アイデアも、同じくらい価値があります。

## 作者とライセンス

作者: [Anton Shakirov](https://www.antonshakirov.com/en)。
[MIT ライセンス](../../LICENSE)で公開しています。自由に使用・改変できます
が、著作権表示は残してください——このアプリを自作と偽ることはライセンス
違反です。
