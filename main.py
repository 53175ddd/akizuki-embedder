"""秋月電子通商の商品リンクを embed で展開する Discord Bot。

トークンは環境変数 DISCORD_TOKEN から読む。setup.sh で導入した場合は、
systemd が /etc/akizuki-embedder.env の内容を環境変数として渡す。

手動で動かす場合:
    DISCORD_TOKEN=xxxxx python3 main.py

Developer Portal で Bot の「MESSAGE CONTENT INTENT」を有効にしておくこと。
"""

import os
import re
import time

import aiohttp
import discord
from bs4 import BeautifulSoup

BASE_URL = "https://akizukidenshi.com"
# 例: https://akizukidenshi.com/catalog/g/g108001/ （スキーム・www の有無は問わない）
PRODUCT_URL_RE = re.compile(
    r"(?:https?://)?(?:www\.)?akizukidenshi\.com/catalog/g/g(\d+)", re.IGNORECASE
)
MAX_LINKS_PER_MESSAGE = 5
CACHE_TTL = 600  # 秒
EMBED_COLOR = 0x1E6EB4
USER_AGENT = "Mozilla/5.0 (compatible; AkizukiLinkBot/1.0)"

_cache: dict[str, tuple[float, dict | None]] = {}


def _text(el) -> str:
    return el.get_text(" ", strip=True) if el else ""


def _truncate(s: str, n: int) -> str:
    return s if len(s) <= n else s[: n - 1] + "…"


def parse_product(html: str, url: str) -> dict | None:
    soup = BeautifulSoup(html, "html.parser")
    name_el = soup.select_one("#hidden_goods_name")
    name = name_el["value"] if name_el else _text(soup.select_one("h1.h1-goods-name"))
    if not name:
        return None  # 商品ページではない（削除済み・エラーなど）

    img = soup.select_one("img.block-src-l--image")
    image = None
    if img:
        src = img.get("data-src") or img.get("src")
        if src and "lazyloading" not in src:
            image = BASE_URL + src if src.startswith("/") else src

    # 概要は <br> を改行として扱う
    overview_el = soup.select_one(".block-goods-overview")
    overview = ""
    if overview_el:
        for br in overview_el.find_all("br"):
            br.replace_with("\n")
        overview = "\n".join(
            line.strip() for line in overview_el.get_text().splitlines() if line.strip()
        )

    stock_el = soup.select_one("[class*='block-goods-detail--stock-info']")
    price_el = soup.select_one(".block-goods-price--price")
    tax_el = price_el.select_one(".tax") if price_el else None
    if tax_el:
        tax_el.extract()

    return {
        "url": url,
        "name": name,
        "code": _text(soup.select_one("#spec_goods")),
        "model": _text(soup.select_one("#spec_number")),
        "maker": _text(soup.select_one(".block-goods-detail-maker dd")),
        "release": _text(soup.select_one("#spec_release_dt")),
        "qty": _text(soup.select_one("#spec_goods_sales_qty")),
        "price": _text(price_el),
        "net_price": _text(soup.select_one(".block-goods-price--net-price")),
        "stock": _text(stock_el),
        "overview": overview,
        "image": image,
    }


async def fetch_product(session: aiohttp.ClientSession, code: str) -> dict | None:
    url = f"{BASE_URL}/catalog/g/g{code}/"
    cached = _cache.get(url)
    if cached and time.monotonic() - cached[0] < CACHE_TTL:
        return cached[1]

    async with session.get(url) as resp:
        if resp.status != 200:
            return None
        html = await resp.text()
    product = parse_product(html, url)
    _cache[url] = (time.monotonic(), product)
    return product


def build_embed(p: dict) -> discord.Embed:
    embed = discord.Embed(
        title=_truncate(p["name"], 256),
        url=p["url"],
        color=EMBED_COLOR,
    )
    if p["price"]:
        price = f"{p['price']}（税込）"
        if p["qty"]:
            price = f"{p['qty']} {price}"
        embed.add_field(name="価格", value=price, inline=True)
    for label, key in (
        ("在庫", "stock"),
        ("型番", "model"),
    ):
        if p[key]:
            embed.add_field(name=label, value=_truncate(p[key], 1024), inline=True)
    if p["image"]:
        embed.set_image(url=p["image"])
    embed.set_footer(text="秋月電子通商")
    return embed


class AkizukiBot(discord.Client):
    def __init__(self) -> None:
        intents = discord.Intents.default()
        intents.message_content = True
        super().__init__(intents=intents)
        self.http_session: aiohttp.ClientSession | None = None

    async def setup_hook(self) -> None:
        self.http_session = aiohttp.ClientSession(
            headers={"User-Agent": USER_AGENT},
            timeout=aiohttp.ClientTimeout(total=15),
        )

    async def close(self) -> None:
        if self.http_session:
            await self.http_session.close()
        await super().close()

    async def on_ready(self) -> None:
        print(f"ログインしました: {self.user} (id={self.user.id})")

    async def on_message(self, message: discord.Message) -> None:
        if message.author.bot:
            return

        codes = list(dict.fromkeys(PRODUCT_URL_RE.findall(message.content)))
        if not codes:
            return

        embeds = []
        async with message.channel.typing():
            for code in codes[:MAX_LINKS_PER_MESSAGE]:
                try:
                    product = await fetch_product(self.http_session, code)
                except Exception as e:  # ネットワークエラーなどは無視して次へ
                    print(f"取得失敗 g{code}: {e!r}")
                    continue
                if product:
                    embeds.append(build_embed(product))

        if embeds:
            await message.channel.send(embeds=embeds)


def main() -> None:
    token = os.environ.get("DISCORD_TOKEN")
    if not token:
        raise SystemExit("環境変数 DISCORD_TOKEN を設定してください")
    AkizukiBot().run(token)


if __name__ == "__main__":
    main()
