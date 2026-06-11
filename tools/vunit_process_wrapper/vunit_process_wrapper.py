"""vunit process wrapper

This script is only intended to be invoked by the `vunit_test` Bazel rule.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Sequence, Tuple

from python.runfiles import Runfiles

VUNIT_TEST_ARGS_FILE = "VUNIT_TEST_ARGS_FILE"


def _find_runfile(runfiles: Runfiles, rlocationpath: str) -> Path:
    """Locate a runfile and ensure it points to a real file.

    Args:
        runfiles: A Runfiles object.
        rlocationpath: The runfile to look up.

    Returns:
        The path to the runfile.
    """
    runfile = runfiles.Rlocation(rlocationpath)
    if not runfile:
        raise FileNotFoundError(f"Runfile not found: {rlocationpath}")
    path = Path(runfile)
    if not path.exists():
        raise FileNotFoundError(f"Runfile does not exist: {path}")
    return path


def _parse_named_binary(value: str) -> Tuple[str, str]:
    """Parse a `name:rlocationpath` pair for a simulator binary.

    Args:
        value: The command line arg value in `name:rlocationpath` format.

    Returns:
        The binary name and its `rlocationpath`.
    """
    name, _, path = value.partition(":")
    return name, path


def parse_args(args: Sequence[str]) -> argparse.Namespace:
    """Parse command line arguments."""

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sim",
        type=str,
        required=True,
        help="The simulator name (e.g. 'ghdl', 'questa').",
    )
    parser.add_argument(
        "--sim_bin",
        dest="sim_bins",
        type=_parse_named_binary,
        default=[],
        action="append",
        help="Named simulator binary as `name:rlocationpath`. May be repeated.",
    )
    parser.add_argument(
        "--sim_env",
        dest="sim_envs",
        type=str,
        default=[],
        action="append",
        help=(
            "Simulator-supplied env var as `NAME=VALUE`. The value may be a "
            "literal string, or prefixed with `abs:<rlocationpath>` to set "
            "NAME to the absolute filesystem path of that runfile. Repeatable."
        ),
    )
    parser.add_argument(
        "--run_py",
        type=str,
        required=True,
        help="rlocationpath of the toolchain-supplied VUnit driver script.",
    )
    parser.add_argument(
        "--libraries_json",
        type=str,
        required=True,
        help="rlocationpath of the libraries descriptor emitted by `vunit_test`.",
    )
    parser.add_argument(
        "--vunit_arg",
        dest="vunit_args",
        type=str,
        default=[],
        action="append",
        help="Extra arg appended to the run.py invocation (forwarded into VUnit's CLI).",
    )
    parser.add_argument(
        "--precompiled_lib_dir",
        dest="precompiled_lib_dirs",
        type=str,
        default=[],
        action="append",
        help=(
            "Precompiled library set as `<format>:<vendor>:<rlocationpath>`. "
            "`format` selects the link directive family (e.g. `aldec` -> "
            "`vmap -link`); `vendor` triggers ecosystem quirks (e.g. "
            "`xilinx` adds `xil_defaultlib.glbl` as a sibling top). "
            "Repeatable. Exposed to run.py via `VUNIT_PRECOMPILED_LIBS_JSON`."
        ),
    )
    parser.add_argument(
        "--coverage",
        action="store_true",
        help="Enable coverage instrumentation. Sets `VUNIT_COVERAGE=1` for the run.py.",
    )
    parser.add_argument(
        "--coverage_output",
        type=str,
        default=None,
        help=(
            "rlocationpath of the coverage artifact path (Aldec ACDB, "
            "Mentor UCDB, GHDL gcov, …). Exposed to run.py via "
            "`VUNIT_COVERAGE_OUTPUT` as an absolute path."
        ),
    )

    return parser.parse_args(args)


def _resolve_abs_env(spec: str, runfiles: Runfiles) -> str:
    """Resolve an `abs:[upN:]<rlocationpath>` env value to an absolute path.

    Mirrors the convention used in rules_cocotb so simulator integrations
    can express GHDL_PREFIX-style "walk N parents up from this runfile" in
    a portable way.
    """
    up = 0
    while spec.startswith("up"):
        count_end = spec.find(":")
        if count_end <= 0:
            break
        try:
            up += int(spec[2:count_end])
        except ValueError:
            break
        spec = spec[count_end + 1 :]
    resolved = runfiles.Rlocation(spec)
    if not resolved:
        raise FileNotFoundError(f"Sim env runfile not found: {spec}")
    # `.absolute()` (not `.resolve()`) — see `_resolve_libraries_json` for
    # why we deliberately do not follow runfiles-tree symlinks.
    path = Path(resolved).absolute()
    for _ in range(up):
        path = path.parent
    return str(path)


def _resolve_libraries_json(runfiles: Runfiles, src_rloc: str, dst_path: Path) -> None:
    """Rewrite libraries.json rlocationpaths to runfiles-tree symlink paths.

    Uses `Path.absolute()` (which only prepends CWD for relative inputs) —
    NOT `Path.resolve()` (which canonicalises through symlinks). The
    runfiles tree's entries are deliberately symlinks pointing at declared
    inputs; `resolve()` would escape the sandbox by handing the simulator
    the path-after-symlink (the user's source tree / Bazel execroot),
    which the sandbox is supposed to keep out of view.
    """
    src = _find_runfile(runfiles, src_rloc)
    raw = json.loads(src.read_text(encoding="utf-8"))
    resolved = {
        lib: {
            "vhdl_sources": [
                str(_find_runfile(runfiles, p).absolute()) for p in entry.get("vhdl_sources", [])
            ],
            "verilog_sources": [
                str(_find_runfile(runfiles, p).absolute()) for p in entry.get("verilog_sources", [])
            ],
        }
        for lib, entry in raw.items()
    }
    dst_path.write_text(json.dumps(resolved, indent=2), encoding="utf-8")


# pylint: disable-next=too-many-locals,too-many-branches,too-many-statements
def main() -> None:
    """The main entrypoint."""
    if VUNIT_TEST_ARGS_FILE not in os.environ:
        raise EnvironmentError(f"`{VUNIT_TEST_ARGS_FILE}` was not found in environment.")

    runfiles = Runfiles.Create()
    if not runfiles:
        raise EnvironmentError("Failed to locate runfiles.")

    args_file = _find_runfile(runfiles, os.environ[VUNIT_TEST_ARGS_FILE])
    args = parse_args(args_file.read_text(encoding="utf-8").splitlines() + sys.argv[1:])

    env = dict(os.environ)
    env.update(runfiles.EnvVars())

    tmp_dir = tempfile.mkdtemp(dir=os.getenv("TEST_TMPDIR"), prefix="vunit_test-")
    tmp_path = Path(tmp_dir)

    # Avoid VUnit/GHDL caching into the user's real $HOME.
    home_dir = tmp_path / "home"
    home_dir.mkdir(exist_ok=True, parents=True)
    env["HOME"] = str(home_dir)

    # VUnit discovers simulators by walking $PATH. Symlink each
    # toolchain-supplied binary into a dedicated bin/ dir and prepend it.
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True, parents=True)
    env["PATH"] = str(bin_dir) + os.pathsep + env.get("PATH", "")
    for bin_name, bin_rlocationpath in args.sim_bins:
        sim_bin = _find_runfile(runfiles, bin_rlocationpath)
        (bin_dir / bin_name).symlink_to(sim_bin)

    for entry in args.sim_envs:
        name, _, value = entry.partition("=")
        if value.startswith("abs:"):
            value = _resolve_abs_env(value[len("abs:") :], runfiles)
        env[name] = value

    # Point VUnit's output dir straight at Bazel's undeclared-outputs dir
    # so compile artifacts, per-test logs, and wave files end up in the
    # test's `outputs.zip` without an intermediate copy. Fall back to a
    # tmp path for interactive invocations (`bazel run`) where the env
    # var isn't set.
    if "TEST_UNDECLARED_OUTPUTS_DIR" in os.environ:
        out_dir = Path(os.environ["TEST_UNDECLARED_OUTPUTS_DIR"]) / "vunit_out"
    else:
        out_dir = tmp_path / "vunit_out"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Point VUnit's xunit report straight at Bazel's `XML_OUTPUT_FILE` so
    # the test runner reads it without an intermediate copy. VUnit's
    # `--xunit-xml` writes JUnit-shaped XML, which is exactly what
    # Bazel expects at that path. Fall back to a tmp path for interactive
    # invocations (when `bazel run` is used, `XML_OUTPUT_FILE` is unset).
    if "XML_OUTPUT_FILE" in os.environ:
        xunit_path = Path(os.environ["XML_OUTPUT_FILE"])
        xunit_path.parent.mkdir(parents=True, exist_ok=True)
    else:
        xunit_path = tmp_path / "xunit.xml"

    libs_json = tmp_path / "libraries.resolved.json"
    _resolve_libraries_json(runfiles, args.libraries_json, libs_json)

    env["VUNIT_LIBRARIES_JSON"] = str(libs_json)
    env["VUNIT_OUTPUT_PATH"] = str(out_dir)
    env["VUNIT_XUNIT_XML"] = str(xunit_path)

    # Precompiled libs: surface as a small JSON the run.py reads. Format:
    # `[{"simulator": "...", "library_dir": "<absolute path>"}, ...]`. The
    # absolute path is computed here (where runfiles resolution lives) so
    # the run.py doesn't need to thread Runfiles itself.
    if args.precompiled_lib_dirs:
        precompiled_descriptors = []
        for entry in args.precompiled_lib_dirs:
            fmt, vendor, rloc = entry.split(":", 2)
            lib_dir = _find_runfile(runfiles, rloc)
            precompiled_descriptors.append(
                {
                    "format": fmt,
                    "vendor": vendor,
                    "library_dir": str(lib_dir.absolute()),
                }
            )
        precompiled_json = tmp_path / "precompiled_libs.json"
        precompiled_json.write_text(
            json.dumps(precompiled_descriptors, indent=2),
            encoding="utf-8",
        )
        env["VUNIT_PRECOMPILED_LIBS_JSON"] = str(precompiled_json)

    if args.coverage:
        env["VUNIT_COVERAGE"] = "1"
        if args.coverage_output:
            cov_runfile = runfiles.Rlocation(args.coverage_output)
            if cov_runfile:
                cov_path = Path(cov_runfile).absolute()
                cov_path.parent.mkdir(parents=True, exist_ok=True)
                env["VUNIT_COVERAGE_OUTPUT"] = str(cov_path)
            else:
                # The path is a declared output not yet materialised;
                # compute the expected location relative to the workspace
                # so run.py can write there.
                env["VUNIT_COVERAGE_OUTPUT"] = args.coverage_output

    # `run_py` is a plain Python script. Run it inside the wrapper's venv
    # (which `vunit_test` populates with `toolchain.vunit` + user deps)
    # so `import vunit` resolves against the active toolchain's library.
    # The subprocess inherits our stdout/stderr so VUnit's progress
    # output streams live to the test log rather than being held back
    # until completion.
    run_py = _find_runfile(runfiles, args.run_py)

    result = subprocess.run(
        [sys.executable, str(run_py), *args.vunit_args],
        env=env,
        check=False,
    )

    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
