"""
Command-line interface for mod-scanner.
"""

from __future__ import annotations

import argparse
import io
import os
import sys
import tempfile
from pathlib import Path
import requests

from .config import Config
from .pret_fetcher import load_or_fetch_reference_database
from .scanner import ModScanner, WhitelistManager


def format_status_badge(status: str) -> str:
    if status == "CLEAN":
        return "\033[92m[CLEAN - PASSED]\033[0m"
    elif status == "FLAGGED":
        return "\033[93m[FLAGGED - REVIEW NEEDED]\033[0m"
    elif status == "REJECT":
        return "\033[91m[REJECT - PROHIBITED]\033[0m"
    return f"[{status}]"


def write_github_actions_outputs(result: ScanResult, target_name: str, preview_files: list[Path]):
    """Writes GitHub Actions step summary and outputs when running in CI/CD."""
    step_summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary_path:
        badge = "🟢 **PASSED (CLEAN)**" if result.is_clean else ("🟡 **FLAGGED FOR REVIEW**" if result.is_flagged else "🔴 **REJECTED (PROHIBITED)**")
        lines = [
            f"## 🛡️ Mod Scanner Report: `{target_name}`",
            "",
            "| Metric | Status |",
            "| :--- | :--- |",
            f"| **Verdict** | {badge} |",
            f"| **Files Scanned** | `{result.scanned_file_count}` |",
            f"| **Scan Duration** | `{result.elapsed_seconds}s` |",
            f"| **Violations** | `{len(result.violations)}` |",
            f"| **Flagged for Review** | `{len(result.flags)}` |",
            "",
        ]

        if result.violations:
            lines.extend([
                "### 🚨 Hard Violations (Auto-Reject)",
                "| File Path | Rule Type | Violation Details |",
                "| :--- | :--- | :--- |",
            ])
            for v in result.violations:
                clean_path = v.file_path.replace("|", "/")
                clean_msg = v.message.replace("|", "/")
                lines.append(f"| `{clean_path}` | `{v.rule_type}` | {clean_msg} |")
            lines.append("")

        if result.flags:
            lines.extend([
                "### ⚠️ Flagged Assets (Derivative Edits / Demakes)",
                "_These assets closely resemble canonical assets. Review the 3-panel diff artifact to verify whether they are original hand-drawn demakes._",
                "",
                "| File Path | Matched Reference | Similarity | Hamming Distance | Mod Hash |",
                "| :--- | :--- | :--- | :--- | :--- |",
            ])
            for f in result.flags:
                clean_path = f.file_path.replace("|", "/")
                clean_ref = f.matched_ref.replace("|", "/")
                pct = round((1 - f.hamming_distance / 256) * 100, 1)
                lines.append(f"| `{clean_path}` | `{clean_ref}` | **{pct}%** | `{f.hamming_distance}/256` | `{f.mod_hash[:16]}...` |")
            lines.append("")

        if preview_files:
            lines.extend([
                "> [!NOTE]",
                f"> **{len(preview_files)} Diff Previews Generated**: Download the workflow artifact `mod-scanner-diffs` to visually inspect side-by-side sprite comparisons.",
                "",
            ])

        try:
            with open(step_summary_path, "a", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
        except Exception as e:
            print(f"Warning: Failed to write to GITHUB_STEP_SUMMARY: {e}", file=sys.stderr)

    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        try:
            with open(output_path, "a", encoding="utf-8") as f:
                f.write(f"verdict={result.status}\n")
                f.write(f"scanned-count={result.scanned_file_count}\n")
                f.write(f"violations-count={len(result.violations)}\n")
                f.write(f"flags-count={len(result.flags)}\n")
        except Exception as e:
            print(f"Warning: Failed to write to GITHUB_OUTPUT: {e}", file=sys.stderr)


def handle_scan(args, config: Config):
    target = args.target
    is_url = target.startswith("http://") or target.startswith("https://")

    print(f"Loading reference database (cache: {config.paths.reference_hashes_file})...")
    scanner = ModScanner(config=config)

    temp_file = None
    try:
        if is_url:
            print(f"Downloading remote archive from: {target}")
            with requests.get(target, stream=True, timeout=60) as resp:
                resp.raise_for_status()
                temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".zip")
                for chunk in resp.iter_content(chunk_size=64 * 1024):
                    if chunk:
                        temp_file.write(chunk)
                temp_file.close()
            scan_path = temp_file.name
        else:
            scan_path = target
            if not os.path.exists(scan_path):
                print(f"\033[91mError: Target path not found: {scan_path}\033[0m", file=sys.stderr)
                sys.exit(1)

        is_directory = os.path.isdir(scan_path)
        scan_type_str = "directory" if is_directory else "archive"
        print(f"Scanning {scan_type_str} '{target}'...")
        result = scanner.scan_target_sync(scan_path)

        print("\n" + "=" * 60)
        print(f" Verdict: {format_status_badge(result.status)}")
        print(f" Summary: {result.summary}")
        print(f" Files Scanned: {result.scanned_file_count} (in {result.elapsed_seconds}s)")
        print("=" * 60)

        if result.violations:
            print("\n\033[91m🚨 VIOLATIONS DETECTED:\033[0m")
            for i, v in enumerate(result.violations, 1):
                print(f"  {i}. [{v.rule_type}] {v.file_path}")
                print(f"     -> {v.message}")

        saved_previews: list[Path] = []
        if result.flags:
            print("\n\033[93m⚠️ FLAGGED ASSETS (POTENTIAL DEMAKES / EDITS):\033[0m")
            out_preview_dir = Path(args.preview_dir)
            if args.save_previews:
                out_preview_dir.mkdir(parents=True, exist_ok=True)

            for i, f in enumerate(result.flags, 1):
                pct = round((1 - f.hamming_distance / 256) * 100, 1)
                print(f"  {i}. {f.file_path}")
                print(f"     Closest Match: {f.matched_ref}")
                print(f"     Hamming Distance: {f.hamming_distance}/256 ({pct}% identical)")
                print(f"     Mod Hash: {f.mod_hash}")

                if args.save_previews and f.preview_bytes:
                    clean_name = f.file_path.replace("/", "_").replace("\\", "_").replace(" ", "_")
                    preview_file = out_preview_dir / f"diff_{i:03d}_{clean_name}.png"
                    with open(preview_file, "wb") as pf:
                        pf.write(f.preview_bytes)
                    saved_previews.append(preview_file)
                    print(f"     Preview Diff Saved: {preview_file}")

        # Check GitHub Actions integration
        is_github_actions = args.github_actions or "GITHUB_STEP_SUMMARY" in os.environ
        if is_github_actions:
            write_github_actions_outputs(result, target, saved_previews)

        print("")
        if result.is_rejected:
            sys.exit(2)
        elif result.is_flagged:
            if args.fail_on_flagged:
                sys.exit(1)
            else:
                sys.exit(0)
        else:
            sys.exit(0)

    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except Exception:
                pass


def handle_update_db(args, config: Config):
    print("Force updating reference database from pret upstream repositories...")
    ref_db = load_or_fetch_reference_database(config, force_refresh=True)
    print(f"\033[92mSuccess! Reference database updated with {len(ref_db.hashes)} asset hashes.\033[0m")


def handle_whitelist(args, config: Config):
    wm = WhitelistManager(config.paths.whitelist_file)
    if args.action == "list":
        print(f"Approved Whitelisted Hashes ({len(wm._approved_hashes)}):")
        for h in sorted(list(wm._approved_hashes)):
            print(f"  - {h}")
    elif args.action == "add":
        if not args.hash:
            print("Error: hash required to add to whitelist", file=sys.stderr)
            sys.exit(1)
        if wm.approve(args.hash):
            print(f"\033[92mHash {args.hash} added to whitelist.\033[0m")
        else:
            print(f"Hash {args.hash} is already in whitelist.")


def main():
    parser = argparse.ArgumentParser(
        prog="mod-scanner",
        description="Copyright and ROM scanner for gen1recomp and decomp mods.",
    )
    parser.add_argument("--config", default="config.yaml", help="Path to config.yaml")

    subparsers = parser.add_subparsers(dest="command", required=True)

    # Scan command
    scan_parser = subparsers.add_parser("scan", help="Scan a directory, local .zip archive, or release URL")
    scan_parser.add_argument("target", help="File path to directory, .zip archive, or release URL")
    scan_parser.add_argument(
        "--save-previews", action="store_true", default=True, help="Save diff preview PNGs"
    )
    scan_parser.add_argument(
        "--preview-dir", default="./scan_previews", help="Directory where diff preview PNGs are saved"
    )
    scan_parser.add_argument(
        "--github-actions", action="store_true", default=False, help="Emit GitHub Actions step summary and outputs"
    )
    scan_parser.add_argument(
        "--fail-on-flagged", dest="fail_on_flagged", action="store_true", default=True,
        help="Exit with code 1 if assets are flagged for review (default)"
    )
    scan_parser.add_argument(
        "--no-fail-on-flagged", dest="fail_on_flagged", action="store_false",
        help="Exit with code 0 if assets are flagged (only exit non-zero on hard violations)"
    )

    # Update DB command
    subparsers.add_parser("update-db", help="Fetch pret sources and refresh reference hash database")

    # Whitelist command
    wl_parser = subparsers.add_parser("whitelist", help="Manage approved asset whitelist")
    wl_parser.add_argument("action", choices=["list", "add"], help="Action to perform")
    wl_parser.add_argument("hash", nargs="?", default="", help="Hash string to add")

    args = parser.parse_args()
    config = Config.from_file(args.config)

    if args.command == "scan":
        handle_scan(args, config)
    elif args.command == "update-db":
        handle_update_db(args, config)
    elif args.command == "whitelist":
        handle_whitelist(args, config)


if __name__ == "__main__":
    main()

