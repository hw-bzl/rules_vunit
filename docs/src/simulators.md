# Simulators

A simulator integration is a Bazel rule that wires a specific HDL
simulator into the VUnit test harness. `vunit_test` doesn't talk to
simulators directly — it picks one of the simulators registered in the
active `vunit_toolchain` by name (via its `sim` attribute), and the
toolchain dispatches source staging through the matching `vunit_*_sim`
target.

Each `vunit_*_sim` rule produces a `VUnitSimInfo` provider that the
shared `vunit_test` rule consumes. New simulator integrations can be
added by writing a rule that returns the same provider and registering
it in a `vunit_toolchain.simulators` dict.

## Built-in integrations

| Rule | HDL languages | Source | CI-verified |
|------|---------------|--------|-------------|
| [`vunit_ghdl_sim`](./vunit_ghdl_sim.md) | VHDL | BCR `ghdl` | ✅ |
| [`vunit_nvc_sim`](./vunit_nvc_sim.md) | VHDL | bring-your-own (no BCR module yet) | — |
| [`vunit_modelsim_sim`](./vunit_modelsim_sim.md) | Verilog / SystemVerilog / VHDL | bring-your-own (commercial) | — |
| [`vunit_questa_sim`](./vunit_questa_sim.md) | Verilog / SystemVerilog / VHDL | bring-your-own (commercial; same VUnit backend as ModelSim) | — |
| [`vunit_riviera_sim`](./vunit_riviera_sim.md) | Verilog / SystemVerilog / VHDL | bring-your-own (commercial) | — |
| [`vunit_activehdl_sim`](./vunit_activehdl_sim.md) | Verilog / SystemVerilog / VHDL | bring-your-own (commercial) | — |

The in-tree toolchain (`//vunit/toolchain:toolchain`) registers only
the CI-verified row — GHDL. For any other simulator, define your own
[`vunit_toolchain`](./vunit_toolchain.md) that wires the relevant
`vunit_*_sim` to your install and register it ahead of the default.

The "CI-verified" column is what `rules_vunit`'s own `//tests/...`
exercises. The other rules are wired correctly against VUnit's
simulator backends, but `rules_vunit` can't ship the binaries
(commercial license or no BCR module yet), so we can't validate them
ourselves — please file issues if you hit problems wiring one up.

Per-simulator status, known limitations, and any downstream-wiring
patterns are inline on each simulator's reference page.
