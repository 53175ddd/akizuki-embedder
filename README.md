# akizuki-embedder

Discord に投稿されたメッセージに秋月電子通商の商品ページのリンク（`akizukidenshi.com/catalog/g/g<番号>`）が含まれていると、商品情報を embed で投稿する Bot です。

- embed の内容: 商品名（商品ページへのリンク付き）、価格（税込）、在庫状況、型番、商品画像
- 1 メッセージにつき最大 5 件まで。同じリンクは 1 回だけ扱います。
- 取得した商品情報は 10 分間キャッシュします。
- 存在しない商品番号のリンクや取得エラーは無視します（何も投稿しません）。

## ファイル構成

| ファイル | 内容 |
|---|---|
| `main.py` | Bot 本体 |
| `setup.sh` | Ubuntu 用のセットアップスクリプト |
| `requirements.txt` | 必要な Python パッケージ（discord.py、beautifulsoup4） |

## 動作環境

- Ubuntu 22.04 以降（Python 3.10 以上、systemd）
- インターネット接続（Discord と akizukidenshi.com への HTTPS 通信）
- CPU やメモリはほとんど使いません。N150 程度の小型 PC で十分です。

---

## セットアップ

まっさらな Ubuntu マシンに導入する前提の手順です。`setup.sh` が手順を 1 ステップずつ案内するので、表示に従って進めてください。

### 1. Discord のアカウントとサーバーを用意する

Bot を追加するサーバーで「サーバー管理」の権限を持っている Discord アカウントが必要です。Bot の作成そのものは `setup.sh` の中で案内します。

### 2. リポジトリを Ubuntu マシンに置く

Git でクローンする場合:

```bash
sudo apt update && sudo apt install -y git
```

```bash
git clone <このリポジトリの URL> akizuki-embedder
```

ほかの PC からコピーする場合は、`main.py`、`setup.sh`、`requirements.txt` の 3 つを同じディレクトリに置いてください。Windows の PC から送る場合は、PowerShell で次のように実行します（`user@ubuntu-host` は Ubuntu マシンの「ユーザー名@ホスト名（または IP アドレス）」に置き換えます）。

```bash
scp -r akizuki-embedder user@ubuntu-host:~/
```

> Ubuntu 側で SSH を受け付けていない場合は、先に Ubuntu で `sudo apt install -y openssh-server` を実行してください。USB メモリなどでコピーしてもかまいません。

### 3. setup.sh を実行する

```bash
cd akizuki-embedder && sudo bash setup.sh
```

`setup.sh` は次の 7 ステップで進みます。システムを変更するステップでは、実行前に内容を表示して確認を求めます（`n` で中断できます）。

| ステップ | 内容 |
|---|---|
| 1. 実行環境の確認 | root で実行しているか、Ubuntu（apt と systemd）か、必要なファイルがそろっているかを確認します。 |
| 2. Discord Developer Portal での準備 | Bot の作成、トークンの発行、**MESSAGE CONTENT INTENT** の有効化を案内します。 |
| 3. 必要なパッケージのインストール | apt で `python3`、`python3-venv`、`curl`、`ca-certificates` を入れます。 |
| 4. Bot 用ユーザーの作成とプログラムの配置 | ログインできない専用ユーザー `akizuki-embedder` を作り、`/opt/akizuki-embedder` に `main.py` と Python の仮想環境（venv）を用意します。 |
| 5. Bot トークンの設定 | トークンを入力します（画面には表示されません）。Discord に問い合わせてトークンが有効か、MESSAGE CONTENT INTENT がオンかを確認したうえで、`/etc/akizuki-embedder.env` に保存します。最後に、必要な権限を選択済みの**招待 URL** を表示します。 |
| 6. サービスの登録と起動 | systemd に `akizuki-embedder` サービスを登録して起動します。 |
| 7. 起動の確認 | Bot が Discord にログインしたことをログで確認します。 |

ステップ 5 で表示された招待 URL をブラウザで開き、Bot をサーバーに招待してください。招待 URL には次の権限が選択されています。

- チャンネルを見る
- メッセージを送信
- 埋め込みリンク
- スレッドでメッセージを送信

### 4. 動作を確認する

Bot がいるチャンネルに商品ページのリンク（例: `https://akizukidenshi.com/catalog/g/g108001/`）を投稿し、embed が投稿されることを確認してください。

> **注意**: 同じトークンの Bot をほかの PC でも動かしていると、リンク 1 つに embed が 2 回投稿されます。セットアップの前に、ほかの環境の Bot を止めてください。

---

## トークンの扱い

トークンは `/etc/akizuki-embedder.env` に `DISCORD_TOKEN=...` の形で保存されます。このファイルは root だけが読めます（パーミッション 600）。systemd がサービスの起動時にこのファイルを読み、環境変数 `DISCORD_TOKEN` として `main.py` に渡します。

トークンを変更するときは、`sudo bash setup.sh` を実行し直して、「保存済みのトークンをそのまま使いますか？」で `n` を選んでください。

## 運用

| 操作 | コマンド |
|---|---|
| 状態を見る | `sudo systemctl status akizuki-embedder` |
| ログを見る | `journalctl -u akizuki-embedder -f` |
| 止める | `sudo systemctl stop akizuki-embedder` |
| 再起動する | `sudo systemctl restart akizuki-embedder` |
| 自動起動をやめる | `sudo systemctl disable --now akizuki-embedder` |

### 更新する

リポジトリを最新にしてから `setup.sh` を実行し直します。`main.py` の入れ替え、パッケージの更新、再起動が行われます。保存済みのトークンはそのまま使えます。

```bash
git pull && sudo bash setup.sh
```

### アンインストールする

```bash
sudo systemctl disable --now akizuki-embedder
```

```bash
sudo rm -rf /etc/systemd/system/akizuki-embedder.service /etc/akizuki-embedder.env /opt/akizuki-embedder && sudo systemctl daemon-reload
```

```bash
sudo userdel akizuki-embedder
```

## 手動で動かす（開発用）

systemd を使わずに試すときは、venv を作って直接起動します。

```bash
python3 -m venv venv && venv/bin/pip install -r requirements.txt
```

```bash
DISCORD_TOKEN=ここにトークン venv/bin/python main.py
```

## うまく動かないとき

| 症状 | 確認すること |
|---|---|
| ステップ 5 で「トークンが正しくありません」と出る | トークンをコピーし直すか、Developer Portal の Reset Token で再発行してください。 |
| `PrivilegedIntentsRequired` | Developer Portal の Bot 画面で MESSAGE CONTENT INTENT がオンになっていません。 |
| ログインはするがリンクに反応しない | Bot にそのチャンネルの「チャンネルを見る」「メッセージを送信」の権限があるか確認してください。 |
| メッセージは届くが embed が表示されない | 「埋め込みリンク」の権限があるか確認してください。 |
| 特定の商品だけ表示されない | 通信エラーの場合は、ログに `取得失敗 g<番号>` と出ます。ログに何も出ない場合は、商品ページが存在しないか、秋月のサイトのデザインが変わって情報を取り出せなくなっている可能性があります。 |
