<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Hop アプリアイコン — 4本線のアスタリスク">

# Hop

**macOS のメニューバーに住む小さな相棒。タイマー、スリープ防止、
システムモニター、クリップボード履歴、ファイル変換、ウィンドウ管理、
そして軽量トレントクライアント。ワンクリックで、必要なものが
すべてそこに。**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Tiếng Việt](README.vi.md) · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · **日本語**

<img src="https://www.antonshakirov.com/products/hop/screens/ja/panel.png" width="420" alt="Hop パネル — ドットマトリクス表示のメニューバータイマー、プリセットとワーク・レストサイクル">

</div>

Hop は Mac のメニューバーに常駐し、こまごました半ダースのユーティリティを
まとめて置き換えます。ポモドーロ式タイマー、caffeinate 風のスリープ
ブロッカー、システムモニター、クリップボードマネージャー、ドラッグ＆
ドロップのファイル変換、ウィンドウスナップ、そして軽量トレント
クライアント——7 本のアプリの代わりに、軽量なネイティブアプリが 1 本。

## ダウンロード

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — 開いて `Hop.app` をアプリケーションフォルダへドラッグ（推奨）
- `Hop-x.y.z.zip` — 同じアプリの素のアーカイブ（内蔵アップデーターが使用）。[最新リリース](https://github.com/antonyshakirov/hop/releases/latest)を参照
- 高速ミラー: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

初回起動時は `Hop.app` を右クリック → **開く** → 確認
（アプリはまだ公証されていません）。macOS 14 以降が必要です。

## 機能

### タイマーとサイクル

ワンジェスチャーで設定できるドットマトリクスのカウントダウン。数字を
ドラッグする、電子レンジのように時間を打ち込む、プリセットを選ぶ——
どれでも。ワーク・レストサイクル（25/5 のポモドーロ、52/17、90/15、
もちろん自分好みにも）、ストップウォッチ、別のタイマーを試す間も
進行中のタイマーを取っておけるスタッシュ、そして再生中のメディアを
一時停止もできる終了アラート。

### スリープ防止

Mac を 15 分、8 時間、あるいはずっと起こしておく——ワンクリック、
パスワード不要。ディスプレイを点けたままにも、蓋を閉じたまま作業を
続けることもできます（ダウンロード、長いビルド、外部ディスプレイに
便利）。

### システムモニター

CPU と GPU の負荷・温度、メモリとスワップ、ネットワーク、ディスク、
バッテリーの状態と消費電力——スパークラインチャート付きのライブ値、
自分で決める色のしきい値、°C/°F 切り替え、稼働時間の表示。値は
macOS から直接取得し、タブを開いている間だけ更新されます。

### クリップボード履歴

コピーした直近 100 件（最大 300 件）を、テキストも画像も保持。ワンクリックでコピーし
直すことも、直前のアプリへそのままペーストすることも。パスワードなど
の秘匿入力は一切保存されません。

### ファイル変換

画像・PDF・動画・音声をまとめてパネルへドロップ。JPEG、PNG、HEIC、
AVIF、WebP へ出力、PDF 圧縮、HEVC による動画の軽量化——変換前に
リアルタイムで正直なサイズ見積もりを表示します。処理はすべて
ローカルで完結。

### ウィンドウ管理

ゾーングリフをクリックするか ⌃⌥ ホットキーを押すだけで、ウィンドウを
2 分の 1、4 分の 1、3 分の 1、中央へスナップ——追加アプリは不要です。

### トレント

同じパネルに収まる軽量 BitTorrent クライアント。.torrent ファイルを
ドロップするか magnet リンクをペーストして、ダウンロードするファイルを
正確に選べます——開始前でも、ダウンロードの最中でも。一時停止、再開、
シードに対応し、レシオ 1.0 で自動停止するオプションも。モジュールは
デフォルトでオフになっており、有効化するとオープンソースのエンジンを
小さな別ダウンロード（約 26 MB、署名検証済み）として取得します。
エンジンはローカルポート経由でのみ Hop と通信します。Hop を .torrent
ファイルと magnet リンクのデフォルトアプリにすることもできます。

### そのほか

内蔵スピードテスト（Apple の networkQuality）、フィルムグレインの
質感を持つダーク／ライトテーマ、グローバルホットキー、ログイン時に
起動、クラッシュループからアプリを復旧させるセーフモード。

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/system.png" width="280" alt="Hop システムモニター — CPU、GPU、メモリ、ネットワーク、ディスク、バッテリーのチャート">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/converter.png" width="280" alt="Hop ファイル変換 — 画像、PDF、動画、音声の一括変換">
<img src="https://www.antonshakirov.com/products/hop/screens/ja/settings.png" width="280" alt="Hop 設定 — テーマ、モジュール、ホットキー、18言語">
</div>

## 18 言語

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — アプリは最初からシステム言語に自動で従います。

## プライバシー

すべてローカルで動作します。サーバーなし、アナリティクスなし、
アカウントなし。アプリがネットワークに触れるのはアップデートの確認時、
内蔵スピードテストを実行した時、そして——トレントモジュールを有効に
した場合——エンジンを一度取得する時とトレント通信そのものの時だけ。
アップデートとトレントエンジンは署名付きアーカイブで配信され、
インストール前に Ed25519 署名で検証されます。

ウェブサイト: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## 無料である理由

Hop は完全に無料です。試用期間も、Pro 版も、アプリ内課金もありません。広告もデータ収集もアカウントもなく、収益化するものも売るものもありません。これは個人プロジェクトです。自分のために Hop を作り、毎日使っていて、ただ共有しているだけです。役に立ったら、誰かに教えてあげてください。

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

Hop がクリックを 1 つ 2 つ節約してくれたなら、**[リポジトリにスターを](https://github.com/antonyshakirov/hop/stargazers)**——
スターは、ほかの人がこのアプリを見つけるための道しるべです。バグ報告や
機能のアイデアは [Issues](https://github.com/antonyshakirov/hop/issues) へ
どうぞ。

## 作者とライセンス

作者: [Anton Shakirov](https://www.antonshakirov.com/en)。
[MIT ライセンス](../../LICENSE)で公開しています。自由に使用・改変できます
が、著作権表示は残してください——このアプリを自作と偽ることはライセンス
違反です。
