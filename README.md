# rules_vunit

Bazel rules for running [VUnit](https://vunit.github.io/) testbenches against
VHDL (and SystemVerilog where the simulator supports it) modules.

## Rules

| Rule | What it does |
|---|---|
| `vunit_test` | A Bazel `test` target that drives VUnit over a set of `vhdl_library` / `verilog_library` targets keyed by VUnit library name. |
| `vunit_toolchain` | Bundles a `vunit` Python library + a set of `vunit_*_sim` targets + the `run.py` driver script. Registers via the standard `toolchain()` wrapper. |
| `vunit_ghdl_sim` | [GHDL](https://ghdl.github.io/ghdl/) integration (VHDL, open-source, tested in CI). |
| `vunit_nvc_sim` | [NVC](https://www.nickg.me.uk/nvc/) integration (VHDL, bring-your-own install). |
| `vunit_modelsim_sim` | Mentor/Siemens EDA ModelSim integration (commercial, bring-your-own install). |
| `vunit_questa_sim` | Mentor/Siemens EDA Questa integration (same VUnit backend as ModelSim; commercial, bring-your-own install). |
| `vunit_riviera_sim` | Aldec Riviera-PRO integration (commercial, bring-your-own install). |
| `vunit_activehdl_sim` | Aldec Active-HDL integration (commercial, bring-your-own install). |

## Documentation

Full reference for every rule and simulator integration — plus a worked
end-to-end example — is published at:

**<https://hw-bzl.github.io/rules_vunit>**

A minimum downstream wiring sits under [`examples/simple/`](examples/simple/).
