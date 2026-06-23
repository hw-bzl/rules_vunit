"""vunit toolchain rules"""

load("@rules_venv//python:py_info.bzl", "PyInfo")
load(":vunit_simulators.bzl", "VUnitSimInfo")

def _vunit_toolchain_impl(ctx):
    simulators = {}
    for target, value in ctx.attr.simulators.items():
        if value in simulators:
            fail("The simulator '{}' is defined multiple times. Please update '{}'".format(
                value,
                ctx.label,
            ))
        simulators[value] = target

    return [platform_common.ToolchainInfo(
        vunit = ctx.attr.vunit,
        simulators = simulators,
        default_sim = ctx.attr.default_sim or None,
        env = ctx.attr.env,
        run_py = ctx.file.run_py,
        label = ctx.label,
    )]

vunit_toolchain = rule(
    doc = """\
Define a toolchain for `vunit_*` rules.

The toolchain bundles a `vunit` Python library, a set of HDL simulators
that `vunit_test` targets can select between via their `sim` attribute,
and the orchestration `run.py` the rule invokes at test time. Register
an instance with the standard `toolchain(...)` wrapper to make it
discoverable.

### Registering simulators

Each entry in `simulators` is a `vunit_*_sim` target keyed by the
*string* name that `vunit_test(sim = ...)` will use to select it.
Names are user-chosen — common conventions are `"ghdl"`, `"nvc"`,
`"modelsim"`, `"questa"`. Each name must be unique within the dict.

```python
load("@rules_vunit//vunit:vunit_ghdl_sim.bzl", "vunit_ghdl_sim")
load("@rules_vunit//vunit:vunit_toolchain.bzl", "vunit_toolchain")

vunit_ghdl_sim(
    name = "vunit_ghdl",
    ghdl = "@ghdl",
    vhdl_libs = ["@ghdl//:vhdl_libs_v08"],
)

vunit_toolchain(
    name = "my_vunit_toolchain",
    vunit = "//path/to:vunit_py_library",
    default_sim = "ghdl",
    simulators = {":vunit_ghdl": "ghdl"},
    # run_py defaults to //tools/rules_vunit_run:rules_vunit_run.py.
)

toolchain(
    name = "my_toolchain",
    toolchain = ":my_vunit_toolchain",
    toolchain_type = "@rules_vunit//vunit:toolchain_type",
)
```

Add `register_toolchains("//path/to:my_toolchain")` to `MODULE.bazel`
ahead of `//vunit/toolchain` to override the default. `default_sim`
chooses which simulator runs when a `vunit_test` omits its own `sim`
attribute; it's optional, but if set must name one of the keys in
`simulators`.

### Customising `run.py`

The default `run.py` (shipped at
`//tools/rules_vunit_run:rules_vunit_run.py`) reads a JSON descriptor
from `VUNIT_LIBRARIES_JSON`, declares each library with
`vu.add_library(...)` / `lib.add_source_file(...)`, and calls
`vu.main()`. Override it via the `run_py` attribute when you need extra
configuration — custom test attributes, `set_sim_option(...)` calls,
`post_run` hooks, etc. The wrapper always sets:

* `VUNIT_LIBRARIES_JSON` — path to the resolved library/sources JSON.
* `VUNIT_OUTPUT_PATH` — sandboxed directory to pass as `-o`.
* `VUNIT_XUNIT_XML` — path to write the xunit XML to (pass as `-x`).

The script runs inside the venv composed by the `vunit_test` rule:
`toolchain.vunit` is on `sys.path`, plus anything the test pulls in via
its own `deps` attribute. So a custom `run.py` just needs to `import
vunit` and any helper packages declared on the test target.

The default driver's plumbing is also exposed as a Python library —
`from rules_vunit_run import load_manifest,
ensure_vunit_verilog_path_is_plus_free, vunit_builtin_verilog_include_dir,
configure_coverage` — so a custom `run.py` can reuse the manifest
loader, the bzlmod `+`-in-path workaround for Aldec, and the coverage
hook instead of vendoring them. Add
`@rules_vunit//tools/rules_vunit_run` to the test target's `deps` to
make the import resolve.

Per-simulator API and wiring details live in the
[Simulators](./simulators.md) section.
""",
    implementation = _vunit_toolchain_impl,
    attrs = {
        "default_sim": attr.string(
            doc = "An optional default simulator to use.",
        ),
        "env": attr.string_dict(
            doc = (
                "Environment variables to set whenever the toolchain " +
                "invokes a simulator. Applied to every sim registered " +
                "in `simulators`; for sim-specific vars (license server, " +
                "install root, etc.) prefer the per-`vunit_*_sim` `env` " +
                "attr instead. Precedence at test time: toolchain `env` " +
                "< sim `env` < rule-level `vunit_test(env = ...)`."
            ),
            default = {},
        ),
        "run_py": attr.label(
            doc = "The Python orchestration script the `vunit_test` rule invokes. Defaults to a shipped driver that wires VUnit up from a JSON library descriptor; override with your own `.py` when you need custom orchestration (hooks, per-test attributes, etc.). Python deps for the script come from the toolchain's `vunit` py_library plus the test's `deps` — both are stitched into the venv that runs the script.",
            allow_single_file = [".py"],
            default = Label("//tools/rules_vunit_run:rules_vunit_run.py"),
        ),
        "simulators": attr.label_keyed_string_dict(
            doc = "A mapping of `vunit_*_sim` targets to their matching simulator names. Every target must provide `VUnitSimInfo`.",
            allow_empty = False,
            mandatory = True,
            cfg = "exec",
            providers = [
                [VUnitSimInfo],
            ],
        ),
        "vunit": attr.label(
            doc = "The `vunit` python library.",
            providers = [PyInfo],
            mandatory = True,
            cfg = "exec",
        ),
    },
)

def _current_vunit_toolchain_lib_impl(ctx):
    toolchain = ctx.toolchains[Label("//vunit:toolchain_type")]
    vunit_target = toolchain.vunit

    # For some reason, simply forwarding `DefaultInfo` from
    # the target results in a loss of data. To avoid this a
    # new provider is created with the same info.
    default_info = DefaultInfo(
        files = vunit_target[DefaultInfo].files,
        runfiles = vunit_target[DefaultInfo].default_runfiles,
    )

    return [
        default_info,
        vunit_target[PyInfo],
        vunit_target[OutputGroupInfo],
        vunit_target[InstrumentedFilesInfo],
    ]

current_vunit_toolchain_lib = rule(
    doc = "Match and expose the `vunit_toolchain` for the current configuration.",
    implementation = _current_vunit_toolchain_lib_impl,
    toolchains = [
        str(Label("//vunit:toolchain_type")),
    ],
)
