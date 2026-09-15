"""
Production Discord Bot for automated mod zip scanning and moderator workflows.
Supports Forum Channels, Threads, Diff Zip Bundling, and Anti-Spam Capped Reporting.
"""

from __future__ import annotations

import asyncio
import io
import logging
import os
import zipfile
import aiohttp
import discord
from discord.ext import commands

from ..config import Config
from ..scanner import ModScanner, ScanResult, ScanFlag, ScanViolation
from .views import ModReviewView

logger = logging.getLogger("mod_scanner.bot")


def create_diff_bundle_zip(source_name: str, result: ScanResult) -> io.BytesIO:
    """
    Creates an in-memory zip archive containing a text report and all generated
    3-panel diff PNGs so moderators can download and review large mods in bulk.
    """
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", compression=zipfile.ZIP_DEFLATED) as z:
        # 1. Summary report
        report_lines = [
            f"MOD SCANNER REPORT: {source_name}",
            f"Status: {result.status}",
            f"Scanned Files: {result.scanned_file_count}",
            f"Elapsed Time: {result.elapsed_seconds}s",
            "=" * 60,
            "",
        ]

        if result.violations:
            report_lines.append("VIOLATIONS (Hard Rejections):")
            for i, v in enumerate(result.violations, 1):
                report_lines.append(f"  {i}. [{v.rule_type}] {v.file_path}")
                report_lines.append(f"     Reason: {v.message}")
            report_lines.append("")

        if result.flags:
            report_lines.append("FLAGGED ASSETS (Potential Demakes / Derivative Edits):")
            for i, f in enumerate(result.flags, 1):
                report_lines.append(f"  {i}. {f.file_path}")
                report_lines.append(f"     Matched Reference: {f.matched_ref}")
                report_lines.append(f"     Hamming Distance: {f.hamming_distance}/256")
                report_lines.append(f"     Mod Hash: {f.mod_hash}")
                report_lines.append(f"     Ref Hash: {f.ref_hash}")
                report_lines.append("")

        z.writestr("scan_report.txt", "\n".join(report_lines).encode("utf-8"))

        # 2. Add all preview images
        for i, flag in enumerate(result.flags, 1):
            if flag.preview_bytes:
                clean_filename = flag.file_path.replace("/", "_").replace("\\", "_")
                z.writestr(f"diffs/{i:03d}_{clean_filename}.png", flag.preview_bytes)

    zip_buffer.seek(0)
    return zip_buffer


def is_channel_monitored(channel: discord.abc.GuildChannel | discord.Thread, config: Config) -> bool:
    """Checks if a message's channel (or parent forum channel) is configured to be monitored."""
    if not config.discord.monitored_channel_ids:
        return True  # If empty, monitor all accessible channels

    monitored = set(config.discord.monitored_channel_ids)
    if channel.id in monitored:
        return True

    # If channel is a thread inside a forum or text channel, check parent ID
    if isinstance(channel, discord.Thread) and channel.parent_id in monitored:
        return True

    return False


def build_discord_bot(config: Config) -> commands.Bot:
    intents = discord.Intents.default()
    intents.message_content = True  # Required to inspect attachment filenames & contents

    bot = commands.Bot(command_prefix="!", intents=intents)
    scanner = ModScanner(config=config)

    @bot.event
    async def on_ready():
        logger.info(f"Mod Scanner Bot connected as {bot.user} (ID: {bot.user.id})")
        logger.info(f"Loaded {len(scanner.ref_db.hashes)} reference hashes into memory.")
        if config.discord.monitored_channel_ids:
            logger.info(f"Monitoring channels/forums: {config.discord.monitored_channel_ids}")
        else:
            logger.info("Monitoring all channels/forums where the bot has access.")
        print(f"Mod Scanner Bot online as {bot.user}")

    async def process_zip_payload(
        zip_bytes: bytes,
        source_name: str,
        message: discord.Message,
        channel: discord.abc.Messageable
    ):
        # Offload CPU-bound scanning to worker pool to protect Discord heartbeat
        result: ScanResult = await asyncio.to_thread(scanner.scan_archive_sync, zip_bytes)

        # Thread context info
        is_thread = isinstance(message.channel, discord.Thread)
        thread_info = f"🧵 **Thread:** `{message.channel.name}`\n" if is_thread else ""
        parent_name = message.channel.parent.name if is_thread and message.channel.parent else message.channel.name

        if result.is_clean:
            try:
                await message.add_reaction("✅")
            except Exception:
                pass
            logger.info(f"Archive '{source_name}' in '{message.channel.name}' from {message.author} passed scan (CLEAN).")

        elif result.is_rejected:
            try:
                await message.add_reaction("❌")
            except Exception:
                pass

            # DM author with top reasons (capped to avoid DM size limits)
            rejection_reasons = "\n".join(
                [f"• **[{v.rule_type}]** `{v.file_path}`: {v.message}" for v in result.violations[:10]]
            )
            if len(result.violations) > 10:
                rejection_reasons += f"\n_...and {len(result.violations) - 10} more violations._"

            dm_text = (
                f"⚠️ **Your mod upload '{source_name}' was automatically rejected:**\n\n"
                f"{rejection_reasons}\n\n"
                f"_Please ensure your release contains no official Nintendo ROM dumps, proprietary binaries, or direct asset rips._"
            )
            try:
                await message.author.send(dm_text)
            except Exception:
                pass

            if config.discord.auto_delete_violations:
                try:
                    await message.delete()
                except Exception:
                    pass

        elif result.is_flagged:
            try:
                await message.add_reaction("⚠️")
            except Exception:
                pass

            # Send review embed to moderator review channel
            review_channel_id = config.discord.mod_review_channel_id
            review_channel = bot.get_channel(review_channel_id) if review_channel_id else channel

            flag_hashes = [f.mod_hash for f in result.flags]
            view = ModReviewView(
                whitelist_mgr=scanner.whitelist,
                flagged_hashes=flag_hashes,
                original_message=message,
                author_user=message.author,
            )

            # Sort flags by lowest Hamming distance (highest similarity first)
            sorted_flags = sorted(result.flags, key=lambda f: f.hamming_distance)
            max_items = config.discord.max_embed_items
            top_flags = sorted_flags[:max_items]
            remaining_count = len(sorted_flags) - len(top_flags)

            # Build concise embed
            embed = discord.Embed(
                title=f"⚠️ Asset Review Needed: {source_name}",
                description=(
                    f"**Author:** {message.author.mention} (`{message.author.name}`)\n"
                    f"**Location:** #{parent_name} {f'(Thread: `{message.channel.name}`)' if is_thread else ''}\n"
                    f"**Jump to Message:** [Click here to view upload]({message.jump_url})\n"
                    f"**Total Flagged Assets:** {len(result.flags)} of {result.scanned_file_count} files\n\n"
                    f"_Inspect the 3-panel diff below to check if this is an original demake or a derivative rip._"
                ),
                color=discord.Color.gold(),
            )

            files_to_send: list[discord.File] = []

            for i, flag in enumerate(top_flags, 1):
                embed.add_field(
                    name=f"Asset #{i}: `{flag.file_path}`",
                    value=(
                        f"• Match: `{flag.matched_ref}`\n"
                        f"• Distance: `{flag.hamming_distance}/256` ({round((1 - flag.hamming_distance / 256) * 100, 1)}% identical)\n"
                        f"• Confidence: `{'High Similarity (Demake?)' if flag.hamming_distance > 14 else 'Probable Rip'}`"
                    ),
                    inline=False,
                )
                if flag.preview_bytes and i == 1:
                    # Attach the top diff as the embed thumbnail/image
                    preview_filename = "top_diff_preview.png"
                    files_to_send.append(
                        discord.File(io.BytesIO(flag.preview_bytes), filename=preview_filename)
                    )
                    embed.set_image(url=f"attachment://{preview_filename}")

            if remaining_count > 0:
                embed.add_field(
                    name="📦 Additional Flagged Assets",
                    value=f"_...and **{remaining_count} more** flagged assets included in the attached diff bundle zip._",
                    inline=False,
                )

            # Generate and attach the full report & diffs zip bundle if enabled
            if config.discord.attach_diff_bundle_zip and result.flags:
                bundle_zip_buf = create_diff_bundle_zip(source_name, result)
                clean_zip_name = f"diff_bundle_{source_name.replace('.zip', '')}.zip"
                files_to_send.append(
                    discord.File(bundle_zip_buf, filename=clean_zip_name)
                )

            embed.set_footer(text="Panel format: [ Mod Asset ] [ Canonical Ref ] [ Pixel Diff ]")

            if review_channel:
                await review_channel.send(embed=embed, files=files_to_send, view=view)

    @bot.event
    async def on_message(message: discord.Message):
        if message.author.bot:
            return

        # Check channel filter
        if not is_channel_monitored(message.channel, config):
            return

        # Check for zip attachments
        for attachment in message.attachments:
            if attachment.filename.lower().endswith(".zip"):
                try:
                    logger.info(f"Scanning attachment '{attachment.filename}' in #{message.channel.name}...")
                    zip_data = await attachment.read()
                    await process_zip_payload(
                        zip_bytes=zip_data,
                        source_name=attachment.filename,
                        message=message,
                        channel=message.channel
                    )
                except Exception as e:
                    logger.error(f"Error scanning attachment {attachment.filename}: {e}")

        await bot.process_commands(message)

    @bot.event
    async def on_thread_create(thread: discord.Thread):
        """Monitors newly created forum threads for initial post zip attachments."""
        if not is_channel_monitored(thread, config):
            return

        try:
            # Fetch starter message of the thread
            starter_message = await thread.fetch_message(thread.id)
            if starter_message:
                for attachment in starter_message.attachments:
                    if attachment.filename.lower().endswith(".zip"):
                        logger.info(f"Scanning starter attachment '{attachment.filename}' in new thread '{thread.name}'...")
                        zip_data = await attachment.read()
                        await process_zip_payload(
                            zip_bytes=zip_data,
                            source_name=attachment.filename,
                            message=starter_message,
                            channel=thread
                        )
        except Exception as e:
            logger.debug(f"Could not check starter message for thread {thread.name}: {e}")

    async def handle_self_check(
        zip_bytes: bytes,
        source_name: str,
        user: discord.User | discord.Member,
    ) -> tuple[discord.Embed, list[discord.File]]:
        """Scans a mod payload for self-service developer checks and builds response embeds and diff attachments."""
        result: ScanResult = await asyncio.to_thread(scanner.scan_archive_sync, zip_bytes)
        files_to_send: list[discord.File] = []

        if result.is_clean:
            embed = discord.Embed(
                title=f"✅ Pre-Check Passed: {source_name}",
                description=(
                    f"**Status:** Clean\n"
                    f"**Files Scanned:** {result.scanned_file_count} (in {result.elapsed_seconds}s)\n\n"
                    f"No official Nintendo ROM headers, proprietary binaries, or matching canonical sprites were detected. "
                    f"Your mod is ready for upload!"
                ),
                color=discord.Color.green(),
            )
            return embed, files_to_send

        elif result.is_rejected:
            embed = discord.Embed(
                title=f"❌ Pre-Check Failed (Prohibited Assets): {source_name}",
                description=(
                    f"**Status:** Rejected\n"
                    f"**Violations Found:** {len(result.violations)}\n"
                    f"**Files Scanned:** {result.scanned_file_count} (in {result.elapsed_seconds}s)\n\n"
                    f"The following prohibited files or direct asset rips were detected:\n"
                ),
                color=discord.Color.red(),
            )
            for i, v in enumerate(result.violations[:10], 1):
                embed.add_field(
                    name=f"Violation #{i}: `{v.file_path}`",
                    value=f"• **Rule:** `{v.rule_type}`\n• **Reason:** {v.message}",
                    inline=False,
                )
            if len(result.violations) > 10:
                embed.add_field(
                    name="📦 Additional Violations",
                    value=f"_...and **{len(result.violations) - 10} more** violations._",
                    inline=False,
                )
            embed.set_footer(text="Please remove official ROM headers, dumped archives, or direct rips before posting.")
            return embed, files_to_send

        else:  # FLAGGED
            embed = discord.Embed(
                title=f"⚠️ Similarity Review Needed: {source_name}",
                description=(
                    f"**Status:** Flagged for Moderator Review\n"
                    f"**Flagged Assets:** {len(result.flags)} of {result.scanned_file_count} files\n"
                    f"**Scan Duration:** {result.elapsed_seconds}s\n\n"
                    f"These assets closely resemble official sprites. If they are original hand-drawn demakes, "
                    f"moderators will review the 3-panel diffs when you post your thread."
                ),
                color=discord.Color.gold(),
            )

            sorted_flags = sorted(result.flags, key=lambda f: f.hamming_distance)
            top_flags = sorted_flags[:5]

            for i, flag in enumerate(top_flags, 1):
                pct = round((1 - flag.hamming_distance / 256) * 100, 1)
                embed.add_field(
                    name=f"Asset #{i}: `{flag.file_path}`",
                    value=(
                        f"• **Match:** `{flag.matched_ref}`\n"
                        f"• **Similarity:** `{pct}%` (Hamming distance `{flag.hamming_distance}/256`)\n"
                        f"• **Hash:** `{flag.mod_hash[:16]}...`"
                    ),
                    inline=False,
                )
                if flag.preview_bytes and i == 1:
                    preview_filename = "self_check_diff_preview.png"
                    files_to_send.append(
                        discord.File(io.BytesIO(flag.preview_bytes), filename=preview_filename)
                    )
                    embed.set_image(url=f"attachment://{preview_filename}")

            if len(sorted_flags) > 5:
                embed.add_field(
                    name="📦 Additional Flagged Assets",
                    value=f"_...and **{len(sorted_flags) - 5} more** flagged assets included in the diff bundle._",
                    inline=False,
                )

            # Generate downloadable diff bundle so author can inspect locally
            if result.flags:
                bundle_buf = create_diff_bundle_zip(source_name, result)
                files_to_send.append(
                    discord.File(bundle_buf, filename=f"precheck_diffs_{source_name.replace('.zip', '')}.zip")
                )

            embed.set_footer(text="Panel format: [ Mod Asset ] [ Canonical Ref ] [ Pixel Diff ]")
            return embed, files_to_send

    @bot.tree.command(name="check-mod", description="Privately pre-check your mod zip before posting to avoid auto-rejections.")
    async def check_mod_slash(
        interaction: discord.Interaction,
        file: discord.Attachment | None = None,
        url: str | None = None,
    ):
        """Slash command for self-service pre-checks (runs ephemerally)."""
        if not file and not url:
            await interaction.response.send_message(
                "❌ Please attach a `.zip` file or provide a direct `.zip` URL to check.",
                ephemeral=True,
            )
            return

        await interaction.response.defer(ephemeral=True)

        try:
            if file:
                if not file.filename.lower().endswith(".zip"):
                    await interaction.followup.send("❌ Attached file must be a `.zip` archive.", ephemeral=True)
                    return
                source_name = file.filename
                zip_data = await file.read()
            else:
                source_name = url.split("/")[-1] or "mod.zip"
                async with aiohttp.ClientSession() as session:
                    async with session.get(url, timeout=aiohttp.ClientTimeout(total=60)) as resp:
                        if resp.status != 200:
                            await interaction.followup.send(f"❌ Failed to download archive (HTTP {resp.status})", ephemeral=True)
                            return
                        zip_data = await resp.read()

            embed, files = await handle_self_check(zip_data, source_name, interaction.user)
            await interaction.followup.send(embed=embed, files=files, ephemeral=True)

        except Exception as e:
            logger.exception(f"Error in /check-mod: {e}")
            await interaction.followup.send(f"❌ Error during mod pre-check: {e}", ephemeral=True)

    @bot.command(name="check")
    async def manual_check_command(ctx: commands.Context, url: str | None = None):
        """Self-service check via message attachment or URL."""
        attachment = ctx.message.attachments[0] if ctx.message.attachments else None
        if not attachment and not url:
            await ctx.reply("❌ Please attach a `.zip` archive to your message or specify a URL: `!check <url>`")
            return

        status_msg = await ctx.reply("⏳ Running mod pre-check...")
        try:
            if attachment:
                if not attachment.filename.lower().endswith(".zip"):
                    await status_msg.edit(content="❌ Attached file must be a `.zip` archive.")
                    return
                source_name = attachment.filename
                zip_data = await attachment.read()
            else:
                source_name = url.split("/")[-1] or "mod.zip"
                async with aiohttp.ClientSession() as session:
                    async with session.get(url, timeout=aiohttp.ClientTimeout(total=60)) as resp:
                        if resp.status != 200:
                            await status_msg.edit(content=f"❌ Failed to download archive (HTTP {resp.status})")
                            return
                        zip_data = await resp.read()

            embed, files = await handle_self_check(zip_data, source_name, ctx.author)
            await ctx.reply(embed=embed, files=files)
            await status_msg.delete()
        except Exception as e:
            logger.exception(f"Error in !check: {e}")
            await status_msg.edit(content=f"❌ Error during scan: {e}")

    @bot.command(name="sync")
    @commands.has_permissions(administrator=True)
    async def sync_tree_command(ctx: commands.Context):
        """Sync application commands with Discord (Admin only)."""
        synced = await bot.tree.sync()
        await ctx.reply(f"✅ Synced {len(synced)} application commands.")

    return bot

