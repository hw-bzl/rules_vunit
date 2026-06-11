"""VUnit NVC simulator integration"""

load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load(":vunit_sim_utils.bzl", "SIM_ENV_ATTR", "VUnitSimInfo", "VUnitSimOutputInfo")

VUnitSimNvcInfo = provider(
    doc = "NVC-specific extension of `VUnitSimInfo`.",
    fields = {
        "all_files": "depset[File]: All transitive runfiles required by the NVC tools.",
        "nvc": "File: The `nvc` simulator executable.",
    },
)

def nvc_compile(ctx, simulator, libraries, sim_opts):
    """Stage VHDL sources for an NVC simulation under VUnit.

    Args:
        ctx (ctx): The rule's context object.
        simulator (Target): The `vunit_nvc_sim` target.
        libraries (list): List of (lib_name, target) pairs (each target must
            provide `VhdlInfo`).
        sim_opts (list[str]): Forwarded to VUnit's CLI.

    Returns:
        VUnitSimOutputInfo: Source runfiles plus the `VUNIT_SIMULATOR` env var.
    """
    sim_info = simulator[VUnitSimNvcInfo]
    if not sim_info.nvc:
        fail("vunit_nvc_sim requires an nvc binary")

    transitive = []
    for _, lib_target in libraries:
        if VhdlInfo not in lib_target:
            fail("vunit_nvc_sim only supports VHDL libraries; `{}` lacks VhdlInfo.".format(
                lib_target.label,
            ))
        vhdl_info = lib_target[VhdlInfo]
        transitive.append(vhdl_info.srcs)
        transitive.append(vhdl_info.data)

    return VUnitSimOutputInfo(
        runfiles = ctx.runfiles(transitive_files = depset(transitive = transitive)),
        sim_env = {"VUNIT_SIMULATOR": "nvc"},
        test_args = list(sim_opts),
        build_args = [],
    )

def _vunit_nvc_sim_impl(ctx):
    all_files = ctx.attr.nvc[DefaultInfo].default_runfiles.files
    return [
        VUnitSimInfo(
            all_files = all_files,
            bins = {"nvc": ctx.executable.nvc},
            compile = nvc_compile,
            env = ctx.attr.env,
            name = "nvc",
        ),
        VUnitSimNvcInfo(
            all_files = all_files,
            nvc = ctx.executable.nvc,
        ),
    ]

vunit_nvc_sim = rule(
    doc = """\
A simulator configuration for running [NVC](https://www.nickg.me.uk/nvc/)
(open-source VHDL simulator) under VUnit.

### Status

Infrastructure only. NVC is open source but does not yet have a BCR
module, so `rules_vunit` cannot ship a default toolchain wired to it.
Wire it up downstream by pointing `nvc` at a `new_local_repository` /
`sh_binary` wrapper around a system install (or a custom Bazel build)
and registering a `vunit_toolchain` that routes `sim = "nvc"` through
this rule. VUnit's runner handles compilation and simulation at test
time.

### Notes

NVC only supports VHDL (`VhdlInfo`); pair it with `vhdl_library` targets
in the `libraries` map of `vunit_test`.
""",
    implementation = _vunit_nvc_sim_impl,
    attrs = {
        "env": SIM_ENV_ATTR,
        "nvc": attr.label(
            doc = "The `nvc` simulator binary.",
            executable = True,
            mandatory = True,
            cfg = "exec",
        ),
    },
)
