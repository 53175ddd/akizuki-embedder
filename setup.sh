#!/usr/bin/env bash
# akizuki-embedder のセットアップスクリプト（Ubuntu 用）
#
# 使い方: sudo ./setup.sh
#
# 何度実行してもかまいません。2 回目以降は main.py とパッケージを更新し、
# 保存済みのトークンを使い続けるか入れ直すかを選べます。

set -euo pipefail

APP_NAME="akizuki-embedder"
APP_USER="akizuki-embedder"
INSTALL_DIR="/opt/${APP_NAME}"
ENV_FILE="/etc/${APP_NAME}.env"
UNIT_FILE="/etc/systemd/system/${APP_NAME}.service"
# チャンネルを見る + メッセージを送信 + 埋め込みリンク + スレッドでメッセージを送信
PERMISSIONS=274877926400
DISCORD_API="https://discord.com/api/v10"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_STEPS=7
STEP=0
LAST_STATUS=""

# ---------- 表示用 ----------

if [ -t 1 ]; then
  BOLD=$'\e[1m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; CYAN=$'\e[36m'; RESET=$'\e[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; RESET=""
fi

step() {
  STEP=$((STEP + 1))
  echo
  echo "${BOLD}${CYAN}==== [${STEP}/${TOTAL_STEPS}] $1 ====${RESET}"
}
info() { echo "  $*"; }
ok()   { echo "  ${GREEN}✔ $*${RESET}"; }
warn() { echo "  ${YELLOW}! $*${RESET}"; }
die()  { echo "  ${RED}✘ $*${RESET}" >&2; exit 1; }

# 「続行しますか？」と聞き、n なら終了する
confirm_or_exit() {
  local ans
  read -r -p "  続行しますか？ [Y/n] " ans
  case "${ans}" in
    [nN]*) echo "  中断しました。"; exit 0 ;;
  esac
}

# y/n を聞いて結果を返す（既定値は第 2 引数: Y または N）
ask_yn() {
  local prompt="$1" default="$2" ans
  if [ "${default}" = "Y" ]; then
    read -r -p "  ${prompt} [Y/n] " ans
    [[ ! "${ans}" =~ ^[nN] ]]
  else
    read -r -p "  ${prompt} [y/N] " ans
    [[ "${ans}" =~ ^[yY] ]]
  fi
}

pause() {
  read -r -p "  準備ができたら Enter を押してください… " _
}

# ---------- Discord API ----------

# トークンでアプリケーション情報を取得する。
# 成功すると APP_ID / APP_NAME_DISCORD / APP_FLAGS を設定して 0 を返す。
# トークンがコマンドライン引数に現れないよう、ヘッダーは標準入力から渡す。
fetch_application() {
  local token="$1" body status
  body="$(mktemp)"
  status="$(printf 'Authorization: Bot %s\n' "${token}" \
    | curl -sS -o "${body}" -w '%{http_code}' -H @- "${DISCORD_API}/applications/@me" || true)"
  if [ "${status}" != "200" ]; then
    rm -f "${body}"
    LAST_STATUS="${status}"
    return 1
  fi
  {
    read -r APP_ID
    read -r APP_NAME_DISCORD
    read -r APP_FLAGS
  } < <(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d["id"]); print(d.get("name", "")); print(d.get("flags", 0))
' "${body}")
  rm -f "${body}"
}

# MESSAGE CONTENT INTENT（GATEWAY_MESSAGE_CONTENT または _LIMITED）が有効か
has_message_content_intent() {
  (( (APP_FLAGS & (1 << 18 | 1 << 19)) != 0 ))
}

# ======================================================================

echo "${BOLD}秋月電子 商品リンク展開 Bot（${APP_NAME}）のセットアップ${RESET}"
echo "  各ステップの内容を表示してから実行します。途中で n を入力すると中断できます。"

# ---------- 1. 事前確認 ----------
step "実行環境の確認"
[ "$(id -u)" -eq 0 ] || die "root 権限が必要です。sudo ./setup.sh で実行してください。"
command -v apt-get >/dev/null || die "apt-get が見つかりません。このスクリプトは Ubuntu 向けです。"
command -v systemctl >/dev/null || die "systemctl が見つかりません。systemd が動いている環境で実行してください。"
[ -f "${SCRIPT_DIR}/main.py" ] || die "${SCRIPT_DIR}/main.py が見つかりません。リポジトリ内の setup.sh を実行してください。"
[ -f "${SCRIPT_DIR}/requirements.txt" ] || die "${SCRIPT_DIR}/requirements.txt が見つかりません。"
if [ -r /etc/os-release ]; then
  ok "OS: $(. /etc/os-release && echo "${PRETTY_NAME}")"
fi
if systemctl list-unit-files "${APP_NAME}.service" --no-legend 2>/dev/null | grep -q "${APP_NAME}"; then
  warn "すでにインストールされています。main.py とパッケージを更新し、Bot を再起動します。"
fi
info "インストール先: ${INSTALL_DIR}"
info "トークンの保存先: ${ENV_FILE}"
info "サービス名: ${APP_NAME}"
confirm_or_exit

# ---------- 2. Discord 側の準備 ----------
step "Discord Developer Portal での準備"
info "ブラウザで次のページを開き、Bot を用意してください。"
info "  https://discord.com/developers/applications"
echo
info "1. New Application を押してアプリケーションを作る（作成済みなら不要）"
info "2. 左メニューの Bot を開き、Reset Token でトークンを発行して控える"
info "   ※ トークンは一度しか表示されません。他人に知られないようにしてください。"
info "3. 同じ画面の Privileged Gateway Intents で"
info "   ${BOLD}MESSAGE CONTENT INTENT${RESET} をオンにして Save Changes を押す"
echo
info "サーバーへの招待 URL は、ステップ 5 でトークンを確認したあとに表示します。"
pause

# ---------- 3. パッケージ ----------
step "必要なパッケージのインストール"
info "apt で python3 / python3-venv / curl / ca-certificates をインストールします。"
confirm_or_exit
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3 python3-venv curl ca-certificates
python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
  || die "Python 3.10 以上が必要です（現在: $(python3 --version)）。"
ok "$(python3 --version) を使います。"

# ---------- 4. ユーザーとファイル ----------
step "Bot 用ユーザーの作成とプログラムの配置"
info "ログインできない専用ユーザー ${APP_USER} を作り、"
info "main.py を ${INSTALL_DIR} に置いて Python の仮想環境（venv）を作ります。"
confirm_or_exit
if id "${APP_USER}" >/dev/null 2>&1; then
  ok "ユーザー ${APP_USER} は作成済みです。"
else
  useradd --system --home-dir "${INSTALL_DIR}" --no-create-home --shell /usr/sbin/nologin "${APP_USER}"
  ok "ユーザー ${APP_USER} を作成しました。"
fi
# プログラムは root の所有にして、Bot 自身からは書き換えられないようにする
install -d -m 755 "${INSTALL_DIR}"
install -m 644 "${SCRIPT_DIR}/main.py" "${SCRIPT_DIR}/requirements.txt" "${INSTALL_DIR}/"
ok "main.py を配置しました。"
if [ ! -x "${INSTALL_DIR}/venv/bin/python" ]; then
  python3 -m venv "${INSTALL_DIR}/venv"
  ok "venv を作成しました。"
fi
info "パッケージをインストールしています…"
"${INSTALL_DIR}/venv/bin/pip" install -q --disable-pip-version-check --no-cache-dir -U -r "${INSTALL_DIR}/requirements.txt"
ok "discord.py / beautifulsoup4 をインストールしました。"

# ---------- 5. トークン ----------
step "Bot トークンの設定"
TOKEN=""
if [ -f "${ENV_FILE}" ] && grep -q '^DISCORD_TOKEN=.' "${ENV_FILE}"; then
  info "保存済みのトークンがあります（${ENV_FILE}）。"
  if ask_yn "保存済みのトークンをそのまま使いますか？" Y; then
    TOKEN="$(sed -n 's/^DISCORD_TOKEN=//p' "${ENV_FILE}" | head -n 1)"
  fi
fi

while :; do
  if [ -z "${TOKEN}" ]; then
    info "ステップ 2 で控えたトークンを貼り付けて Enter を押してください（入力内容は表示されません）。"
    read -r -s -p "  トークン: " TOKEN
    echo
    TOKEN="${TOKEN#Bot }"
    TOKEN="$(printf '%s' "${TOKEN}" | tr -d '[:space:]')"
    if [ -z "${TOKEN}" ]; then
      warn "トークンが空です。"
      continue
    fi
  fi

  info "Discord にトークンを確認しています…"
  if fetch_application "${TOKEN}"; then
    ok "トークンは有効です（アプリケーション名: ${APP_NAME_DISCORD}）。"
    break
  fi
  if [ "${LAST_STATUS}" = "401" ]; then
    warn "トークンが正しくありません（HTTP 401）。もう一度入力してください。"
    TOKEN=""
  else
    warn "Discord に接続できませんでした（HTTP ${LAST_STATUS:-なし}）。ネットワークを確認してください。"
    if ask_yn "確認せずにこのトークンを保存しますか？" N; then
      APP_ID=""
      APP_FLAGS=-1
      break
    fi
    TOKEN=""
  fi
done

if [ "${APP_FLAGS}" != "-1" ]; then
  while ! has_message_content_intent; do
    warn "MESSAGE CONTENT INTENT がオフになっています。オフのままだと Bot はリンクに反応しません。"
    info "Developer Portal の Bot 画面でオンにして Save Changes を押してください。"
    pause
    fetch_application "${TOKEN}" || { warn "再確認できませんでした。先に進みます。"; break; }
  done
  has_message_content_intent 2>/dev/null && ok "MESSAGE CONTENT INTENT はオンです。"
fi

# root だけが読めるファイルに保存する。systemd がこれを環境変数として main.py に渡す
( umask 077; printf 'DISCORD_TOKEN=%s\n' "${TOKEN}" > "${ENV_FILE}" )
chown root:root "${ENV_FILE}"
chmod 600 "${ENV_FILE}"
ok "トークンを ${ENV_FILE} に保存しました（root のみ読み取り可）。"

if [ -n "${APP_ID:-}" ]; then
  echo
  info "${BOLD}次の URL をブラウザで開き、Bot をサーバーに招待してください。${RESET}"
  info "（招待済みなら不要です。必要な権限はあらかじめ選択されています）"
  echo
  echo "  https://discord.com/oauth2/authorize?client_id=${APP_ID}&scope=bot&permissions=${PERMISSIONS}"
  echo
  pause
fi

# ---------- 6. systemd ----------
step "サービスの登録と起動"
info "systemd に ${APP_NAME} サービスを登録します。"
info "マシンの起動時に自動で Bot が起動し、異常終了したときは 10 秒後に再起動します。"
confirm_or_exit
cat > "${UNIT_FILE}" <<EOF
[Unit]
Description=Akizuki link embed Discord bot
After=network-online.target
Wants=network-online.target

[Service]
User=${APP_USER}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${ENV_FILE}
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/main.py
Restart=always
RestartSec=10
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
systemctl enable "${APP_NAME}" >/dev/null 2>&1
systemctl restart "${APP_NAME}"
ok "サービスを登録して起動しました。"

# ---------- 7. 起動確認 ----------
step "起動の確認"
info "Bot が Discord にログインするのを待っています（最大 30 秒）…"
RESULT="timeout"
for _ in $(seq 1 30); do
  LOG="$(journalctl -u "${APP_NAME}" --since "${START_TIME}" -o cat --no-pager 2>/dev/null || true)"
  if grep -q 'ログインしました' <<<"${LOG}"; then
    RESULT="ok"; break
  elif grep -qE 'PrivilegedIntentsRequired|LoginFailure|Improper token|Traceback' <<<"${LOG}"; then
    RESULT="error"; break
  fi
  sleep 1
done

case "${RESULT}" in
  ok)
    ok "$(grep 'ログインしました' <<<"${LOG}" | tail -n 1)"
    echo
    echo "${BOLD}${GREEN}セットアップが完了しました。${RESET}"
    info "Bot のいるチャンネルに秋月電子の商品リンクを投稿して、embed が出ることを確認してください。"
    info "  例: https://akizukidenshi.com/catalog/g/g108001/"
    ;;
  error)
    warn "起動中にエラーが発生しました。ログの末尾:"
    tail -n 15 <<<"${LOG}" | sed 's/^/    /'
    echo
    info "トークンを入れ直すときは、もう一度 sudo ./setup.sh を実行してください。"
    exit 1
    ;;
  *)
    warn "30 秒以内にログインを確認できませんでした。次のコマンドでログを確認してください。"
    info "  journalctl -u ${APP_NAME} -f"
    exit 1
    ;;
esac

echo
info "よく使うコマンド:"
info "  状態を見る   sudo systemctl status ${APP_NAME}"
info "  ログを見る   journalctl -u ${APP_NAME} -f"
info "  再起動する   sudo systemctl restart ${APP_NAME}"
info "  止める       sudo systemctl stop ${APP_NAME}"
