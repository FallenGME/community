#!/usr/bin/env python3
"""
Discord ↔ Discourse bridge bot.

Listens for Discord events and relays them to the Discourse plugin's incoming
HTTP endpoint. Also called (via DiscordBridge.post_to_discord_*) when Discourse
needs to post into Discord — that direction is handled by the Discourse Ruby
plugin using Discord's REST API / Incoming Webhook directly, so this bot only
needs to handle the Discord → Discourse direction.

Required Discord Gateway Intents (enable in Developer Portal):
  - GUILDS
  - GUILD_MESSAGES
  - GUILD_MESSAGE_THREADS
  - MESSAGE_CONTENT (Privileged Intent)

Required Bot Permissions:
  - Read Messages / View Channels
  - Send Messages
  - Read Message History
  - Create Public Threads (for Forum channels)

Setup:
  1. Copy .env.example to .env and fill in all values.
  2. pip install -r requirements.txt
  3. python3 bot.py

The bot signs every outgoing POST to Discourse with an HMAC-SHA256 signature
in the X-Bridge-Signature header so the Discourse plugin can authenticate it.
"""

import os
import json
import hmac
import hashlib
import logging
from typing import Optional

import aiohttp
import discord
from dotenv import load_dotenv

load_dotenv()

# ── Configuration ─────────────────────────────────────────────────────────────

DISCORD_BOT_TOKEN     = os.environ["DISCORD_BOT_TOKEN"]
DISCOURSE_URL         = os.environ["DISCOURSE_URL"].rstrip("/")
HMAC_SECRET           = os.environ["HMAC_SECRET"].encode()
GENERAL_CHANNEL_ID    = int(os.environ["GENERAL_CHANNEL_ID"])
SUPPORT_FORUM_ID      = int(os.environ["SUPPORT_FORUM_ID"])

DISCOURSE_INCOMING    = f"{DISCOURSE_URL}/community-integrations/discord/incoming"

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("discord-bridge")

# ── Discord client setup ──────────────────────────────────────────────────────

intents = discord.Intents.default()
intents.message_content = True     # Privileged intent — must be enabled in Developer Portal
intents.guild_messages   = True
intents.guilds           = True

client = discord.Client(intents=intents)

# ── HMAC signing ─────────────────────────────────────────────────────────────

def sign_body(body: bytes) -> str:
    """Return 'sha256=<hex>' HMAC-SHA256 signature over body."""
    digest = hmac.new(HMAC_SECRET, body, hashlib.sha256).hexdigest()
    return f"sha256={digest}"


# ── HTTP relay ────────────────────────────────────────────────────────────────

async def relay_to_discourse(session: aiohttp.ClientSession, payload: dict) -> None:
    """POST a signed JSON payload to the Discourse incoming endpoint."""
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    sig  = sign_body(body)

    headers = {
        "Content-Type": "application/json",
        "X-Bridge-Signature": sig,
    }

    try:
        async with session.post(DISCOURSE_INCOMING, data=body, headers=headers, timeout=aiohttp.ClientTimeout(total=10)) as resp:
            if resp.status not in (200, 201, 204):
                text = await resp.text()
                log.warning("Discourse returned %s for type=%s: %s", resp.status, payload.get("type"), text[:200])
            else:
                log.info("Relayed %s to Discourse (HTTP %s)", payload.get("type"), resp.status)
    except Exception as exc:
        log.error("Failed to relay %s to Discourse: %s", payload.get("type"), exc)


# ── Event handlers ────────────────────────────────────────────────────────────

@client.event
async def on_ready():
    log.info("Bridge bot connected as %s (id=%s)", client.user.name, client.user.id)
    log.info("Watching General channel id=%s and Support Forum id=%s", GENERAL_CHANNEL_ID, SUPPORT_FORUM_ID)


@client.event
async def on_message(message: discord.Message):
    # Ignore messages sent by any bot (including this one) to prevent loops.
    if message.author.bot:
        return

    channel = message.channel

    # ── General channel → Discourse Chat ────────────────────────────────────
    if channel.id == GENERAL_CHANNEL_ID:
        payload = {
            "type":             "chat_message",
            "discord_msg_id":   str(message.id),
            "discord_username": str(message.author.name),
            "discord_user_id":  str(message.author.id),
            "content":          message.content,
        }
        async with aiohttp.ClientSession() as session:
            await relay_to_discourse(session, payload)
        return

    # ── Forum channel thread reply → Discourse topic reply ──────────────────
    # A Forum thread itself is a Thread channel whose parent is the Forum channel.
    if isinstance(channel, discord.Thread) and channel.parent_id == SUPPORT_FORUM_ID:
        # The starter message of a Discord Forum post has the same snowflake ID
        # as the thread itself.  It is handled by on_thread_create → skip here
        # to prevent a duplicate forum_reply being sent alongside the forum_post.
        if message.id == channel.id:
            return

        payload = {
            "type":               "forum_reply",
            "discord_thread_id":  str(channel.id),
            "discord_msg_id":     str(message.id),
            "discord_username":   str(message.author.name),
            "discord_user_id":    str(message.author.id),
            "content":            message.content,
        }
        async with aiohttp.ClientSession() as session:
            await relay_to_discourse(session, payload)


@client.event
async def on_thread_create(thread: discord.Thread):
    """
    Fires when a new thread is created.  For Discord Forum channels the first
    message is sent in a separate on_message event (the thread starter message),
    so we only need to create the Discourse topic stub here and let the first
    on_message fill in the content.

    However, discord.py 2.x provides thread.starter_message for Forum posts.
    If available, use it. Otherwise fall back to fetching the first message.
    """
    if thread.parent_id != SUPPORT_FORUM_ID:
        return

    # Prefer the cached starter_message; fall back to fetching it.
    # In discord.py 2.x, thread.starter_message is populated for newly created
    # Forum posts since the message is in the cache at creation time.
    starter: Optional[discord.Message] = thread.starter_message
    if starter is None:
        try:
            starter = await thread.fetch_message(thread.id)
        except (discord.NotFound, discord.HTTPException):
            starter = None

    if starter and starter.author.bot:
        # First message is from a bot (likely this bot echoing back) — skip.
        return

    payload = {
        "type":               "forum_post",
        "discord_thread_id":  str(thread.id),
        "discord_username":   str(starter.author.name) if starter else "unknown",
        "discord_user_id":    str(starter.author.id)   if starter else "0",
        "title":              thread.name,
        "content":            starter.content if starter else "(no content)",
    }
    async with aiohttp.ClientSession() as session:
        await relay_to_discourse(session, payload)


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    client.run(DISCORD_BOT_TOKEN, log_handler=None)
