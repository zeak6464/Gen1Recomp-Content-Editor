"""
Discord UI components and interactive review action buttons.
"""

from __future__ import annotations

import discord
from discord.ext import commands
from typing import List, Optional
from ..scanner import WhitelistManager, ScanFlag


class ModReviewView(discord.ui.View):
    """
    Interactive buttons attached to a flagged mod review embed in Discord.
    Allows moderators to Approve (and whitelist) or Reject a flagged release.
    """
    def __init__(
        self,
        whitelist_mgr: WhitelistManager,
        flagged_hashes: List[str],
        original_message: Optional[discord.Message] = None,
        author_user: Optional[discord.User] = None,
        timeout: Optional[float] = None,
    ):
        super().__init__(timeout=timeout)
        self.whitelist_mgr = whitelist_mgr
        self.flagged_hashes = flagged_hashes
        self.original_message = original_message
        self.author_user = author_user

    @discord.ui.button(label="Approve (Whitelist Artwork)", style=discord.ButtonStyle.green, emoji="✅")
    async def approve_button(self, interaction: discord.Interaction, button: discord.ui.Button):
        for h in self.flagged_hashes:
            self.whitelist_mgr.approve(h)

        for child in self.children:
            if isinstance(child, discord.ui.Button):
                child.disabled = True

        await interaction.response.edit_message(
            content=f"✅ **Approved by {interaction.user.mention}** - Asset hash(es) saved to whitelist.",
            view=self
        )

        # Send confirmation to author if available
        if self.author_user:
            try:
                await self.author_user.send(
                    f"🎉 Great news! Your mod post in **{interaction.guild.name if interaction.guild else 'the server'}** "
                    f"has been reviewed and approved by moderators."
                )
            except Exception:
                pass

    @discord.ui.button(label="Reject & Delete", style=discord.ButtonStyle.danger, emoji="🗑️")
    async def reject_button(self, interaction: discord.Interaction, button: discord.ui.Button):
        for child in self.children:
            if isinstance(child, discord.ui.Button):
                child.disabled = True

        await interaction.response.edit_message(
            content=f"❌ **Rejected by {interaction.user.mention}** - Mod contained derivative/ripped assets.",
            view=self
        )

        if self.original_message:
            try:
                await self.original_message.delete()
            except Exception:
                pass

        if self.author_user:
            try:
                await self.author_user.send(
                    f"⚠️ Your mod submission in **{interaction.guild.name if interaction.guild else 'the server'}** "
                    f"was reviewed and rejected by the moderation team due to copyrighted or directly ripped asset policies."
                )
            except Exception:
                pass
