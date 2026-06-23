"""VUnit ModelSim simulator integration"""

load(":vunit_sim_utils.bzl", "SIM_ENV_ATTR", "VUnitSimInfo", "VUnitSimOutputInfo", "gather_library_sources")

VUnitSimModelsimInfo = provider(
    doc = "ModelSim-specific extension of `VUnitSimInfo`.",
    fields = {
        "all_files": "depset[File]: All transitive runfiles required by the ModelSim tools.",
        "vcom": "File: The `vcom` VHDL compiler executable.",
        "vlib": "File: The `vlib` library manager executable.",
        "vlog": "File: The `vlog` Verilog compiler executable.",
        "vsim": "File: The `vsim` simulator executable.",
    },
)

def modelsim_compile(ctx, simulator, libraries, sim_opts):
    """Stage HDL sources for a ModelSim/Questa simulation under VUnit.

    Args:
        ctx (ctx): The rule's context object.
        simulator (Target): The `vunit_modelsim_sim` target.
        libraries (list): List of (lib_name, target) pairs.
        sim_opts (list[str]): Forwarded to VUnit's CLI.

    Returns:
        VUnitSimOutputInfo: Source runfiles plus the `VUNIT_SIMULATOR` env var.
    """
    sim_info = simulator[VUnitSimModelsimInfo]
    if not sim_info.vsim:
        fail("vunit_modelsim_sim requires a vsim binary")

    return VUnitSimOutputInfo(
        runfiles = ctx.runfiles(transitive_files = gather_library_sources(libraries)),
        sim_env = {"VUNIT_SIMULATOR": "modelsim"},
        test_args = list(sim_opts),
        build_args = [],
    )

def _vunit_modelsim_sim_impl(ctx):
    all_files = depset(transitive = [
        ctx.attr.vlib[DefaultInfo].default_runfiles.files,
        ctx.attr.vlog[DefaultInfo].default_runfiles.files,
        ctx.attr.vcom[DefaultInfo].default_runfiles.files,
        ctx.attr.vsim[DefaultInfo].default_runfiles.files,
    ])
    return [
        VUnitSimInfo(
            all_files = all_files,
            bins = {
                "vcom": ctx.executable.vcom,
                "vlib": ctx.executable.vlib,
                "vlog": ctx.executable.vlog,
                "vsim": ctx.executable.vsim,
            },
            compile = modelsim_compile,
            env = ctx.attr.env,
            name = "modelsim",
        ),
        VUnitSimModelsimInfo(
            all_files = all_files,
            vcom = ctx.executable.vcom,
            vlib = ctx.executable.vlib,
            vlog = ctx.executable.vlog,
            vsim = ctx.executable.vsim,
        ),
    ]

vunit_modelsim_sim = rule(
    doc = """\
A simulator configuration for running [Mentor/Siemens EDA
ModelSim](https://eda.sw.siemens.com/en-US/ic/modelsim/) under VUnit.

VUnit shares the `modelsim` backend for both ModelSim and Questa; use
`vunit_questa_sim` if you prefer that terminology — they wire up the
same VUnit backend.

### Status

Infrastructure only. ModelSim is commercial, with no BCR module and no
redistributable binary; `rules_vunit` cannot validate this rule in CI.
Wire it up downstream by pointing the binary attrs at your own install
and registering a `vunit_toolchain` that routes `sim = "modelsim"`
through this rule.

### Notes

ModelSim accepts both Verilog/SystemVerilog (`VerilogInfo`) and VHDL
(`VhdlInfo`) modules. VUnit drives `vlib` / `vlog` / `vcom` / `vsim` via
its own runner — the rule just stages sources and surfaces the
binaries on PATH.
""",
    implementation = _vunit_modelsim_sim_impl,
    attrs = {
        "env": SIM_ENV_ATTR,
        "vcom": attr.label(
            doc = "The `vcom` VHDL compiler binary.",
            executable = True,
            mandatory = True,
            cfg = "exec",
        ),
        "vlib": attr.label(
            doc = "The `vlib` library manager binary.",
            executable = True,
            mandatory = True,
            cfg = "exec",
        ),
        "vlog": attr.label(
            doc = "The `vlog` Verilog/SystemVerilog compiler binary.",
            executable = True,
            mandatory = True,
            cfg = "exec",
        ),
        "vsim": attr.label(
            doc = "The `vsim` simulator binary.",
            executable = True,
            mandatory = True,
            cfg = "exec",
        ),
    },
)
