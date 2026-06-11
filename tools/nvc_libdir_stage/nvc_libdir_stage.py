"""Stage compiled NVC library directories under one root.

Replaces what the BCR `nvc` module used to do via an `nvc_libdir`
rule that returned a single TreeArtifact. The BCR module now exposes
per-library TreeArtifacts at the same granularity an `apt`/`brew`
install of nvc would lay out on disk (`<prefix>/lib/nvc/<library>/`),
and consolidating them belongs in the consumer — here, `cocotb_nvc_sim`.

Usage:
    nvc_libdir_stage --out OUTPUT_DIR --lib LIB1_DIR [--lib LIB2_DIR ...]

Each input library directory's basename is its NVC library identifier
(e.g. `std`, `ieee`, `nvc.08`); we copy its contents into
`OUTPUT_DIR/<basename>/` so the simulator can find every shipped
library by name when `NVC_LIBPATH=OUTPUT_DIR` is set.
"""

import argparse
import os
import shutil
import stat
from pathlib import Path


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="Output directory.")
    parser.add_argument(
        "--lib",
        dest="libs",
        action="append",
        default=[],
        help="Compiled NVC library directory. Repeatable.",
    )
    return parser.parse_args()


def _make_writable(path: Path) -> None:
    """Add owner-write to `path`.

    Bazel marks files in TreeArtifact inputs read-only; nvc itself
    rewrites `_index` / library marker files in the staged work dir
    at simulation time, so each copied entry needs the write bit.
    """
    try:
        path.chmod(path.stat().st_mode | stat.S_IWUSR)
    except OSError:
        # Symlinks on some platforms can't have their permissions
        # changed; nvc will fail loudly enough later if a real file
        # genuinely stays read-only.
        pass


def _copy_tree(src: Path, dst: Path) -> None:
    """Recursively copy `src` into `dst`, widening permissions on copies."""
    shutil.copytree(src, dst, symlinks=True, dirs_exist_ok=True)
    _make_writable(dst)
    for root, dirs, files in os.walk(dst):
        for name in dirs + files:
            _make_writable(Path(root, name))


def main() -> None:
    """The main entrypoint."""
    args = parse_args()

    if not args.libs:
        raise ValueError("at least one --lib is required")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    for lib in args.libs:
        src = Path(lib)
        name = src.name
        if not name:
            raise ValueError(f"empty basename for --lib {lib}")
        _copy_tree(src, out_dir / name)


if __name__ == "__main__":
    main()
