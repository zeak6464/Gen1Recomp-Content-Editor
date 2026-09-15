import io
import pytest
from mod_scanner.config import Config
from mod_scanner.core.binary_scanner import check_file_stream_for_magic


@pytest.fixture
def binary_rules():
    config = Config.from_file("config.yaml")
    return config.binary_rules


def test_blacklisted_extension_detected(binary_rules):
    stream = io.BytesIO(b"dummy")
    violation = check_file_stream_for_magic(stream, "roms/pokemon_fire.gba", binary_rules)
    assert violation is not None
    assert "prohibited console ROM/container extension" in violation.reason


def test_gb_nintendo_logo_detected(binary_rules):
    # GB Nintendo logo at 0x0104
    header = bytearray(512)
    logo_bytes = bytes.fromhex("ceed6666cc0d000b03730083000c000d0008111f8889000eaccf")
    header[0x0104 : 0x0104 + len(logo_bytes)] = logo_bytes

    stream = io.BytesIO(header)
    violation = check_file_stream_for_magic(stream, "renamed_data.bin", binary_rules)
    assert violation is not None
    assert "Game Boy" in violation.rule_name


def test_gba_logo_header_detected(binary_rules):
    # GBA Nintendo logo header at 0x0004
    header = bytearray(512)
    gba_logo = bytes.fromhex("24ffae51699aa2213d84820a84e409ad")
    header[0x0004 : 0x0004 + len(gba_logo)] = gba_logo

    stream = io.BytesIO(header)
    violation = check_file_stream_for_magic(stream, "asset.dat", binary_rules)
    assert violation is not None
    assert "GBA" in violation.rule_name


def test_contained_signature_detected(binary_rules):
    # Embedded 3DS bcres package in custom binary file
    payload = b"RPII1\x00\x00\x00\x98\x00\x00\x000\x00\x00\x00AABO.bcres.cx\x00\x00"
    stream = io.BytesIO(payload)
    violation = check_file_stream_for_magic(stream, "assets/rumble_pii.pack", binary_rules)
    assert violation is not None
    assert "bcres" in violation.rule_name


def test_n64_magic_detected(binary_rules):
    # N64 big endian magic 0x80371240 at 0x0000
    header = bytearray(512)
    header[0:4] = bytes.fromhex("80371240")

    stream = io.BytesIO(header)
    violation = check_file_stream_for_magic(stream, "custom_level.bin", binary_rules)
    assert violation is not None
    assert "N64" in violation.rule_name


def test_switch_nsp_magic_detected(binary_rules):
    # Switch PFS0 at 0x0000
    header = bytearray(512)
    header[0:4] = b"PFS0"

    stream = io.BytesIO(header)
    violation = check_file_stream_for_magic(stream, "update.pkg", binary_rules)
    assert violation is not None
    assert "Nintendo Switch" in violation.rule_name


def test_native_executable_passes(binary_rules):
    # Native PC executable (MZ header / .exe) should not be blocked
    stream = io.BytesIO(b"MZ\x90\x00\x03\x00\x00\x00\x04\x00\x00\x00\xff\xff\x00\x00")
    violation = check_file_stream_for_magic(stream, "tools/launcher.exe", binary_rules)
    assert violation is None



def test_gamecube_fsys_detected(binary_rules):
    # GameCube Genius Sonority FSYS container
    stream = io.BytesIO(b"FSYS\x00\x00\x00\x20\x00\x00\x01\x00")
    violation = check_file_stream_for_magic(stream, "data/poke_face.bin", binary_rules)
    assert violation is not None
    assert "FSYS" in violation.rule_name


def test_gamecube_rarc_detected(binary_rules):
    # GameCube RARC archive
    stream = io.BytesIO(b"RARC\x00\x00\x00\x40\x00\x00\x00\x20")
    violation = check_file_stream_for_magic(stream, "stage/arena.bin", binary_rules)
    assert violation is not None
    assert "RARC" in violation.rule_name


def test_rvz_disc_container_detected(binary_rules):
    # Dolphin RVZ disc container (RVZ\x01)
    stream = io.BytesIO(b"RVZ\x01\x00\x00\x00\x20\x00\x00\x00\x00")
    violation = check_file_stream_for_magic(stream, "disc_backup.dat", binary_rules)
    assert violation is not None
    assert "RVZ" in violation.rule_name


def test_wbfs_disc_container_detected(binary_rules):
    # Wii WBFS disc container (WBFS)
    stream = io.BytesIO(b"WBFS\x00\x00\x00\x01\x00\x00\x00\x00")
    violation = check_file_stream_for_magic(stream, "game_backup.bin", binary_rules)
    assert violation is not None
    assert "WBFS" in violation.rule_name


def test_nes_rom_header_detected(binary_rules):
    # NES ROM header (NES\x1A)
    stream = io.BytesIO(b"NES\x1a\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00")
    violation = check_file_stream_for_magic(stream, "classic_game.bin", binary_rules)
    assert violation is not None
    assert "NES" in violation.rule_name


def test_nkit_recovery_signature_detected(binary_rules):
    # NKit recovery data signature embedded in package
    payload = b"\x00" * 32 + b"NKIT\x00\x01" + b"\x00" * 32
    stream = io.BytesIO(payload)
    violation = check_file_stream_for_magic(stream, "assets/disc_patch.pack", binary_rules)
    assert violation is not None
    assert "NKit" in violation.rule_name


def test_clean_file_passes(binary_rules):
    stream = io.BytesIO(b"This is completely clean text or JSON configuration data.")
    violation = check_file_stream_for_magic(stream, "config.json", binary_rules)
    assert violation is None


