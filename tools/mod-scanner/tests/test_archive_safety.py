import io
import zipfile
import pytest
from mod_scanner.config import ArchiveConfig
from mod_scanner.core.archive import (
    open_safe_zip,
    ArchiveSecurityError,
    ZipBombError,
    PathTraversalError,
    validate_archive_metadata,
)


def create_mock_zip(files: dict) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr(name, data)
    return buf.getvalue()


def test_safe_zip_passes():
    config = ArchiveConfig(max_unpacked_size_mb=10, max_file_count=100, max_compression_ratio=20.0)
    data = create_mock_zip({"mod.txt": b"Hello world! This is a clean mod text file."})
    z = open_safe_zip(data, config)
    assert len(z.namelist()) == 1
    z.close()


def test_zip_bomb_compression_ratio_rejected():
    config = ArchiveConfig(max_unpacked_size_mb=100, max_file_count=100, max_compression_ratio=20.0)
    # Highly compressible sequence of zeroes > 5MB
    huge_zeroes = b"\x00" * (6 * 1024 * 1024)  # 6MB of zeroes compresses to ~6KB (>1000:1 ratio)
    data = create_mock_zip({"bomb.dat": huge_zeroes})

    with pytest.raises(ZipBombError) as exc_info:
        open_safe_zip(data, config)
    assert "exceeding max allowable ratio" in str(exc_info.value)


def test_max_unpacked_size_rejected():
    config = ArchiveConfig(max_unpacked_size_mb=1, max_file_count=100, max_compression_ratio=1000.0)
    # 2MB of non-zero data
    content = bytes(range(256)) * (8 * 1024)  # 2MB
    data = create_mock_zip({"large.dat": content})

    with pytest.raises(ArchiveSecurityError) as exc_info:
        open_safe_zip(data, config)
    assert "Archive uncompressed size exceeds limit" in str(exc_info.value)


def test_path_traversal_rejected():
    config = ArchiveConfig(max_unpacked_size_mb=10, max_file_count=100, max_compression_ratio=20.0)
    data = create_mock_zip({"../malicious.sh": b"echo 'pwned'"})

    with pytest.raises(PathTraversalError):
        open_safe_zip(data, config)
