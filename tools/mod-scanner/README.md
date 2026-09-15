# mod-scanner

`mod-scanner` is an automated verification tool and CI/CD scanner for `gen1recomp` and decompilation mods. It checks mod releases and working directories for copyrighted Nintendo ROM dumps, proprietary container binaries, and direct sprite rips, while distinguishing original hand-drawn demakes for human moderator review.

---

## Mod Verification Guide (For Creators & Developers)

Mod authors should verify their mod files before uploading to release channels to ensure they meet community distribution rules.

### Verification Criteria

| Status | Trigger Criteria | Action Needed |
| :--- | :--- | :--- |
| **`CLEAN` (Passed)** | Custom textures, audio, scripts, and original scratch art. | Ready for release. |
| **`FLAGGED` (Review)** | High visual similarity to canonical sprites (Hamming distance 15 to 30). Common for hand-drawn demakes or adapted sprites. | Moderator will review the generated 3-panel diff preview. Whitelisted on approval. |
| **`REJECT` (Prohibited)** | Official console ROM headers (`.gb`, `.gba`, `.nds`, `.3ds`, `.z64`, `.nsp`, `.xci`), dumped archives, or direct 1:1 sprite rips (Hamming distance <= 14). | Remove prohibited binary dumps or rips before uploading. |

---

## 3 Ways to Check Your Mod

### Method 1: Local Scan (Working Directory or Zip)

You can scan your local working tree or a packed `.zip` archive using the Python CLI without needing an active bot.

#### Quick Setup:
```bash
git clone https://github.com/1Jamie/mod-scanner.git
cd mod-scanner
pip install -e .
```

#### Commands:
```bash
# Scan active mod working folder
mod-scanner scan ./path/to/my-mod-folder/

# Scan a built release zip
mod-scanner scan ./release/MyMod_v1.0.zip

# Scan a remote GitHub release URL
mod-scanner scan https://github.com/user/repo/releases/download/v1.0/mod.zip

# Save 3-panel diff previews to custom folder
mod-scanner scan ./path/to/my-mod-folder/ --preview-dir ./diff_previews/
```

#### Exit Codes:
- `0`: Clean (passed all checks).
- `1`: Flagged (potential demake or derivative edit needing review).
- `2`: Rejected (prohibited ROM header, proprietary archive, or direct rip).

Use `--no-fail-on-flagged` to return exit code `0` for flagged similarity warnings while still failing on hard violations.

---

### Method 2: GitHub Actions CI/CD Integration

Add `mod-scanner` directly into your repository workflow to automatically scan pull requests and tag releases. The action caches reference databases, posts a Markdown report to GitHub Step Summary, and attaches generated diff PNGs as workflow artifacts.

#### Add Workflow (`.github/workflows/mod-check.yml`):

```yaml
name: Mod Verification Check

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Run Mod Scanner
        uses: 1Jamie/mod-scanner@main
        with:
          path: '.'
          fail-on-flagged: 'true'
          save-previews: 'true'
          upload-artifacts: 'true'
```

#### Inputs:
- `path`: Path to directory or `.zip` file (default: `.`).
- `fail-on-flagged`: Set to `'false'` if you only want hard ROM/rip rejections to fail the build.
- `save-previews`: Generates side-by-side diff comparison PNGs.
- `upload-artifacts`: Uploads the diff images as a downloadable artifact.

---

### Method 3: Discord Self-Service Pre-Check

In Discord servers running the mod-scanner bot, you can test your mod privately before publishing to forum release channels:

- **/check-mod [file] [url]**: Runs a private ephemeral scan visible only to you.
  - If rejected, lists the exact filenames and ROM headers detected.
  - If flagged, displays percentage similarity scores, attaches the top preview image, and provides a downloadable `.zip` of all 3-panel diff comparisons.
- **!check [url]**: Text command fallback.

---

## Understanding 3-Panel Diff Previews

When an asset has a close silhouette or palette similarity to an official sprite, `mod-scanner` generates a 3-panel visual diff:

```text
+---------------------+---------------------+---------------------+
|      Panel 1        |      Panel 2        |      Panel 3        |
|    [Mod Asset]      |   [Canonical Ref]   |  [Pixel Difference] |
+---------------------+---------------------+---------------------+
```

- **Panel 1 (Mod Asset)**: The sprite included in your mod, normalized with 1:1 pixel scaling on a neutral checkerboard.
- **Panel 2 (Canonical Ref)**: The closest matching official reference sprite from the upstream decompilation repositories.
- **Panel 3 (Pixel Difference)**: Direct visual difference showing exactly which pixels match or deviate.

---

## Server Administration & Self-Hosting

Looking to host the Discord bot, configure server monitoring, or customize detection rules?

See the [Hosting & Server Administration Guide (HOSTING.md)](HOSTING.md).
