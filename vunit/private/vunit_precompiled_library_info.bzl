"""`VUnitPrecompiledLibraryInfo` — provider for downstream-produced library sets.

Cocotb's analog (`CocotbPrecompiledLibraryInfo`) ships with `rules_cocotb`;
the VUnit equivalent serves the same role: a contract between rules_vunit's
`vunit_test` consumer and a downstream producer (e.g. a rule that compiles
Xilinx IP simulation libraries into a Riviera library set). rules_vunit owns
the contract; the producer rules live in downstream orgs because they
typically dispatch over heterogeneous build-system inputs (Vivado exports,
plain HDL libraries, vendor IP catalogs) that this ruleset can't reasonably
model upstream.

Field shapes mirror `CocotbPrecompiledLibraryInfo` exactly so a single
downstream producer rule can return both providers from the same action
(one Bazel target, one compile, two consumers).
"""

VUnitPrecompiledLibraryInfo = provider(
    doc = ("Output of a downstream rule that materialises a simulator " +
           "vendor's precompiled library set (e.g. Xilinx IP simulation " +
           "libraries extracted via Vivado `export_simulation` and compiled " +
           "by the simulator's own driver). The vunit test rule consumes " +
           "these via its `precompiled_libs` attr; the vunit_process_wrapper " +
           "patches the per-format runner to emit the vendor's link " +
           "directive (`vmap -link` for Aldec, `-modelsimini` for Mentor, " +
           "etc.) before VUnit's own compile step."),
    fields = {
        "format": ("str: precompiled-library format family. Tied to the " +
                   "vendor binary format and link-config syntax, not to an " +
                   "individual simulator. Known values: " +
                   "`aldec` (rivierapro, activehdl), " +
                   "`mentor` (questa, modelsim), " +
                   "`synopsys` (vcs, vcs_mx), " +
                   "`cadence` (xcelium, ies). One bundle works for every " +
                   "simulator in its family."),
        "library_dir": ("File: TreeArtifact rooted at the library set. " +
                        "Holds the format's link-config file at a " +
                        "conventional path " +
                        "(aldec: ./library.cfg; " +
                        "mentor: ./modelsim.ini; " +
                        "synopsys: ./synopsys_sim.setup; " +
                        "cadence: ./cds.lib) plus the per-library compiled " +
                        "artifacts the link-config references."),
        "links_secureip": ("bool: True when this bundle ships a `secureip` " +
                           "library that encrypted vendor primitives " +
                           "reference at elaboration. When set, the " +
                           "wrapper instructs the toolchain `run.py` to " +
                           "add `-L secureip` (Aldec) / equivalent to the " +
                           "vsim link flags so the encrypted modules " +
                           "resolve. Replaces the legacy `vendor='xilinx'` " +
                           "string check in downstream `run.py`s."),
        "provides_glbl": ("bool: True when this bundle ships the Xilinx " +
                          "`glbl` module needed to drive global pseudo-" +
                          "resets (GSR/GTS/PRLD) for Vivado-exported IP. " +
                          "When set, the wrapper instructs the toolchain " +
                          "`run.py` to add `xil_defaultlib.glbl` as a " +
                          "sibling simulation top. Replaces the legacy " +
                          "`vendor='xilinx'` string check; bundles that " +
                          "provide glbl elsewhere (or don't need it) can " +
                          "leave this False even with `vendor='xilinx'`."),
        "vendor": ("str: free-form ecosystem identifier, included in the " +
                   "wrapper's runtime descriptor as advisory metadata for " +
                   "the toolchain `run.py` (e.g. logging which vendor's " +
                   "libs were linked). NOT used by the wrapper for any " +
                   "behavioral decision — see `links_secureip` / " +
                   "`provides_glbl` for typed quirks. Conventional values: " +
                   "`xilinx`, `intel`, `microchip`, or empty for " +
                   "non-vendor bundles."),
    },
)
