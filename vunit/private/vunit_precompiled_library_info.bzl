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
        "vendor": ("str: optional ecosystem identifier for vendor-specific " +
                   "quirks. Known values: " +
                   "`xilinx` (Vivado export — adds `xil_defaultlib.glbl` as " +
                   "a sibling top to elaborate GSR/GTS/PRLD pseudo-resets, " +
                   "and bumps simulation precision to `fs` so MMCM/PLL " +
                   "half-period math survives rounding). Empty string for " +
                   "bundles that don't need ecosystem fixups. The wrapper " +
                   "applies vendor quirks additively on top of the format's " +
                   "runner patch."),
    },
)
