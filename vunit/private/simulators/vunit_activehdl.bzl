"""VUnit Active-HDL simulator integration"""

load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")
load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load(":vunit_sim_utils.bzl", "SIM_ENV_ATTR", "VUnitSimInfo", "VUnitSimOutputInfo")

VUnitSimActiveHdlInfo = provider(
    doc = "Active-HDL-specific extension of `VUnitSimInfo`.",
    fields = {
        "all_files": "depset[File]: All transitive runfiles required by the Active-HDL tools.",
        "vcom": "File: The `vcom` VHDL compiler executable.",
        "vlib": "File: The `vlib` library manager executable.",
        "vlog": "File: The `vlog` Verilog compiler executable.",
        "vsim": "File: The `vsim` simulator executable.",
    },
)

def _gather_library_sources(libraries):
    transitive = []
    for _, lib_target in libraries:
        if VhdlInfo in lib_target:
            transitive.append(lib_target[VhdlInfo].srcs)
            transitive.append(lib_target[VhdlInfo].data)
        elif VerilogInfo in lib_target:
            transitive.append(lib_target[VerilogInfo].srcs)
            transitive.append(lib_target[VerilogInfo].data)
        else:
            fail("Library target `{}` provides neither VhdlInfo nor VerilogInfo.".format(
                lib_target.label,
            ))
    return depset(transitive = transitive)

def activehdl_compile(ctx, simulator, libraries, sim_opts):
    """Stage HDL sources for an Active-HDL simulation under VUnit.

    Args:
        ctx (ctx): The rule's context object.
        simulator (Target): The `vunit_activehdl_sim` target.
        libraries (list): List of (lib_name, target) pairs.
        sim_opts (list[str]): Forwarded to VUnit's CLI.

    Returns:
        VUnitSimOutputInfo: Source runfiles plus the `VUNIT_SIMULATOR` env var.
    """
    sim_info = simulator[VUnitSimActiveHdlInfo]
    if not sim_info.vsim:
        fail("vunit_activehdl_sim requires a vsim binary")

    return VUnitSimOutputInfo(
        runfiles = ctx.runfiles(transitive_files = _gather_library_sources(libraries)),
        sim_env = {"VUNIT_SIMULATOR": "activehdl"},
        test_args = list(sim_opts),
        build_args = [],
    )

def _vunit_activehdl_sim_impl(ctx):
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
            compile = activehdl_compile,
            env = ctx.attr.env,
            name = "activehdl",
        ),
        VUnitSimActiveHdlInfo(
            all_files = all_files,
            vcom = ctx.executable.vcom,
            vlib = ctx.executable.vlib,
            vlog = ctx.executable.vlog,
            vsim = ctx.executable.vsim,
        ),
    ]

vunit_activehdl_sim = rule(
    doc = """\
A simulator configuration for running [Aldec
Active-HDL](https://www.aldec.com/en/products/fpga_simulation/active-hdl)
under VUnit.

### Status

Infrastructure only. Active-HDL is commercial, with no BCR module and
no redistributable binary; `rules_vunit` cannot validate this rule in
CI.

### Notes

Active-HDL accepts both Verilog/SystemVerilog (`VerilogInfo`) and VHDL
(`VhdlInfo`) modules. Sets `VUNIT_SIMULATOR=activehdl`.
""",
    implementation = _vunit_activehdl_sim_impl,
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
