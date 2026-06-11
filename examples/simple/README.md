# `rules_vunit` simple example (GHDL)

Self-contained downstream project that builds an 8-bit VHDL adder and
exercises it with a VUnit testbench under GHDL. Demonstrates the
minimum wiring needed to assemble a custom `vunit_toolchain`.

```text
examples/simple/
├── MODULE.bazel              # bazel_deps + vunit_pip_deps + register custom toolchain
├── BUILD.bazel               # py_library(vunit) + vunit_ghdl_sim + vunit_toolchain + vunit_test
├── adder.vhd                 # 8-bit DUT
├── tb_adder.vhd              # VUnit testbench
├── requirements_*.txt        # pinned vunit_hdl pip wheels (copied from rules_vunit)
└── README.md                 # this file
```

## Run it

From this directory:

```text
bazel test //...
```

Expected output:

```text
//:adder_test                                                            PASSED
Executed 1 out of 1 test: 1 test passes.
```

## What a downstream project needs

`rules_vunit` deliberately does *not* register a default toolchain for
downstream consumers — its in-tree `@rules_vunit//vunit/toolchain` is
scoped to the rules_vunit dev workflow. A downstream project assembles
its own with the simulators it actually wants. This example shows the
minimum:

1. **`MODULE.bazel`** — `bazel_dep` on `rules_vunit` plus the BCR
   modules for whatever simulators you want (`ghdl` for GHDL),
   `rules_req_compile` for VUnit's pip wheels, and `rules_venv` for
   the `py_library` rule. The example reuses rules_vunit's pinned lock
   files via local copies; a real project would maintain its own and
   could pin a different `vunit_hdl` version.

2. **`BUILD.bazel`** — four pieces in order:
   - A `py_library(name = "vunit", deps = ["@vunit_pip_deps//vunit_hdl"])`
     wrapping the wheel. The toolchain consumes this label.
   - `vunit_ghdl_sim(ghdl = "@ghdl", vhdl_libs = ["@ghdl//:vhdl_libs_v08"])`.
   - `vunit_toolchain` + `toolchain()` rules to register the sim.
   - `vhdl_library` (for both DUT and testbench) + `vunit_test` for
     the actual run.

3. **`register_toolchains("//:vunit_toolchain")`** in `MODULE.bazel`
   to make the toolchain discoverable.

## Adding more simulators

The `simulators` dict on `vunit_toolchain` is a mapping from
`vunit_*_sim` targets to the names `vunit_test(sim = "...")` selects
by. To add NVC or ModelSim, instantiate `vunit_nvc_sim` /
`vunit_modelsim_sim` alongside `vunit_ghdl` and extend the dict:

```python
simulators = {
    ":vunit_ghdl":     "ghdl",
    ":vunit_nvc":      "nvc",
    ":vunit_modelsim": "modelsim",
},
```

Each simulator integration has its own reference page in the
[rules_vunit book](../../docs/src/simulators.md) listing the
attributes it needs.

## Customising `run.py`

The default `run.py` shipped with rules_vunit wires VUnit up from the
library descriptor the rule emits. Override it via the toolchain's
`run_py` attribute when you need extra orchestration:

```python
vunit_toolchain(
    name = "vunit_toolchain_def",
    vunit = ":vunit",
    run_py = "//:custom_run.py",   # <-- your script
    simulators = {":vunit_ghdl": "ghdl"},
)
```

A custom `run.py` may read the wrapper-supplied environment
(`VUNIT_LIBRARIES_JSON`, `VUNIT_OUTPUT_PATH`, `VUNIT_XUNIT_XML`) or
configure VUnit by hand.
