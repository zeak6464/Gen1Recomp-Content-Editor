"""
Direct runner for the Mod Scanner Discord Bot.
Run with: python bot.py
"""

import logging
import os
import sys
from mod_scanner.config import Config
from mod_scanner.bot.bot import build_discord_bot

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)

def main():
    config = Config.from_file("config.yaml")
    token = config.discord.token or os.environ.get("DISCORD_BOT_TOKEN", "")

    if not token:
        print("\033[91mError: Discord bot token not provided.\033[0m")
        print("Set it in config.yaml under 'discord.token' or export DISCORD_BOT_TOKEN='your_token'")
        sys.exit(1)

    bot = build_discord_bot(config)
    bot.run(token)

if __name__ == "__main__":
    main()
