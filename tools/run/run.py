"""Default VUnit driver shipped with rules_vunit.

The `vunit_test` rule invokes this script via the process wrapper. Override
the toolchain's `run_py` attribute when you need custom orchestration
(per-test attributes, `set_sim_option(...)` calls, `post_run` hooks, ...).

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
from pathlib import Path
from typing import Mapping, NamedTuple, Sequence

from vunit import VUnit  # type: ignore[import-untyped]


class LibraryEntry(NamedTuple):
    """Sources declared for a single VUnit library."""

    vhdl_sources: Sequence[Path]
    verilog_sources: Sequence[Path]


# The deserialised shape of `VUNIT_LIBRARIES_JSON`. Keep in sync with
# `_libraries_json_map_fn` in `//vunit/private/vunit_test.bzl`, which writes
# this manifest at action time.
LibraryManifest = Mapping[str, LibraryEntry]


def _load_manifest(path: Path) -> LibraryManifest:
    """Deserialise the libraries descriptor written by the `vunit_test` rule."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {
        lib_name: LibraryEntry(
            vhdl_sources=[Path(p) for p in entry.get("vhdl_sources", [])],
            verilog_sources=[Path(p) for p in entry.get("verilog_sources", [])],
        )
        for lib_name, entry in raw.items()
    }


def _configure_coverage(vu: VUnit) -> None:
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
    manifest = _load_manifest(Path(os.environ["VUNIT_LIBRARIES_JSON"]))

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

    if any(entry.vhdl_sources for entry in manifest.values()):
        vu.add_vhdl_builtins()
    if any(entry.verilog_sources for entry in manifest.values()):
        vu.add_verilog_builtins()

    for lib_name, entry in manifest.items():
        lib = vu.add_library(lib_name)
        for src in list(entry.vhdl_sources) + list(entry.verilog_sources):
            lib.add_source_file(src)

    _configure_coverage(vu)

    vu.main()


if __name__ == "__main__":
    main()
