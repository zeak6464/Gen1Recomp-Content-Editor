# Hosting & Server Administration Guide

This guide covers self-hosting the `mod-scanner` Discord bot, configuring detection rules, and managing reference databases and whitelists.

For mod developer instructions on verifying mods, see the main [README.md](README.md).

---

## Architecture & Verification Pipeline

`mod-scanner` operates across tiered checks:

1. **Tier 0: Archive Security (Zip Bomb & Path Traversal Prevention)**
   - Calculates per-file compression ratios before streaming decompression.
   - Blocks directory traversal attacks (ZipSlip) and restricts maximum uncompressed archive sizes.

2. **Tier 1: Static Binary & ROM Header Scanner**
   - Inspects file streams using 64KB chunks to detect console ROM headers and magic bytes (Game Boy, GBC, GBA, N64, GameCube, Wii, Nintendo DS, 3DS, Nintendo Switch NSP/XCI).
   - Checks container packages (`.pack`, `.dat`, `.pak`) for embedded proprietary formats (`.bcres`, `CGFX`, `BCH\0`, `NW4C`, `SARC`, etc.).

3. **Tier 2: Perceptual Image Hashing (16x16 dHash)**
   - Composites transparent RGBA sprites onto solid white backgrounds prior to grayscale conversion to prevent luminance corruption.
   - Generates 256-bit difference hashes and evaluates bitwise XOR Hamming distance against canonical decomp assets:
     - Distance 0 to 14: Direct asset rip or minimal palette recolor (Auto-Reject).
     - Distance 15 to 30: Derivative edit or potential hand-drawn demake (Flagged for Review).
     - Distance > 30: Original custom artwork (Clean).

4. **Tier 3: Discord Bot Moderator Workflow**
   - Listens to Discord Forum Channels and threads for `.zip` attachments.
   - Automatically builds 3-panel side-by-side diff previews (`[Mod Asset] | [Canonical Ref] | [Pixel Difference]`).
   - Attaches an in-memory `.zip` bundle of all generated diff PNGs and provides interactive `[Approve (Whitelist Artwork)]` and `[Reject & Delete]` moderation buttons.

---

## Server Requirements

- Python 3.10+
- Linux, macOS, or Windows host
- Dependencies in `requirements.txt`

---

## Installation & Setup

```bash
git clone https://github.com/1Jamie/mod-scanner.git
cd mod-scanner
pip install -r requirements.txt
```

---

## Configuration Reference (`config.yaml`)

```yaml
# Optional GitHub personal access token to prevent rate limits during pret updates
github_token: ""

# Worker process pool limit for CPU-bound hashing and zip parsing
concurrency:
  max_workers: 2

# Upstream decomp repositories to pull canonical reference sprites from on first boot
pret_sources:
  - name: "pokered"
    repo: "pret/pokered"
    branch: "master"
    image_patterns:
      - "gfx/sprites/**/*.png"
      - "gfx/pokemon/**/*.png"
      - "gfx/trainers/**/*.png"
  - name: "pokeyellow"
    repo: "pret/pokeyellow"
    branch: "master"
    image_patterns:
      - "gfx/sprites/**/*.png"
      - "gfx/pokemon/**/*.png"
      - "gfx/trainers/**/*.png"
  - name: "pokefirered"
    repo: "pret/pokefirered"
    branch: "master"
    image_patterns:
      - "graphics/pokemon/**/front.png"
      - "graphics/pokemon/**/back.png"
      - "graphics/trainers/**/*.png"
  - name: "pokeheartgold"
    repo: "pret/pokeheartgold"
    branch: "master"
    image_patterns:
      - "files/graphic/**/*.png"
      - "src/data/graphics/**/*.png"

# Archive safety limits
archive:
  max_unpacked_size_mb: 500
  max_file_count: 50000
  max_compression_ratio: 20.0

# Binary and console ROM detection
binary_rules:
  blacklisted_extensions:
    - ".gb"
    - ".gbc"
    - ".gba"
    - ".nds"
    - ".3ds"
    - ".cia"
    - ".cxi"
    - ".z64"
    - ".n64"
    - ".v64"
    - ".iso"
    - ".wbfs"
    - ".wad"
    - ".nsp"
    - ".xci"

# Perceptual image matching thresholds
image_rules:
  hash_type: "dhash"
  hash_size: 16
  thresholds:
    auto_reject: 14
    flag_for_review: 30
  generate_diff_preview: true
  preview_panel_size: 64

# Discord bot configuration
discord:
  token: ""                   # Or export DISCORD_BOT_TOKEN
  guild_id: 0
  monitored_channel_ids: []   # List of Forum / Text Channel IDs (empty = all accessible channels)
  mod_review_channel_id: 0    # Channel where flagged embeds and diff bundles are sent
  max_embed_items: 4          # Number of top flagged matches to show in review embed
  attach_diff_bundle_zip: true
  auto_delete_violations: false

# Storage paths
paths:
  cache_dir: "./.cache"
  whitelist_file: "./whitelist.json"
```

---

## Discord Bot Deployment

1. Create a bot in the [Discord Developer Portal](https://discord.com/developers/applications).
2. Under the **Bot** tab, enable **Message Content Intent**.
3. Generate an OAuth2 invite URL with permissions to:
   - Read Messages / View Channels
   - Send Messages & Embed Links
   - Attach Files
   - Add Reactions
   - Manage Messages (if `auto_delete_violations: true`)
4. Set `token` in `config.yaml` or export `DISCORD_BOT_TOKEN`.
5. Set `mod_review_channel_id` to your staff moderation channel.
6. Launch the bot process:

```bash
python bot.py
```

### Syncing Application Slash Commands
To register the `/check-mod` slash command across your Discord guild, run:
```text
!sync
```
in any channel accessible to the bot (requires server Administrator permissions).

---

## Administrative CLI Commands

### Refresh Reference Database
Re-fetches canonical sprites from upstream decompilation repositories and rebuilds `.cache/reference_hashes.json`:
```bash
mod-scanner update-db
```

### Whitelist Management
Approved image hashes are stored in `whitelist.json`. Assets matching whitelisted hashes bypass similarity flags:
```bash
# List all whitelisted hashes
mod-scanner whitelist list

# Manually approve a hash
mod-scanner whitelist add <hash_hex>
```

---

## Running Test Suite

```bash
pytest -v
```
