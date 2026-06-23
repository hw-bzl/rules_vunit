"""VUnit Questa simulator integration"""

load(":vunit_sim_utils.bzl", "SIM_ENV_ATTR", "VUnitSimInfo", "VUnitSimOutputInfo", "gather_library_sources")

VUnitSimQuestaInfo = provider(
    doc = "Questa-specific extension of `VUnitSimInfo`.",
    fields = {
        "all_files": "depset[File]: All transitive runfiles required by the Questa tools.",
        "vcom": "File: The `vcom` VHDL compiler executable.",
        "vlib": "File: The `vlib` library manager executable.",
        "vlog": "File: The `vlog` Verilog compiler executable.",
        "vsim": "File: The `vsim` simulator executable.",
    },
)

def questa_compile(ctx, simulator, libraries, sim_opts):
    """Stage HDL sources for a Questa simulation under VUnit.

    Args:
        ctx (ctx): The rule's context object.
        simulator (Target): The `vunit_questa_sim` target.
        libraries (list): List of (lib_name, target) pairs.
        sim_opts (list[str]): Forwarded to VUnit's CLI.

    Returns:
        VUnitSimOutputInfo: Source runfiles plus the `VUNIT_SIMULATOR` env var.
    """
    sim_info = simulator[VUnitSimQuestaInfo]
    if not sim_info.vsim:
        fail("vunit_questa_sim requires a vsim binary")

    # VUnit shares the `modelsim` backend for both ModelSim and Questa.
    return VUnitSimOutputInfo(
        runfiles = ctx.runfiles(transitive_files = gather_library_sources(libraries)),
        sim_env = {"VUNIT_SIMULATOR": "modelsim"},
        test_args = list(sim_opts),
        build_args = [],
    )

def _vunit_questa_sim_impl(ctx):
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
            compile = questa_compile,
            env = ctx.attr.env,
            name = "modelsim",
        ),
        VUnitSimQuestaInfo(
            all_files = all_files,
            vcom = ctx.executable.vcom,
            vlib = ctx.executable.vlib,
            vlog = ctx.executable.vlog,
            vsim = ctx.executable.vsim,
        ),
    ]

vunit_questa_sim = rule(
    doc = """\
A simulator configuration for running [Mentor/Siemens EDA
Questa](https://eda.sw.siemens.com/en-US/ic/questa/) under VUnit.

Functionally identical to `vunit_modelsim_sim` — VUnit shares one
backend for both products. Use whichever name suits your team's
terminology.

### Status

Infrastructure only. Questa is commercial, with no BCR module and no
redistributable binary; `rules_vunit` cannot validate this rule in CI.
""",
    implementation = _vunit_questa_sim_impl,
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
