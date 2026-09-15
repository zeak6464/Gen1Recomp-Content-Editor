"""
Core orchestrator for scanning mod archives across all tiers.
"""

from __future__ import annotations

import io
import json
import logging
import math
import os
import time
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, BinaryIO, Dict, List, Optional, Set, Tuple
from PIL import Image

from .config import Config
from .core.archive import open_safe_zip, ArchiveSecurityError
from .core.binary_scanner import check_file_stream_for_magic, BinaryViolation
from .core.image_scanner import (
    compute_image_hash,
    calculate_hamming_distance,
    generate_diff_preview,
    ImageMatchResult,
)
from .pret_fetcher import ReferenceDatabase, load_or_fetch_reference_database

logger = logging.getLogger("mod_scanner.scanner")

IMAGE_EXTENSIONS = {".png", ".bmp", ".jpg", ".jpeg", ".webp", ".tga"}
RAW_TEXTURE_EXTENSIONS = {".rgba", ".rgb", ".bgra", ".raw"}
CONTAINER_PACKAGE_EXTENSIONS = {".pack", ".dat", ".pak", ".bundle", ".bin", ".arc", ".res", ".fsys", ".rarc"}


def _parse_image_from_bytes(raw_data: bytes, ext_lower: str) -> Optional[Image.Image]:
    """Attempts to parse raw bytes into a Pillow Image from standard formats or raw buffers."""
    if ext_lower in IMAGE_EXTENSIONS:
        try:
            img = Image.open(io.BytesIO(raw_data))
            img.load()
            return img
        except Exception:
            return None
    elif ext_lower in RAW_TEXTURE_EXTENSIONS:
        length = len(raw_data)
        if ext_lower in {".rgba", ".bgra", ".raw"} and length >= 64:
            w = int(math.isqrt(length // 4))
            if w * w * 4 == length:
                try:
                    mode = "RGBA" if ext_lower in {".rgba", ".raw"} else "BGRA"
                    img = Image.frombytes(mode, (w, w), raw_data)
                    if mode == "BGRA":
                        img = img.convert("RGBA")
                    return img
                except Exception:
                    return None
        elif ext_lower == ".rgb" and length >= 48:
            w = int(math.isqrt(length // 3))
            if w * w * 3 == length:
                try:
                    return Image.frombytes("RGB", (w, w), raw_data)
                except Exception:
                    return None
    return None



@dataclass
class ScanViolation:
    file_path: str
    rule_type: str
    message: str


@dataclass
class ScanFlag:
    file_path: str
    matched_ref: str
    hamming_distance: int
    mod_hash: str
    ref_hash: str
    preview_bytes: Optional[bytes] = None


@dataclass
class ScanResult:
    status: str  # "CLEAN", "FLAGGED", "REJECT"
    summary: str
    scanned_file_count: int
    elapsed_seconds: float
    violations: List[ScanViolation] = field(default_factory=list)
    flags: List[ScanFlag] = field(default_factory=list)

    @property
    def is_clean(self) -> bool:
        return self.status == "CLEAN"

    @property
    def is_rejected(self) -> bool:
        return self.status == "REJECT"

    @property
    def is_flagged(self) -> bool:
        return self.status == "FLAGGED"


class WhitelistManager:
    """Manages moderator-approved asset hashes stored in a flat JSON file."""
    def __init__(self, file_path: Path):
        self.file_path = file_path
        self._approved_hashes: Set[str] = set()
        self.load()

    def load(self):
        if self.file_path.exists():
            try:
                with open(self.file_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    self._approved_hashes = set(data.get("approved_hashes", []))
            except Exception as e:
                logger.warning(f"Could not load whitelist {self.file_path}: {e}")
                self._approved_hashes = set()

    def is_approved(self, image_hash: str) -> bool:
        return image_hash in self._approved_hashes

    def approve(self, image_hash: str, note: str = "") -> bool:
        if image_hash in self._approved_hashes:
            return False
        self._approved_hashes.add(image_hash)
        self._save()
        return True

    def _save(self):
        self.file_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.file_path, "w", encoding="utf-8") as f:
            json.dump({
                "approved_hashes": sorted(list(self._approved_hashes))
            }, f, indent=2)


def _extract_embedded_pngs(data: bytes, max_images: int = 100) -> List[Tuple[int, Image.Image]]:
    """Extracts embedded PNG streams from packed binary files (.pack, .dat, .pak, etc.)."""
    png_magic = b"\x89PNG\r\n\x1a\n"
    iend_magic = b"IEND\xaeB\x60\x82"
    images = []
    idx = 0
    while len(images) < max_images:
        start = data.find(png_magic, idx)
        if start == -1:
            break
        end = data.find(iend_magic, start)
        if end == -1:
            break
        end += len(iend_magic)
        png_bytes = data[start:end]
        try:
            img = Image.open(io.BytesIO(png_bytes))
            img.load()
            images.append((start, img))
        except Exception:
            pass
        idx = end
    return images


def _evaluate_image_against_reference_db(
    img: Image.Image,
    filename_label: str,
    scanner: ModScanner,
    violations: List[ScanViolation],
    flags: List[ScanFlag],
):
    """Computes image hash, checks whitelist, and evaluates similarity against reference DB."""
    try:
        # Ignore sub-16px helper slices and solid single-color masks
        if img.width < 16 or img.height < 16:
            return
        extrema = img.convert("L").getextrema()
        if extrema[0] == extrema[1]:
            return

        mod_hash = compute_image_hash(
            img,
            hash_size=scanner.config.image_rules.hash_size,
            hash_type=scanner.config.image_rules.hash_type,
        )

        if scanner.whitelist.is_approved(mod_hash):
            return

        best_match_key = None
        best_distance = 999999
        best_ref_hash = None

        for ref_key, ref_hash in scanner.ref_db.hashes.items():
            dist = calculate_hamming_distance(mod_hash, ref_hash)
            if dist < best_distance:
                best_distance = dist
                best_match_key = ref_key
                best_ref_hash = ref_hash
                if dist == 0:
                    break

        if best_match_key and best_distance <= scanner.config.image_rules.threshold_auto_reject:
            violations.append(
                ScanViolation(
                    file_path=filename_label,
                    rule_type="DirectAssetRip",
                    message=f"Image matches canonical asset '{best_match_key}' (Hamming Distance: {best_distance}/{scanner.config.image_rules.hash_size ** 2})",
                )
            )
        elif best_match_key and best_distance <= scanner.config.image_rules.threshold_flag_for_review:
            preview_bytes = None
            if scanner.config.image_rules.generate_diff_preview:
                ref_img = scanner.ref_db.get_reference_image(best_match_key)
                if ref_img:
                    preview_canvas = generate_diff_preview(
                        mod_img=img,
                        ref_img=ref_img,
                        panel_size=scanner.config.image_rules.preview_panel_size,
                    )
                    buf = io.BytesIO()
                    preview_canvas.save(buf, format="PNG")
                    preview_bytes = buf.getvalue()

            flags.append(
                ScanFlag(
                    file_path=filename_label,
                    matched_ref=best_match_key,
                    hamming_distance=best_distance,
                    mod_hash=mod_hash,
                    ref_hash=best_ref_hash or "",
                    preview_bytes=preview_bytes,
                )
            )
    except Exception as e:
        logger.debug(f"Could not evaluate image {filename_label}: {e}")


class ModScanner:
    """
    Main scanner instance holding configuration and reference bank.
    """
    def __init__(self, config: Optional[Config] = None, ref_db: Optional[ReferenceDatabase] = None):
        self.config = config or Config.from_file()
        self.ref_db = ref_db or load_or_fetch_reference_database(self.config)
        self.whitelist = WhitelistManager(self.config.paths.whitelist_file)
        self._pool: Optional[ProcessPoolExecutor] = None

    def get_executor(self) -> ProcessPoolExecutor:
        if self._pool is None:
            max_workers = max(1, self.config.concurrency.max_workers)
            self._pool = ProcessPoolExecutor(max_workers=max_workers)
        return self._pool

    def close(self):
        if self._pool is not None:
            self._pool.shutdown(wait=False)
            self._pool = None

    def scan_archive_sync(self, zip_source: str | os.PathLike | bytes | BinaryIO) -> ScanResult:
        """
        Synchronously scans a zip archive through Tier 0 (Safety), Tier 1 (Binary/ROM),
        and Tier 2 (Perceptual Image Hashing).
        """
        start_time = time.time()
        violations: List[ScanViolation] = []
        flags: List[ScanFlag] = []

        # 1. Tier 0: Open safe zip archive (enforces compression ratio, size, path traversal)
        try:
            z = open_safe_zip(zip_source, self.config.archive)
        except ArchiveSecurityError as e:
            return ScanResult(
                status="REJECT",
                summary=f"Archive security check failed: {e}",
                scanned_file_count=0,
                elapsed_seconds=round(time.time() - start_time, 3),
                violations=[ScanViolation(file_path="archive", rule_type="ArchiveSecurity", message=str(e))],
            )

        scanned_files = 0

        # Iterate over zip members without extracting to disk
        try:
            for zinfo in z.infolist():
                if zinfo.is_dir() or zinfo.filename.endswith("/"):
                    continue

                filename = zinfo.filename
                scanned_files += 1
                _, ext_lower = os.path.splitext(filename)
                ext_lower = ext_lower.lower()

                # 2. Tier 1: Binary & Magic Byte Scan (Streamed chunk)
                with z.open(zinfo, "r") as file_stream:
                    binary_violation = check_file_stream_for_magic(
                        stream=file_stream,
                        filename=filename,
                        rules=self.config.binary_rules,
                    )
                    if binary_violation:
                        violations.append(
                            ScanViolation(
                                file_path=filename,
                                rule_type="ConsoleROMHeader",
                                message=binary_violation.reason,
                            )
                        )
                        # Hard binary violations immediately classify as REJECT
                        continue

                # 3. Tier 2: Perceptual Image Hashing (PNG, BMP, JPG, WEBP, TGA, RGBA, RGB)
                parsed_img = None
                if ext_lower in IMAGE_EXTENSIONS or ext_lower in RAW_TEXTURE_EXTENSIONS:
                    try:
                        with z.open(zinfo, "r") as img_stream:
                            raw_data = img_stream.read()
                            parsed_img = _parse_image_from_bytes(raw_data, ext_lower)
                            if parsed_img is not None:
                                _evaluate_image_against_reference_db(parsed_img, filename, self, violations, flags)
                    except Exception as e:
                        logger.debug(f"Could not parse image {filename}: {e}")

                # 5. Embedded Image scanning in Binary Container packages (.pack, .dat, .pak, .fsys, etc.)
                elif ext_lower in CONTAINER_PACKAGE_EXTENSIONS:
                    try:
                        with z.open(zinfo, "r") as pkg_stream:
                            raw_pkg_data = pkg_stream.read()
                            embedded_pngs = _extract_embedded_pngs(raw_pkg_data)
                            for offset, emb_img in embedded_pngs:
                                _evaluate_image_against_reference_db(
                                    emb_img,
                                    f"{filename} [embedded PNG @ 0x{offset:X}]",
                                    self,
                                    violations,
                                    flags,
                                )
                    except Exception as e:
                        logger.debug(f"Could not parse binary package {filename}: {e}")

        finally:
            z.close()

        elapsed = round(time.time() - start_time, 3)

        if violations:
            return ScanResult(
                status="REJECT",
                summary=f"Found {len(violations)} prohibited asset/ROM violation(s)",
                scanned_file_count=scanned_files,
                elapsed_seconds=elapsed,
                violations=violations,
                flags=flags,
            )
        elif flags:
            return ScanResult(
                status="FLAGGED",
                summary=f"Found {len(flags)} asset(s) with high similarity needing moderator review",
                scanned_file_count=scanned_files,
                elapsed_seconds=elapsed,
                violations=violations,
                flags=flags,
            )
        else:
            return ScanResult(
                status="CLEAN",
                summary=f"Scan complete: {scanned_files} files checked, no violations found.",
                scanned_file_count=scanned_files,
                elapsed_seconds=elapsed,
                violations=[],
                flags=[],
            )

    def scan_directory_sync(self, dir_path: str | os.PathLike) -> ScanResult:
        """
        Synchronously scans an uncompressed project directory/working tree
        through Tier 1 (Binary/ROM headers) and Tier 2 (Perceptual Image Hashing).
        """
        start_time = time.time()
        violations: List[ScanViolation] = []
        flags: List[ScanFlag] = []
        root_path = Path(dir_path).resolve()

        if not root_path.exists() or not root_path.is_dir():
            return ScanResult(
                status="REJECT",
                summary=f"Target directory not found: {dir_path}",
                scanned_file_count=0,
                elapsed_seconds=round(time.time() - start_time, 3),
                violations=[ScanViolation(file_path=str(dir_path), rule_type="FileSystem", message="Directory does not exist")],
            )

        ignored_dir_names = {
            ".git", ".github", ".venv", "venv", "env", "node_modules",
            "__pycache__", ".pytest_cache", ".cache", "scan_previews", "dist", "build"
        }

        scanned_files = 0

        for root, dirs, files in os.walk(root_path):
            # Exclude ignored directories in-place
            dirs[:] = [d for d in dirs if d not in ignored_dir_names and not d.startswith(".")]

            for file in files:
                if file.startswith("."):
                    continue

                abs_file_path = Path(root) / file
                rel_path = str(abs_file_path.relative_to(root_path))
                scanned_files += 1
                _, ext_lower = os.path.splitext(file)
                ext_lower = ext_lower.lower()

                # 1. Tier 1: Binary & Magic Byte Scan
                try:
                    with open(abs_file_path, "rb") as file_stream:
                        binary_violation = check_file_stream_for_magic(
                            stream=file_stream,
                            filename=rel_path,
                            rules=self.config.binary_rules,
                        )
                        if binary_violation:
                            violations.append(
                                ScanViolation(
                                    file_path=rel_path,
                                    rule_type="ConsoleROMHeader",
                                    message=binary_violation.reason,
                                )
                            )
                            continue
                except Exception as e:
                    logger.debug(f"Could not read file stream for {rel_path}: {e}")
                    continue

                # 2. Tier 2: Perceptual Image Hashing (PNG, BMP, JPG, WEBP, TGA, RGBA, RGB)
                if ext_lower in IMAGE_EXTENSIONS or ext_lower in RAW_TEXTURE_EXTENSIONS:
                    try:
                        with open(abs_file_path, "rb") as img_stream:
                            raw_data = img_stream.read()
                            parsed_img = _parse_image_from_bytes(raw_data, ext_lower)
                            if parsed_img is not None:
                                _evaluate_image_against_reference_db(parsed_img, rel_path, self, violations, flags)
                    except Exception as e:
                        logger.debug(f"Could not parse image {rel_path}: {e}")

                # 4. Embedded Image scanning in Binary Container packages
                elif ext_lower in CONTAINER_PACKAGE_EXTENSIONS:
                    try:
                        with open(abs_file_path, "rb") as pkg_stream:
                            raw_pkg_data = pkg_stream.read()
                            embedded_pngs = _extract_embedded_pngs(raw_pkg_data)
                            for offset, emb_img in embedded_pngs:
                                _evaluate_image_against_reference_db(
                                    emb_img,
                                    f"{rel_path} [embedded PNG @ 0x{offset:X}]",
                                    self,
                                    violations,
                                    flags,
                                )
                    except Exception as e:
                        logger.debug(f"Could not parse binary package {rel_path}: {e}")

        elapsed = round(time.time() - start_time, 3)

        if violations:
            return ScanResult(
                status="REJECT",
                summary=f"Found {len(violations)} prohibited asset/ROM violation(s)",
                scanned_file_count=scanned_files,
                elapsed_seconds=elapsed,
                violations=violations,
                flags=flags,
            )
        elif flags:
            return ScanResult(
                status="FLAGGED",
                summary=f"Found {len(flags)} asset(s) with high similarity needing moderator review",
                scanned_file_count=scanned_files,
                elapsed_seconds=elapsed,
                violations=violations,
                flags=flags,
            )
        else:
            return ScanResult(
                status="CLEAN",
                summary=f"Scan complete: {scanned_files} files checked, no violations found.",
                scanned_file_count=scanned_files,
                elapsed_seconds=elapsed,
                violations=[],
                flags=[],
            )

    def scan_target_sync(self, target: str | os.PathLike | bytes | BinaryIO) -> ScanResult:
        """
        Scans a target, automatically detecting whether it is a directory path,
        a zip archive path, a byte string, or a file-like stream.
        """
        if isinstance(target, (str, os.PathLike)):
            p = Path(target)
            if p.is_dir():
                return self.scan_directory_sync(p)
            return self.scan_archive_sync(p)
        return self.scan_archive_sync(target)
