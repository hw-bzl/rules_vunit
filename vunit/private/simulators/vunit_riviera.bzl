"""VUnit Riviera-PRO simulator integration"""

load(":vunit_sim_utils.bzl", "SIM_ENV_ATTR", "VUnitSimInfo", "VUnitSimOutputInfo", "gather_library_sources")

VUnitSimRivieraInfo = provider(
    doc = "Riviera-PRO-specific extension of `VUnitSimInfo`.",
    fields = {
        "all_files": "depset[File]: All transitive runfiles required by the Riviera tools.",
        "vcom": "File: The `vcom` VHDL compiler executable.",
        "vlib": "File: The `vlib` library manager executable.",
        "vlist": "File: The `vlist` library lister executable.",
        "vlog": "File: The `vlog` Verilog compiler executable.",
        "vmap": "File: The `vmap` library-mapping executable.",
        "vsim": "File: The `vsim` simulator executable.",
        "vsimsa": "File: The `vsimsa` batch-shell executable (required at PATH alongside `vsim` for VUnit's RivieraProInterface to detect this toolchain).",
    },
)

def riviera_compile(ctx, simulator, libraries, sim_opts):
    """Stage HDL sources for a Riviera-PRO simulation under VUnit.

    Args:
        ctx (ctx): The rule's context object.
        simulator (Target): The `vunit_riviera_sim` target.
        libraries (list): List of (lib_name, target) pairs.
        sim_opts (list[str]): Forwarded to VUnit's CLI.

    Returns:
        VUnitSimOutputInfo: Source runfiles plus the `VUNIT_SIMULATOR` env var.
    """
    sim_info = simulator[VUnitSimRivieraInfo]
    if not sim_info.vsim:
        fail("vunit_riviera_sim requires a vsim binary")

    return VUnitSimOutputInfo(
        runfiles = ctx.runfiles(transitive_files = gather_library_sources(libraries)),
        sim_env = {"VUNIT_SIMULATOR": "rivierapro"},
        test_args = list(sim_opts),
        build_args = [],
    )

def _vunit_riviera_sim_impl(ctx):
    all_files = depset(transitive = [
        ctx.attr.vlib[DefaultInfo].default_runfiles.files,
        ctx.attr.vlist[DefaultInfo].default_runfiles.files,
        ctx.attr.vlog[DefaultInfo].default_runfiles.files,
        ctx.attr.vmap[DefaultInfo].default_runfiles.files,
        ctx.attr.vcom[DefaultInfo].default_runfiles.files,
        ctx.attr.vsim[DefaultInfo].default_runfiles.files,
        ctx.attr.vsimsa[DefaultInfo].default_runfiles.files,
    ])

    # Coverage post-processor — emitted as the `VUnitSimInfo.coverage`
    # struct the rules_vunit wrapper consumes. Only populated when the
    # rule's `coverage_tool` attr is set; consumers that don't ship a
    # converter omit it and `bazel coverage` produces baseline-only LCOV.
    # `tool` is the Target (not the File): the consumer pulls
    # `[DefaultInfo].files_to_run.executable` for the wrapper arg AND
    # `default_runfiles` so the launcher's interpreter + sibling data
    # ship alongside the executable.
    coverage_struct = None
    if ctx.attr.coverage_tool:
        coverage_struct = struct(
            tool = ctx.attr.coverage_tool,
            data_glob = ctx.attr.coverage_data_glob,
            args = list(ctx.attr.coverage_args),
        )

    return [
        VUnitSimInfo(
            all_files = all_files,
            bins = {
                "vcom": ctx.executable.vcom,
                "vlib": ctx.executable.vlib,
                "vlist": ctx.executable.vlist,
                "vlog": ctx.executable.vlog,
                "vmap": ctx.executable.vmap,
                "vsim": ctx.executable.vsim,
                "vsimsa": ctx.executable.vsimsa,
            },
            compile = riviera_compile,
            coverage = coverage_struct,
            env = ctx.attr.env,
            name = "rivierapro",
        ),
        VUnitSimRivieraInfo(
            all_files = all_files,
            vcom = ctx.executable.vcom,
            vlib = ctx.executable.vlib,
            vlist = ctx.executable.vlist,
            vlog = ctx.executable.vlog,
            vmap = ctx.executable.vmap,
            vsim = ctx.executable.vsim,
            vsimsa = ctx.executable.vsimsa,
        ),
    ]

vunit_riviera_sim = rule(
    doc = """\
A simulator configuration for running [Aldec
Riviera-PRO](https://www.aldec.com/en/products/functional_verification/riviera-pro)
under VUnit.

### Status

Infrastructure only. Riviera-PRO is commercial, with no BCR module and
no redistributable binary; `rules_vunit` cannot validate this rule in
CI.

### Notes

Riviera-PRO accepts both Verilog/SystemVerilog (`VerilogInfo`) and VHDL
(`VhdlInfo`) modules. Sets `VUNIT_SIMULATOR=rivierapro`.
""",
    implementation = _vunit_riviera_sim_impl,
    attrs = {
        "coverage_args": attr.string_list(
            doc = ("Template fragments forwarded to `coverage_tool` after " +
                   "the test runs under `bazel coverage`. `{output}` is " +
                   "substituted with `$COVERAGE_OUTPUT_FILE`; `{data_files}` " +
                   "is expanded into one positional arg per file matched " +
                   "by `coverage_data_glob`. Only meaningful when " +
                   "`coverage_tool` is set."),
            default = [],
        ),
        "coverage_data_glob": attr.string(
            doc = ("Shell glob (relative to the VUnit output dir) selecting " +
                   "the raw coverage data files `coverage_tool` consumes. " +
                   "For Riviera-PRO, `**/coverage.acdb` matches every " +
                   "per-testcase ACDB the run produces. Only meaningful " +
                   "when `coverage_tool` is set."),
            default = "",
        ),
        "coverage_tool": attr.label(
            doc = ("Optional Riviera coverage post-processor. When set AND " +
                   "the test runs under `bazel coverage` (Bazel populates " +
                   "`$COVERAGE_OUTPUT_FILE`), the rules_vunit process " +
                   "wrapper invokes this binary after the sim exits with " +
                   "the `coverage_args` template (substituting `{output}` " +
                   "and `{data_files}`) so it can translate the merged ACDB " +
                   "into lcov at `$COVERAGE_OUTPUT_FILE`. Leave unset to " +
                   "ship raw ACDBs under the test outputs dir without an " +
                   "lcov roll-up."),
            executable = True,
            cfg = "exec",
        ),
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
        "vlist": attr.label(
            doc = "The `vlist` library lister binary. Invoked by `vu.main()` to enumerate compiled units in the library.cfg.",
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
        "vmap": attr.label(
            doc = "The `vmap` library-mapping binary. Invoked when external (precompiled) libraries are linked into the test's library.cfg.",
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
        "vsimsa": attr.label(
            doc = ("The `vsimsa` batch-shell binary. **Required**: VUnit's " +
                   "`RivieraProInterface.find_prefix_from_path()` rejects a " +
                   "toolchain directory unless BOTH `vsim` AND `vsimsa` " +
                   "resolve in the same dir on PATH. Omitting `vsimsa` " +
                   "produces a confusing `No available simulator detected` " +
                   "error at test time."),
            executable = True,
            mandatory = True,
            cfg = "exec",
        ),
    },
)
