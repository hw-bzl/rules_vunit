# rules_vunit

Bazel rules that run [VUnit](https://vunit.github.io/) testbenches
against VHDL (and SystemVerilog where the simulator supports it) modules
using HDL simulators — primarily GHDL among the open-source set, with
infrastructure for NVC and the major commercial simulators
(ModelSim/Questa, Riviera-PRO, Active-HDL).

## Overview

A `vunit_test` is a Bazel `test` target that pairs:

- one or more HDL `*_library` targets (from
  [`rules_vhdl`](https://github.com/hw-bzl/rules_vhdl) and/or
  [`rules_verilog`](https://github.com/hw-bzl/rules_verilog)) keyed by
  the VUnit library name they should be added under,
- a `vunit_toolchain` that picks the simulator and supplies the
  orchestration `run.py`.

The two top-level rules are documented under
[Rules](./rules.md); the per-simulator integrations live under
[Simulators](./simulators.md).

## End-to-end example

The walkthrough below builds a tiny 8-bit VHDL adder and exercises it
with a VUnit testbench under GHDL.

### `MODULE.bazel`

```python
bazel_dep(name = "rules_vhdl", version = "0.1.1")
bazel_dep(name = "rules_vunit", version = "{version}")
```

`rules_vunit` registers an in-tree toolchain
(`//vunit/toolchain:toolchain`) wired to GHDL for its own test suite,
but downstream projects should define their own — see the
[example](https://github.com/hw-bzl/rules_vunit/tree/main/examples/simple)
for the minimum wiring.

### `adder.vhd`

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adder is
    port (
        x                : in  std_logic_vector(7 downto 0);
        y                : in  std_logic_vector(7 downto 0);
        carry_in         : in  std_logic;
        sum              : out std_logic_vector(7 downto 0);
        carry_output_bit : out std_logic
    );
end entity adder;

architecture rtl of adder is
    signal result : unsigned(8 downto 0);
begin
    result <= ('0' & unsigned(x)) + ('0' & unsigned(y)) + ("00000000" & carry_in);
    sum              <= std_logic_vector(result(7 downto 0));
    carry_output_bit <= result(8);
end architecture rtl;
```

### `tb_adder.vhd`

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_adder is
    generic (runner_cfg : string);
end entity tb_adder;

architecture tb of tb_adder is
    signal x, y, sum     : std_logic_vector(7 downto 0) := (others => '0');
    signal carry_in, cout : std_logic := '0';
begin
    dut : entity work.adder
        port map (x, y, carry_in, sum, cout);

    main : process
    begin
        test_runner_setup(runner, runner_cfg);
        while test_suite loop
            if run("test_basic_add") then
                x <= x"03"; y <= x"04"; carry_in <= '0';
                wait for 1 ns;
                check_equal(sum, std_logic_vector'(x"07"));
            end if;
        end loop;
        test_runner_cleanup(runner);
    end process;
end architecture tb;
```

### `BUILD.bazel`

```python
load("@rules_vhdl//vhdl:defs.bzl", "vhdl_library")
load("@rules_vunit//vunit:vunit_test.bzl", "vunit_test")

vhdl_library(name = "adder", srcs = ["adder.vhd"])
vhdl_library(name = "tb_adder", srcs = ["tb_adder.vhd"], deps = [":adder"])

vunit_test(
    name = "adder_test",
    libraries = {
        ":tb_adder": "tb_lib",
        ":adder":    "work",
    },
    sim = "ghdl",
)
```

### Run it

```text
$ bazel test //path/to:adder_test
//path/to:adder_test                                                     PASSED
```

## Going further

- The [`vunit_test`](./vunit_test.md) reference covers the full
  attribute set (`sim_opts`, `env`, `data`, etc.).
- The [`vunit_toolchain`](./vunit_toolchain.md) reference shows how to
  define a custom toolchain — selecting a different default simulator,
  overriding `run.py`, or wiring in bring-your-own-install
  `vunit_*_sim` rules.
- The [Simulators](./simulators.md) section lists every built-in
  simulator integration and per-simulator status.
