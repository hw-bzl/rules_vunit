"""Default VUnit driver shipped with rules_vunit.

The `vunit_test` rule invokes this script via the process wrapper. Override
the toolchain's `run_py` attribute when you need custom orchestration
(per-test attributes, `set_sim_option(...)` calls, `post_run` hooks, ...).
Custom drivers can `from rules_vunit_run import load_manifest,
ensure_vunit_verilog_path_is_plus_free, vunit_builtin_verilog_include_dir,
configure_coverage` to reuse the default driver's plumbing instead of
vendoring it — add `@rules_vunit//tools/rules_vunit_run` to the
`vunit_test` deps.

Wrapper-supplied environment:
    VUNIT_LIBRARIES_JSON:        path to a `LibraryManifest` (see below) as JSON.
    VUNIT_OUTPUT_PATH:           output dir (forwarded as -o)
    VUNIT_XUNIT_XML:             xunit report path (forwarded as -x)
    VUNIT_PRECOMPILED_LIBS_JSON: optional path to a JSON describing precompiled
                                 library sets to link. Format:
                                 `[{"format": <name>, "vendor": <name>,
                                    "links_secureip": <bool>,
                                    "provides_glbl": <bool>,
                                    "library_dir": <path>}, ...]`.
                                 The default driver ignores it; consumers that
                                 need precompiled-library linking provide a
                                 `run.py` override that emits the simulator's
                                 link directive (e.g. `vmap -link` for Aldec)
                                 and acts on the typed ecosystem flags.
    VUNIT_COVERAGE:              "1" when `bazel coverage` is the invocation
                                 (gated by `ctx.coverage_instrumented()` on
                                 the `vunit_test` rule). The default driver
                                 applies any `set_sim_option` entries declared
                                 via `VUNIT_COVERAGE_SIM_OPTIONS` (see below)
                                 — dispatch is sim-agnostic.
    VUNIT_COVERAGE_SIM_OPTIONS:  JSON-encoded `{set_sim_option_key: value}`
                                 dict, populated by the active `vunit_*_sim`
                                 rule's `compile` function whenever
                                 `ctx.coverage_instrumented()` is True. Each
                                 entry is forwarded verbatim to
                                 `vu.set_sim_option(key, value)` so all
                                 simulator-specific knowledge stays in the
                                 sim integration, not in this script.
"""

import json
import os
import sys
import tempfile
from pathlib import Path
from typing import List, Mapping, NamedTuple, Sequence

import vunit.builtins as vunit_builtins  # type: ignore[import-untyped]
from vunit import VUnit


class LibraryEntry(NamedTuple):
    """Sources declared for a single VUnit library.

    `verilog_include_dirs` carries the SV `\\`include` search path
    sourced from `VerilogInfo.includes` (`verilog_library` populates
    it from `hdrs`' parent dirs plus the explicit `includes` attr).
    `add_verilog_builtins()` registers the builtin headers as source
    files but does not propagate their dir to user sources, so user
    SV that does `\\`include "vunit_defines.svh"` only resolves when
    we pass include_dirs explicitly to `add_source_file`.
    """

    vhdl_sources: Sequence[Path]
    verilog_sources: Sequence[Path]
    verilog_include_dirs: Sequence[str]


# The deserialised shape of `VUNIT_LIBRARIES_JSON`. Keep in sync with
# `_libraries_json_map_fn` in `//vunit/private/vunit_test.bzl`, which writes
# this manifest at action time.
LibraryManifest = Mapping[str, LibraryEntry]


def load_manifest(path: Path) -> LibraryManifest:
    """Deserialise the libraries descriptor written by the `vunit_test` rule."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {
        lib_name: LibraryEntry(
            vhdl_sources=[Path(p) for p in entry["vhdl_sources"]],
            verilog_sources=[Path(p) for p in entry["verilog_sources"]],
            verilog_include_dirs=list(entry["verilog_include_dirs"]),
        )
        for lib_name, entry in raw.items()
    }


def ensure_vunit_verilog_path_is_plus_free() -> None:
    """Rebind `vunit.builtins.VERILOG_PATH` to a `+`-free location.

    Aldec vlog treats `+` in `+incdir+...` as a list separator. Under
    bzlmod, VUnit's builtin include dir lives at
    `<runfiles>/+http_archive+vunit_hdl/vunit/verilog`, which vlog
    mis-parses and reports `VCP1000 Cannot open file vunit_defines.svh`.

    Stage a `+`-free symlink under `$TEST_TMPDIR` (or system tempdir)
    pointing at the original dir, then rebind the module constant to
    the symlink's `.absolute()` path — NOT `.resolve()`, which would
    follow back to the `+`-containing target. Idempotent: the second
    call sees no `+` and returns. Must run BEFORE
    `vu.add_verilog_builtins()`.
    """
    original = vunit_builtins.VERILOG_PATH
    if "+" not in str(original):
        return

    tmp_root = Path(os.environ.get("TEST_TMPDIR") or tempfile.gettempdir())
    sandbox = tmp_root / "vunit_clean_path"
    if "+" in str(sandbox):
        raise RuntimeError(
            f"Refusing to stage vunit builtins under a `+`-containing path: "
            f"{sandbox!s}. Set TEST_TMPDIR to a `+`-free directory."
        )
    sandbox.mkdir(parents=True, exist_ok=True)
    link = sandbox / "verilog"
    # Skip recreation when the symlink already points at `original`.
    # Otherwise unlink-then-recreate handles both the missing case and
    # the stale case (target moved across cache evictions or between
    # tests) — `Path.exists()` follows symlinks and can't distinguish
    # those, so a naive "skip if exists" would dangle.
    if not (link.is_symlink() and os.readlink(link) == str(original)):
        link.unlink(missing_ok=True)
        link.symlink_to(original)
    vunit_builtins.VERILOG_PATH = link.absolute()


def vunit_builtin_verilog_include_dir() -> Path:
    """Path containing VUnit's `vunit_defines.svh` macros.

    Reads the (possibly-staged) `vunit.builtins.VERILOG_PATH`. Call
    `ensure_vunit_verilog_path_is_plus_free` first so the path is
    guaranteed sandbox-safe AND `+`-free.
    """
    return Path(vunit_builtins.VERILOG_PATH) / "include"


def configure_coverage(vu: VUnit) -> None:
    """Apply simulator-supplied coverage options when ``VUNIT_COVERAGE=1``.

    Knowledge of how to enable coverage for a given simulator lives in
    that sim's ``compile`` function (in its ``vunit_*_sim`` rule). The
    integration declares the work as a JSON-encoded dict via the
    ``VUNIT_COVERAGE_SIM_OPTIONS`` env var, with two sub-dicts:

        {
          "compile_options": {"<key>": <value>, ...},
          "sim_options":     {"<key>": <value>, ...},
        }

    VUnit splits per-file compile options (e.g. ``nvc.a_flags`` —
    flags passed to ``nvc -a``) from per-config sim options (e.g.
    ``ghdl.elab_flags``); the two go through different setters
    (``vu.set_compile_option`` and ``vu.set_sim_option`` respectively).
    Both sub-dicts are optional. This loop is intentionally
    sim-agnostic, so adding a new simulator's coverage support is a
    sim-side change with no edit here.

    TODO: aggregation of per-test sim-side coverage artifacts (gcov
    ``.gcda``/``.gcno``, Mentor UCDB, Aldec ACDB, …) into
    ``VUNIT_COVERAGE_OUTPUT`` isn't implemented here — the default
    driver leaves them under ``VUNIT_OUTPUT_PATH`` and trusts
    downstream tooling (or a toolchain-overridden ``run.py`` using
    ``vu.main(post_run=...)``) to collect them.
    """
    if os.environ.get("VUNIT_COVERAGE") != "1":
        return
    options_json = os.environ.get("VUNIT_COVERAGE_SIM_OPTIONS")
    if not options_json:
        return
    options = json.loads(options_json)
    for key, value in options.get("compile_options", {}).items():
        vu.set_compile_option(key, value)
    for key, value in options.get("sim_options", {}).items():
        vu.set_sim_option(key, value)


def main() -> None:
    """Drive VUnit from the wrapper-supplied environment contract."""
    manifest = load_manifest(Path(os.environ["VUNIT_LIBRARIES_JSON"]))

    # `VUnit.from_argv(argv=...)` passes argv straight to argparse — no
    # implicit `argv[1:]` strip — so we must NOT include `sys.argv[0]`
    # here. If we did, the script path would be picked up as the first
    # positional `test_pattern`, match zero testbenches, and VUnit would
    # silently report "No tests were run!" with exit 0.
    argv = [
        "--no-color",
        "-o",
        os.environ["VUNIT_OUTPUT_PATH"],
        "-x",
        os.environ["VUNIT_XUNIT_XML"],
    ] + sys.argv[1:]
    vu = VUnit.from_argv(argv=argv)

    has_vhdl = False
    has_verilog = False
    for entry in manifest.values():
        has_vhdl = has_vhdl or bool(entry.vhdl_sources)
        has_verilog = has_verilog or bool(entry.verilog_sources)
        if has_vhdl and has_verilog:
            break

    if has_vhdl:
        vu.add_vhdl_builtins()
    builtin_verilog_include_dirs: List[str] = []
    if has_verilog:
        # Repoint `vunit.builtins.VERILOG_PATH` at a `+`-free staged
        # copy when needed BEFORE `add_verilog_builtins` reads it.
        # See the helper's docstring for the full story.
        ensure_vunit_verilog_path_is_plus_free()
        vu.add_verilog_builtins()
        builtin_verilog_include_dirs = [str(vunit_builtin_verilog_include_dir())]

    for lib_name, entry in manifest.items():
        lib = vu.add_library(lib_name)
        for src in entry.vhdl_sources:
            lib.add_source_file(src)
        # Per-library include dirs come from `VerilogInfo.includes`
        # (verilog_library populates from `hdrs`' parent dirs and the
        # `includes` attr) plus VUnit's own builtin SV header dir.
        # VHDL `add_source_file()` doesn't accept include_dirs, so we
        # keep the per-language loops split.
        verilog_include_dirs = list(entry.verilog_include_dirs) + builtin_verilog_include_dirs
        for src in entry.verilog_sources:
            lib.add_source_file(src, include_dirs=verilog_include_dirs)

    configure_coverage(vu)

    vu.main()


if __name__ == "__main__":
    main()
