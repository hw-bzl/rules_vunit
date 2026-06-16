"""Translate a Cobertura XML coverage report into LCOV.

Cobertura is the most portable structured coverage format produced by
EDA simulators with first-class coverage support — NVC's
`--cover-export --format=cobertura` emits it today; commercial tools
(Mentor `vcover report -cobertura`, etc.) emit something close enough
to share. LCOV is what Bazel's coverage runner reads.

Used standalone:

    cobertura_to_lcov <cobertura.xml> <out.lcov>

…or imported as a library by a sim-specific bridge that has driven a
simulator-side `--cover-export` step:

    from cobertura_to_lcov import convert
    convert(Path("cobertura.xml"), Path("out.lcov"))

The translation handles the subset Cobertura schema EDA tools emit:

    <class filename="..."><lines>
      <line number="N" hits="K"/>
      <line number="N" hits="K" branch="true"
            condition-coverage="X% (Y/Z)">
        <conditions>
          <condition number="0" coverage="X%" type="…"/>
        </conditions>
      </line>
    </lines></class>

Output mapping:

    SF:<filename>
    DA:<line>,<hits>
    BRDA:<line>,0,<branch_idx>,<taken>   ← when <conditions> present
    BRF:/BRH:                             ← totals when any branch seen
    LF:/LH:
    end_of_record

The function-coverage records (`FN:`/`FNDA:`/`FNF:`/`FNH:`) are NOT
emitted — Cobertura's `<methods>` block is rare in HDL coverage output
and reconstructing it from sim semantics is more trouble than it's
worth. Bazel happily reports line+branch coverage without it.
"""

import argparse
import sys
from pathlib import Path
from xml.etree import ElementTree


# pylint: disable-next=too-many-locals
def convert(cobertura_xml: Path, lcov_out: Path) -> None:
    """Translate Cobertura XML at ``cobertura_xml`` into LCOV at ``lcov_out``.

    Idempotent — overwrites ``lcov_out`` each call. Creates the parent
    directory if missing.
    """
    tree = ElementTree.parse(cobertura_xml)
    per_file: dict[str, list[ElementTree.Element]] = {}
    for klass in tree.iterfind(".//class"):
        filename = klass.get("filename")
        if not filename:
            continue
        per_file.setdefault(filename, []).extend(klass.findall("./lines/line"))

    lcov_out.parent.mkdir(parents=True, exist_ok=True)
    with lcov_out.open("w", encoding="utf-8") as f:
        for filename in sorted(per_file):
            lines = per_file[filename]
            f.write(f"SF:{filename}\n")
            lines_found = 0
            lines_hit = 0
            branches_found = 0
            branches_hit = 0
            for line in lines:
                number = line.get("number")
                hits = line.get("hits")
                if number is None or hits is None:
                    continue
                hits_int = int(hits)
                f.write(f"DA:{number},{hits_int}\n")
                lines_found += 1
                if hits_int > 0:
                    lines_hit += 1
                for branch_idx, branch in enumerate(line.findall("./conditions/condition")):
                    cov = branch.get("coverage", "0%").rstrip("%")
                    try:
                        taken = int(float(cov))
                    except ValueError:
                        taken = 0
                    f.write(f"BRDA:{number},0,{branch_idx},{taken}\n")
                    branches_found += 1
                    if taken > 0:
                        branches_hit += 1
            if branches_found:
                f.write(f"BRF:{branches_found}\n")
                f.write(f"BRH:{branches_hit}\n")
            f.write(f"LF:{lines_found}\n")
            f.write(f"LH:{lines_hit}\n")
            f.write("end_of_record\n")


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cobertura", type=Path, help="Input Cobertura XML.")
    parser.add_argument("lcov", type=Path, help="Output LCOV file.")
    args = parser.parse_args()

    convert(args.cobertura, args.lcov)
    return 0


if __name__ == "__main__":
    sys.exit(main())
