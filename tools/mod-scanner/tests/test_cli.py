import os
from pathlib import Path
import pytest
from mod_scanner.cli import write_github_actions_outputs, format_status_badge
from mod_scanner.scanner import ScanResult, ScanViolation, ScanFlag


def test_format_status_badge():
    assert "CLEAN" in format_status_badge("CLEAN")
    assert "FLAGGED" in format_status_badge("FLAGGED")
    assert "REJECT" in format_status_badge("REJECT")


def test_write_github_actions_outputs(tmp_path, monkeypatch):
    summary_file = tmp_path / "step_summary.md"
    output_file = tmp_path / "github_output.txt"

    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary_file))
    monkeypatch.setenv("GITHUB_OUTPUT", str(output_file))

    res = ScanResult(
        status="FLAGGED",
        summary="1 asset flagged for review",
        scanned_file_count=15,
        elapsed_seconds=0.12,
        violations=[ScanViolation(file_path="bad.bin", rule_type="ConsoleROMHeader", message="Found ROM header")],
        flags=[ScanFlag(file_path="test.png", matched_ref="ref.png", hamming_distance=10, mod_hash="abc", ref_hash="def")]
    )

    dummy_preview = tmp_path / "diff_001_test.png"
    dummy_preview.write_text("fake png")

    write_github_actions_outputs(res, "my-mod.zip", [dummy_preview])

    # Check step summary
    summary_content = summary_file.read_text()
    assert "Mod Scanner Report" in summary_content
    assert "FLAGGED FOR REVIEW" in summary_content
    assert "bad.bin" in summary_content
    assert "test.png" in summary_content
    assert "Diff Previews Generated" in summary_content

    # Check outputs
    output_content = output_file.read_text()
    assert "verdict=FLAGGED" in output_content
    assert "scanned-count=15" in output_content
    assert "violations-count=1" in output_content
    assert "flags-count=1" in output_content
