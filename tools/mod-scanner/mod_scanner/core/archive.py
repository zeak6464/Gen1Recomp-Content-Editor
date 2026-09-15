"""
Archive safety, zip bomb defense, and path traversal validation.
"""

from __future__ import annotations

import io
import os
import zipfile
from typing import BinaryIO, List, Tuple
from ..config import ArchiveConfig


class ArchiveSecurityError(Exception):
    """Raised when an archive violates safety or size constraints."""
    pass


class ZipBombError(ArchiveSecurityError):
    """Raised when an archive exceeds the maximum safe compression ratio."""
    pass


class PathTraversalError(ArchiveSecurityError):
    """Raised when an archive attempts directory traversal or dangerous filenames."""
    pass


def validate_archive_metadata(
    z: zipfile.ZipFile,
    config: ArchiveConfig
) -> Tuple[int, int]:
    """
    Inspects zip file metadata BEFORE decompressing file contents.
    Validates:
      1. File count limits
      2. Max compression ratio (zip bomb defense)
      3. Total unpacked size limits
      4. Path traversal / ZipSlip security

    Returns:
      Tuple of (total_file_count, total_unpacked_bytes)
    """
    total_unpacked_bytes = 0
    infolist = z.infolist()
    file_count = len(infolist)

    if file_count > config.max_file_count:
        raise ArchiveSecurityError(
            f"Archive exceeds maximum file count limit ({file_count} > {config.max_file_count})"
        )

    for zinfo in infolist:
        # 1. Path traversal check (ZipSlip)
        norm_name = os.path.normpath(zinfo.filename)
        if norm_name.startswith("..") or os.path.isabs(norm_name) or norm_name.startswith("/") or norm_name.startswith("\\"):
            raise PathTraversalError(
                f"Suspicious path detected in archive: '{zinfo.filename}'"
            )

        # 2. Skip directory records for size / ratio calculations
        if zinfo.is_dir() or zinfo.filename.endswith("/"):
            continue

        # 3. Compression ratio pre-calculation check
        # Real zip bombs attempt to expand into gigabytes. Files smaller than 5MB
        # (such as repetitive JSON data or source files) pose no memory exhaustion risk.
        min_size_for_ratio_check = 5 * 1024 * 1024  # 5 MB
        if zinfo.file_size > min_size_for_ratio_check and zinfo.compress_size > 0:
            ratio = zinfo.file_size / zinfo.compress_size
            if ratio > config.max_compression_ratio:
                raise ZipBombError(
                    f"Compression ratio for '{zinfo.filename}' is {ratio:.1f}:1 ({zinfo.file_size / (1024*1024):.1f} MB unpacked), "
                    f"exceeding max allowable ratio of {config.max_compression_ratio}:1"
                )

        total_unpacked_bytes += zinfo.file_size
        if total_unpacked_bytes > config.max_unpacked_size_bytes:
            raise ArchiveSecurityError(
                f"Archive uncompressed size exceeds limit ({total_unpacked_bytes / (1024*1024):.1f} MB > "
                f"{config.max_unpacked_size_mb} MB)"
            )

    return file_count, total_unpacked_bytes


def open_safe_zip(
    source: str | os.PathLike | bytes | BinaryIO,
    config: ArchiveConfig
) -> zipfile.ZipFile:
    """
    Opens a zip archive and immediately enforces metadata security rules.
    """
    if isinstance(source, (bytes, bytearray)):
        file_obj = io.BytesIO(source)
    else:
        file_obj = source

    try:
        z = zipfile.ZipFile(file_obj, "r")
    except zipfile.BadZipFile as e:
        raise ArchiveSecurityError(f"Invalid or corrupted zip archive: {e}")

    validate_archive_metadata(z, config)
    return z
