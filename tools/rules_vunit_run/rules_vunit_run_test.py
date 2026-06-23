"""Unit tests for the default VUnit driver `rules_vunit_run`.

Focuses on the manifest plumbing that drives `add_source_file` — in
particular the `verilog_include_dirs` flow, since regressions there
are hard to spot until a SV-using test fails at compile with `Cannot
open file vunit_defines.svh`. Existing CI doesn't ship a
SV-capable simulator, so the round-trip is tested at the
manifest-deserialise + `vunit_builtin_verilog_include_dir` layers.
"""

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict

import vunit.builtins as vunit_builtins  # type: ignore[import-untyped]
from rules_vunit_run import (
    ensure_vunit_verilog_path_is_plus_free,
    load_manifest,
    vunit_builtin_verilog_include_dir,
)


class LoadManifestTests(unittest.TestCase):
    """`load_manifest` round-trips the manifest schema."""

    def setUp(self) -> None:
        # pylint: disable-next=consider-using-with
        self.tmpdir = Path(self.enterContext(tempfile.TemporaryDirectory()))

    def _write(self, payload: Dict[str, Any]) -> Path:
        path = self.tmpdir / "libraries.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_schema_round_trip(self) -> None:
        """The full manifest schema (sources + per-language include
        dirs) round-trips through `load_manifest`."""
        path = self._write(
            {
                "work": {
                    "vhdl_sources": ["a.vhd"],
                    "verilog_sources": ["tb.sv"],
                    "verilog_include_dirs": [
                        "external/somepkg/include",
                        "fpga/cores/x/hdrs",
                    ],
                }
            }
        )
        manifest = load_manifest(path)

        entry = manifest["work"]
        self.assertEqual([str(p) for p in entry.vhdl_sources], ["a.vhd"])
        self.assertEqual([str(p) for p in entry.verilog_sources], ["tb.sv"])
        self.assertEqual(
            list(entry.verilog_include_dirs),
            ["external/somepkg/include", "fpga/cores/x/hdrs"],
        )

    def test_multiple_libraries_have_independent_include_dirs(self) -> None:
        """Each library's include set is independent — VUnit's
        `add_source_file` is per-library, so propagating one library's
        headers to another's compile would let unrelated SV sources
        accidentally include each other's private headers."""
        path = self._write(
            {
                "lib_a": {
                    "vhdl_sources": [],
                    "verilog_sources": ["a.sv"],
                    "verilog_include_dirs": ["a_hdrs"],
                },
                "lib_b": {
                    "vhdl_sources": [],
                    "verilog_sources": ["b.sv"],
                    "verilog_include_dirs": ["b_hdrs"],
                },
            }
        )
        manifest = load_manifest(path)

        self.assertEqual(list(manifest["lib_a"].verilog_include_dirs), ["a_hdrs"])
        self.assertEqual(list(manifest["lib_b"].verilog_include_dirs), ["b_hdrs"])


class BuiltinIncludeDirTests(unittest.TestCase):
    """`vunit_builtin_verilog_include_dir` resolves to a real path
    that contains `vunit_defines.svh`, and
    `ensure_vunit_verilog_path_is_plus_free` strips `+` from the
    Bazel bzlmod runfiles prefix before Aldec vlog sees it.

    The dcmac test failure mode that motivated this work was
    `VCP1000 Cannot open file vunit_defines.svh` — verify our auto-
    discovery actually points at the right file."""

    def setUp(self) -> None:
        # Snapshot VERILOG_PATH so each test sees an independent
        # starting state — the helper mutates this module-global, and
        # without restoration tests would be order-dependent.
        self._original_verilog_path = vunit_builtins.VERILOG_PATH
        self.addCleanup(setattr, vunit_builtins, "VERILOG_PATH", self._original_verilog_path)
        # pylint: disable-next=consider-using-with
        self._tmpdir = Path(self.enterContext(tempfile.TemporaryDirectory()))

    def _stage_fixture(self, *, with_plus: bool) -> Path:
        """Symlink-fixture pointing at the real verilog dir, with or
        without a `+` in the parent path. Sets `VERILOG_PATH` and
        returns the fixture path so the test can assert against it."""
        parent = self._tmpdir / ("with+plus" if with_plus else "no_plus")
        parent.mkdir()
        fixture = parent / "verilog"
        fixture.symlink_to(self._original_verilog_path)
        vunit_builtins.VERILOG_PATH = fixture
        return fixture

    def test_points_at_vunit_defines_svh(self) -> None:
        """The path must exist and contain `vunit_defines.svh` so
        every user SV file that includes `vunit_defines.svh`
        resolves it without a per-test include_dirs setting."""
        include_dir = vunit_builtin_verilog_include_dir()
        self.assertTrue(
            include_dir.is_dir(),
            f"VUnit builtin include dir does not exist: {include_dir}",
        )
        self.assertTrue(
            (include_dir / "vunit_defines.svh").is_file(),
            f"vunit_defines.svh not at expected location: {include_dir}",
        )

    def test_staging_strips_plus_from_synthetic_path(self) -> None:
        """A `+`-containing fixture exercises the staging code path
        regardless of where the host vunit_hdl install lives, so the
        assertion can't pass vacuously."""
        self._stage_fixture(with_plus=True)

        ensure_vunit_verilog_path_is_plus_free()

        include_dir = vunit_builtin_verilog_include_dir()
        self.assertNotIn("+", str(include_dir))
        self.assertTrue(include_dir.is_dir())

    def test_staging_noop_when_input_is_plus_free(self) -> None:
        """When VERILOG_PATH has no `+`, the helper short-circuits and
        leaves the module global unchanged."""
        fixture = self._stage_fixture(with_plus=False)

        ensure_vunit_verilog_path_is_plus_free()

        self.assertEqual(vunit_builtins.VERILOG_PATH, fixture)

    def test_staging_is_idempotent(self) -> None:
        """Repeated calls return the same staged path — the second
        call sees the already-rebound `+`-free value and short-
        circuits."""
        self._stage_fixture(with_plus=True)

        ensure_vunit_verilog_path_is_plus_free()
        first = vunit_builtins.VERILOG_PATH
        ensure_vunit_verilog_path_is_plus_free()
        second = vunit_builtins.VERILOG_PATH

        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
