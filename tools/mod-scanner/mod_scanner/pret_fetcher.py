"""
Automated streaming fetcher and indexer for upstream pret/decomp assets.
"""

from __future__ import annotations

import fnmatch
import json
import logging
import os
import shutil
import tarfile
import tempfile
import time
from pathlib import Path
from typing import Dict, Optional, Tuple
from PIL import Image
import requests

from .config import Config, PretSource
from .core.image_scanner import compute_image_hash

logger = logging.getLogger("mod_scanner.pret_fetcher")


class ReferenceDatabase:
    """
    In-memory reference database holding 256-bit perceptual hashes and local thumbnail paths.
    """
    def __init__(self, hashes: Dict[str, str], image_dir: Path):
        self.hashes: Dict[str, str] = hashes  # { "pokered/gfx/pokemon/front/bulbasaur.png": "hex_hash" }
        self.image_dir: Path = image_dir

    def get_reference_image(self, ref_key: str) -> Optional[Image.Image]:
        """Loads a cached reference image from the local filesystem."""
        img_path = self.image_dir / ref_key
        if img_path.exists():
            try:
                return Image.open(img_path).copy()
            except Exception as e:
                logger.warning(f"Failed to open cached reference image {img_path}: {e}")
        return None


def fetch_pret_source_to_temp_file(
    source: PretSource,
    github_token: str = "",
    timeout: int = 60
) -> Path:
    """
    Streams the tarball archive from GitHub to a temporary file on disk.
    Avoids loading full archives into RAM.
    """
    url = f"https://github.com/{source.repo}/archive/refs/heads/{source.branch}.tar.gz"
    headers = {"User-Agent": "mod-scanner/0.1"}
    if github_token:
        headers["Authorization"] = f"Bearer {github_token}"

    logger.info(f"Downloading {source.name} from {url}...")
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".tar.gz")
    temp_path = Path(temp_file.name)

    try:
        with requests.get(url, headers=headers, stream=True, timeout=timeout) as response:
            if response.status_code == 404:
                # Try 'main' branch if 'master' returned 404
                alt_url = f"https://github.com/{source.repo}/archive/refs/heads/main.tar.gz"
                logger.info(f"Branch '{source.branch}' 404'd, trying 'main' branch...")
                with requests.get(alt_url, headers=headers, stream=True, timeout=timeout) as alt_resp:
                    alt_resp.raise_for_status()
                    for chunk in alt_resp.iter_content(chunk_size=1024 * 64):
                        if chunk:
                            temp_file.write(chunk)
            else:
                response.raise_for_status()
                for chunk in response.iter_content(chunk_size=1024 * 64):
                    if chunk:
                        temp_file.write(chunk)
    except Exception as e:
        temp_file.close()
        if temp_path.exists():
            temp_path.unlink()
        raise RuntimeError(f"Failed to stream archive for {source.repo}: {e}")
    finally:
        temp_file.close()

    return temp_path


def index_pret_archive(
    source: PretSource,
    tar_path: Path,
    image_rules_config,
    output_image_dir: Path
) -> Dict[str, str]:
    """
    Scans a downloaded tarball, extracts matching PNGs, computes 256-bit dHash,
    and caches copies of the images to output_image_dir.
    """
    indexed_hashes: Dict[str, str] = {}

    with tarfile.open(tar_path, "r:gz") as tar:
        for member in tar.getmembers():
            if not member.isfile() or not member.name.lower().endswith(".png"):
                continue

            # Strip leading top-level folder (e.g. "pokered-master/gfx/..." -> "gfx/...")
            parts = Path(member.name).parts
            if len(parts) <= 1:
                continue
            relative_path = str(Path(*parts[1:]))

            # Match against configured patterns
            matches_pattern = any(
                fnmatch.fnmatch(relative_path, pat) or fnmatch.fnmatch(member.name, pat)
                for pat in source.image_patterns
            )
            if not matches_pattern:
                continue

            # Read image directly from tar member
            f = tar.extractfile(member)
            if f is None:
                continue

            try:
                img = Image.open(f)
                img.load()  # Force load into memory before closing f

                # Filter out tiny icon slices (< 16x16) and solid single-color blank strips
                if img.width < 16 or img.height < 16:
                    continue
                extrema = img.convert("L").getextrema()
                if extrema[0] == extrema[1]:
                    continue

                h_str = compute_image_hash(
                    img,
                    hash_size=image_rules_config.hash_size,
                    hash_type=image_rules_config.hash_type
                )
                ref_key = f"{source.name}/{relative_path}"
                indexed_hashes[ref_key] = h_str

                # Cache reference image thumbnail for 3-panel diff generation
                dest_file = output_image_dir / ref_key
                dest_file.parent.mkdir(parents=True, exist_ok=True)
                img.save(dest_file, format="PNG")
            except Exception as e:
                logger.debug(f"Skipping unreadable PNG '{member.name}': {e}")

    return indexed_hashes


def load_or_fetch_reference_database(
    config: Config,
    force_refresh: bool = False
) -> ReferenceDatabase:
    """
    Loads reference hashes from .cache/reference_hashes.json if available.
    If missing or force_refresh is True, downloads the configured pret repositories,
    indexes their PNGs, and writes the cache.
    """
    cache_file = config.paths.reference_hashes_file
    images_dir = config.paths.reference_images_dir

    if not force_refresh and cache_file.exists():
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            hashes = data.get("hashes", {})
            logger.info(f"Loaded {len(hashes)} cached reference hashes from {cache_file}")
            return ReferenceDatabase(hashes=hashes, image_dir=images_dir)
        except Exception as e:
            logger.warning(f"Failed to read cache {cache_file}, rebuilding: {e}")

    config.paths.cache_dir.mkdir(parents=True, exist_ok=True)
    images_dir.mkdir(parents=True, exist_ok=True)

    all_hashes: Dict[str, str] = {}

    for source in config.pret_sources:
        if not source.repo:
            continue
        logger.info(f"Fetching reference assets for '{source.name}' ({source.repo})...")
        temp_tar = None
        try:
            temp_tar = fetch_pret_source_to_temp_file(source, github_token=config.github_token)
            source_hashes = index_pret_archive(
                source=source,
                tar_path=temp_tar,
                image_rules_config=config.image_rules,
                output_image_dir=images_dir
            )
            logger.info(f"Indexed {len(source_hashes)} images from {source.name}")
            all_hashes.update(source_hashes)
        except Exception as e:
            logger.error(f"Error fetching pret source {source.name}: {e}")
        finally:
            if temp_tar and temp_tar.exists():
                try:
                    temp_tar.unlink()
                except Exception:
                    pass

    # Save cache
    cache_payload = {
        "version": 1,
        "last_updated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "total_hashes": len(all_hashes),
        "hashes": all_hashes,
    }
    with open(cache_file, "w", encoding="utf-8") as f:
        json.dump(cache_payload, f, indent=2)

    logger.info(f"Successfully cached {len(all_hashes)} reference hashes to {cache_file}")
    return ReferenceDatabase(hashes=all_hashes, image_dir=images_dir)
