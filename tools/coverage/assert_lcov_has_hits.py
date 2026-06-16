#!/usr/bin/env python3
"""Assert a Bazel coverage `_coverage_report.dat` lcov file contains
actual HDL coverage hits (not just the empty baseline records Bazel
emits when no test produced coverage).

Reads the file at argv[1]. Walks each `SF:<source>` ... `end_of_record`
block and counts:
  * `LH:<n>` lines hit (sum across records)
  * `LF:<n>` lines findable (sum across records)
  * `BRH:<n>` branches hit (sum across records)
  * `BRF:<n>` branches findable

Exits 0 iff at least one record has `LH > 0` OR `BRH > 0`, AND the
expected source file (argv[2], optional) is referenced. Otherwise prints
a summary and exits 1.

Designed to be invoked from CI after `bazel coverage //...` to ensure
the HDL coverage bridge actually emitted hits, not just baseline.
"""

import sys
from pathlib import Path
from typing import List, NamedTuple


class _Record(NamedTuple):
    sf: str
    lh: int
    lf: int
    brh: int
    brf: int


def _parse_lcov(text: str) -> List[_Record]:
    """Parse lcov tracefile text into per-source records."""
    records: List[_Record] = []
    sf, lh, lf, brh, brf = "", 0, 0, 0, 0
    for line in text.splitlines():
        if line.startswith("SF:"):
            sf = line[3:]
        elif line.startswith("LH:"):
            lh = int(line[3:])
        elif line.startswith("LF:"):
            lf = int(line[3:])
        elif line.startswith("BRH:"):
            brh = int(line[4:])
        elif line.startswith("BRF:"):
            brf = int(line[4:])
        elif line == "end_of_record" and sf:
            records.append(_Record(sf, lh, lf, brh, brf))
            sf, lh, lf, brh, brf = "", 0, 0, 0, 0
    return records


def main() -> int:
    """Walk lcov records and exit non-zero if no real coverage hits."""
    if len(sys.argv) < 2:
        print("usage: assert_lcov_has_hits.py <lcov-file> [<expected-source-substring>]")
        return 2

    lcov_path = Path(sys.argv[1])
    expected_substr = sys.argv[2] if len(sys.argv) > 2 else None

    if not lcov_path.exists():
        print(f"FAIL: lcov file does not exist: {lcov_path}")
        return 1

    records = _parse_lcov(lcov_path.read_text(encoding="utf-8"))
    if not records:
        print(f"FAIL: no `SF:` records found in {lcov_path}")
        return 1

    print(f"Found {len(records)} source record(s) in {lcov_path}:")
    for r in records:
        print(f"  {r.sf}: lines {r.lh}/{r.lf}, branches {r.brh}/{r.brf}")

    if expected_substr and not any(expected_substr in r.sf for r in records):
        print(f"FAIL: no record matched expected substring {expected_substr!r}")
        return 1

    nonempty = [r for r in records if r.lh > 0 or r.brh > 0]
    if not nonempty:
        print(
            "FAIL: every record has 0 line and 0 branch hits — coverage was not actually collected"
        )
        return 1

    print(f"OK: {len(nonempty)} record(s) have nonzero coverage hits")
    return 0


if __name__ == "__main__":
    sys.exit(main())
