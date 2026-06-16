"""Common utilities for vunit simulator actions"""

# Shared `env` attribute used by every `vunit_*_sim` rule. Surfaced on
# the rule's `VUnitSimInfo.env` field; consumed by `vunit_test` when it
# builds the `--sim_env` list passed to the process wrapper. The doc
# describes the test-time precedence ordering.
SIM_ENV_ATTR = attr.string_dict(
    doc = (
        "Environment variables to set when the vunit runner invokes " +
        "this simulator at test time (license-server pointers, install " +
        "root vars, …). Precedence: toolchain `env` < sim `env` < " +
        "rule-level `vunit_test(env = ...)`."
    ),
    default = {},
)

VUnitSimOutputInfo = provider(
    doc = "Per-simulator outputs returned from a `compile()` function.",
    fields = {
        "build_args": "list[str]: Optional extra args forwarded as `VUnit.set_compile_option(...)`-style flags. Plumbed but not yet applied by the default `run.py`.",
        "runfiles": "Runfiles: The runfiles object carrying the simulator binaries, HDL sources, and standard libraries VUnit needs at test time.",
        "sim_env": """\
dict[str, str]: Environment variables to set when invoking the toolchain's
`run.py` at test time. Literal string values are set verbatim; values prefixed
with `abs:[upN:]<rlocationpath>` are resolved by the vunit process wrapper to
an absolute filesystem path, optionally walking N parent directories up (e.g.
`abs:up3:ghdl+/vhdl_libs_v08/ieee/v08/ieee-obj08.cf` resolves to the
`vhdl_libs_v08` root directory).
""",
        "test_args": "list[str]: Optional extra args appended to the `run.py` invocation (forwarded into VUnit's CLI parser, e.g. `--gtkwave-fmt fst`).",
    },
)

def _vunit_sim_info_init(*, all_files, bins, compile, name, env = {}, coverage = None):
    return {
        "all_files": all_files,
        "bins": bins,
        "compile": compile,
        "coverage": coverage,
        "env": env,
        "name": name,
    }

VUnitSimInfo, _ = provider(
    doc = """\
Common simulator interface required by the vunit toolchain.

`VUnitSimInfo` is the *only* contract `vunit_test` and `vunit_toolchain`
depend on — any target that returns it can plug into the toolchain's
`simulators` dict. The shipped `vunit_*_sim` rules each return one (plus
their own per-simulator extension provider, e.g. `VUnitSimGhdlInfo`), but
they aren't privileged in any way.

This is the public extension point for shipping a simulator the bundled
rules don't cover, or wrapping an install shape they don't fit (vendored
tarball, system `.deb`, internal corp build, ...). Write a Starlark rule
whose impl returns `VUnitSimInfo`, drop it into a `vunit_toolchain`
under the simulator name of your choice, and `vunit_test(sim = ...)`
resolves through it.

Simulator-specific providers (`VUnitSimGhdlInfo`, `VUnitSimNvcInfo`,
etc.) are only consumed by the corresponding shipped `compile` function —
custom rules don't need to return them unless they want to reuse a
shipped `compile`.
""",
    init = _vunit_sim_info_init,
    fields = {
        "all_files": "depset[File]: All transitive runfiles required by the simulator.",
        "bins": "dict[str, File]: Simulator binaries to place on PATH at test time. Keys are the expected binary names (e.g. {'ghdl': <File>} or {'vsim': <File>, 'vlog': <File>, 'vcom': <File>, 'vlib': <File>}).",
        "compile": "callable: A function with signature `compile(ctx, simulator, libraries, sim_opts) -> VUnitSimOutputInfo` that gathers and stages HDL sources for VUnit. `libraries` is a list of `(lib_name, target)` pairs.",
        "coverage": ("struct-or-None: Per-sim bridge from raw simulator " +
                     "coverage output to lcov for `bazel coverage`. When " +
                     "set AND the test is launched under `bazel coverage` " +
                     "(`ctx.configuration.coverage_enabled`), the process " +
                     "wrapper invokes the tool after the sim returns, " +
                     "producing lcov at `$COVERAGE_OUTPUT_FILE`. Sims " +
                     "without coverage support leave this `None`. Fields:\n" +
                     "  * `tool` (Target): the coverage tool target. `vunit_test` " +
                     "reads `tool[DefaultInfo].files_to_run.executable` for the " +
                     "executable path and `tool[DefaultInfo].default_runfiles` for " +
                     "the tool's runfiles tree — passing the target (not just the " +
                     "executable File) means rules_venv-based binaries get their " +
                     "venv_config + interpreter staged into the test runfiles.\n" +
                     "  * `args` (list[str]): args template. `{output}` is " +
                     "substituted with `$COVERAGE_OUTPUT_FILE`; `{data_files}` " +
                     "is expanded into one positional arg per file matched " +
                     "by `data_glob`. Other entries pass through verbatim.\n" +
                     "  * `data_glob` (str): shell glob relative to the " +
                     "VUnit output dir selecting the raw coverage artifacts " +
                     "the tool consumes (e.g. `**/*.covdb` for NVC)."),
        "env": "dict[str, str]: Environment variables this simulator needs when the vunit runner invokes it at test time (e.g. license-server pointers, install-root vars). Surfaced from the sim rule's `env` attr; defaults to `{}` when a sim integration omits it. Precedence at test time: toolchain `env` < sim `env` < rule-level `vunit_test(env = ...)`.",
        "name": "str: The VUnit simulator name this integration declares (e.g. \"ghdl\", \"nvc\", \"modelsim\"). Used to populate `VUNIT_SIMULATOR` at test time.",
    },
)
