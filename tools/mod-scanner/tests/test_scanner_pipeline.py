import io
import tempfile
import zipfile
from pathlib import Path
import pytest
from PIL import Image, ImageDraw
from mod_scanner.config import Config
from mod_scanner.core.image_scanner import compute_image_hash
from mod_scanner.pret_fetcher import ReferenceDatabase
from mod_scanner.scanner import ModScanner, WhitelistManager


def create_test_image(color=(100, 150, 200)) -> bytes:
    img = Image.new("RGBA", (56, 56), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((8, 8, 48, 48), fill=color, outline=(0, 0, 0, 255))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def mock_scanner(tmp_path):
    config = Config.from_file("config.yaml")
    config.paths.cache_dir = tmp_path / ".cache"
    config.paths.whitelist_file = tmp_path / "whitelist.json"

    # Setup mock reference database
    ref_img_data = create_test_image(color=(255, 0, 0))
    ref_img = Image.open(io.BytesIO(ref_img_data))
    ref_hash = compute_image_hash(ref_img, hash_size=16)

    ref_images_dir = tmp_path / ".cache" / "reference_images"
    ref_images_dir.mkdir(parents=True, exist_ok=True)
    (ref_images_dir / "pokered" / "gfx" / "pokemon").mkdir(parents=True, exist_ok=True)
    ref_img.save(ref_images_dir / "pokered" / "gfx" / "pokemon" / "bulbasaur.png")

    ref_db = ReferenceDatabase(
        hashes={"pokered/gfx/pokemon/bulbasaur.png": ref_hash},
        image_dir=ref_images_dir
    )

    return ModScanner(config=config, ref_db=ref_db)


def test_pipeline_clean_mod(mock_scanner):
    # Zip with unrelated custom art (e.g. square) and clean text
    square_img = Image.new("RGBA", (56, 56), (0, 0, 0, 0))
    draw = ImageDraw.Draw(square_img)
    draw.rectangle((5, 5, 50, 50), fill=(0, 255, 0, 255))
    img_buf = io.BytesIO()
    square_img.save(img_buf, format="PNG")

    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, "w") as z:
        z.writestr("README.md", b"# Custom Mod")
        z.writestr("textures/custom_block.png", img_buf.getvalue())

    result = mock_scanner.scan_archive_sync(zip_buf.getvalue())
    assert result.is_clean
    assert result.status == "CLEAN"


def test_pipeline_reject_rom_header(mock_scanner):
    # Zip containing file with GBA Nintendo logo header
    header = bytearray(512)
    gba_logo = bytes.fromhex("24ffae51699aa2213d84820a84e409ad")
    header[0x0004 : 0x0004 + len(gba_logo)] = gba_logo

    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, "w") as z:
        z.writestr("assets/game_core.bin", bytes(header))

    result = mock_scanner.scan_archive_sync(zip_buf.getvalue())
    assert result.is_rejected
    assert any("GBA" in v.message for v in result.violations)


def test_pipeline_reject_direct_asset_rip(mock_scanner):
    # Exact recolor of reference bulbasaur
    rip_data = create_test_image(color=(0, 0, 255))  # Same shape, blue

    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, "w") as z:
        z.writestr("gfx/bulbasaur_shiny.png", rip_data)

    result = mock_scanner.scan_archive_sync(zip_buf.getvalue())
    assert result.is_rejected
    assert any("bulbasaur.png" in v.message for v in result.violations)


def test_whitelist_allows_previously_flagged(mock_scanner):
    rip_data = create_test_image(color=(0, 0, 255))
    img = Image.open(io.BytesIO(rip_data))
    img_hash = compute_image_hash(img, hash_size=16)

    # Approve hash into whitelist
    mock_scanner.whitelist.approve(img_hash)

    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, "w") as z:
        z.writestr("gfx/bulbasaur_shiny.png", rip_data)

    result = mock_scanner.scan_archive_sync(zip_buf.getvalue())
    assert result.is_clean


def test_pipeline_directory_scan_clean(mock_scanner, tmp_path):
    mod_dir = tmp_path / "clean_mod_repo"
    mod_dir.mkdir()
    (mod_dir / "textures").mkdir()
    (mod_dir / "README.md").write_text("# My Clean Mod")

    square_img = Image.new("RGBA", (56, 56), (0, 0, 0, 0))
    draw = ImageDraw.Draw(square_img)
    draw.rectangle((5, 5, 50, 50), fill=(0, 255, 0, 255))
    square_img.save(mod_dir / "textures" / "custom_block.png")

    result = mock_scanner.scan_directory_sync(mod_dir)
    assert result.is_clean
    assert result.scanned_file_count == 2


def test_pipeline_directory_scan_reject(mock_scanner, tmp_path):
    mod_dir = tmp_path / "violation_mod_repo"
    mod_dir.mkdir()
    (mod_dir / "roms").mkdir()

    header = bytearray(512)
    gba_logo = bytes.fromhex("24ffae51699aa2213d84820a84e409ad")
    header[0x0004 : 0x0004 + len(gba_logo)] = gba_logo
    (mod_dir / "roms" / "game.bin").write_bytes(bytes(header))

    result = mock_scanner.scan_directory_sync(mod_dir)
    assert result.is_rejected
    assert len(result.violations) == 1


def test_scan_target_sync_dispatch(mock_scanner, tmp_path):
    # Test dispatch on directory
    mod_dir = tmp_path / "dispatch_dir"
    mod_dir.mkdir()
    (mod_dir / "test.txt").write_text("hello")
    res_dir = mock_scanner.scan_target_sync(mod_dir)
    assert res_dir.is_clean

    # Test dispatch on zip
    zip_path = tmp_path / "dispatch.zip"
    with zipfile.ZipFile(zip_path, "w") as z:
        z.writestr("test.txt", b"hello")
    res_zip = mock_scanner.scan_target_sync(zip_path)
    assert res_zip.is_clean


def test_pipeline_raw_rgba_texture_scan(mock_scanner):
    # Direct rip rendered as raw RGBA buffer (56x56 = 3136 pixels * 4 = 12544 bytes)
    rip_png = create_test_image(color=(0, 0, 255))
    img = Image.open(io.BytesIO(rip_png))
    raw_rgba_data = img.tobytes("raw", "RGBA")

    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, "w") as z:
        z.writestr("textures/bulbasaur.rgba", raw_rgba_data)

    result = mock_scanner.scan_archive_sync(zip_buf.getvalue())
    assert result.is_rejected
    assert any("bulbasaur.png" in v.message for v in result.violations)


def test_pipeline_importer_scripts_allowed(mock_scanner):
    # Importer script that guides extraction from user-provided ROM/ISO
    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, "w") as z:
        z.writestr(
            "portrait_bounds.lua",
            b"-- Reference to GC6E01 poke_face.fsys extraction table\nreturn {['assets/portraits/001.png']={0,0,42,42}}"
        )
        z.writestr("manifest.json", '{"target_game": "Pokémon Colosseum (GameCube)", "game_id": "GC6E01"}'.encode("utf-8"))

    result = mock_scanner.scan_archive_sync(zip_buf.getvalue())
    assert result.is_clean
    assert result.status == "CLEAN"





