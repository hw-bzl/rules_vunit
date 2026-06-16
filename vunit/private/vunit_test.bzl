"""VUnit test rule"""

load("@rules_venv//python:py_info.bzl", "PyInfo")
load("@rules_venv//python/venv:defs.bzl", "py_venv_common")
load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")
load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load(":vunit_precompiled_library_info.bzl", "VUnitPrecompiledLibraryInfo")
load(":vunit_simulators.bzl", "VUnitSimInfo", "vunit_sim_compile")

# VUnit simulator name → precompiled-library `format` family. Mirrors the
# same mapping cocotb's `_SIM_FORMAT` uses (rules_cocotb owns the cocotb
# side); shared families let a single downstream rule emit both providers
# from one action.
_SIM_FORMAT = {
    "activehdl": "aldec",
    "ghdl": "ghdl",
    "modelsim": "mentor",
    "nvc": "nvc",
    "questa": "mentor",
    "rivierapro": "aldec",
}

def _rlocationpath(file, workspace_name):
    """A convenience method for producing the `rlocationpath` of a file."""
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _build_libraries_from_module(module):
    """Walk a module's transitive HDL DAG and group sources by VUnit library.

    Returns `(grouped, source_depset)`. `grouped` maps
    `lib_name -> {"vhdl_sources": [File], "verilog_sources": [File]}`;
    rlocationpath conversion is deferred to `_libraries_json_map_fn` so
    File-to-path conversion happens at action time and any active path
    mapping is honored. `source_depset` is the union of all HDL files
    referenced (used to extend runfiles).

    Each reachable `VhdlInfo` contributes its sources under its own
    `library` field (falling back to `"work"` — the VHDL default — when
    unset). Verilog has no equivalent per-target library; all reachable
    `VerilogInfo` sources land in the module's own VHDL `library` when
    `module` is a `vhdl_library` (so a mixed-language testbench compiles
    everything into one library by default), otherwise `"work"`.

    `VhdlInfo.deps` and `VerilogInfo.deps` are already transitive
    depsets of their respective providers — no aspect needed; the
    rules populate the full DAG.
    """
    grouped = {}
    source_depsets = []

    verilog_lib_name = "work"

    if VhdlInfo in module:
        info = module[VhdlInfo]
        if info.library:
            verilog_lib_name = info.library

        # `.deps` is the TRANSITIVE depset; appending the root's own info
        # picks up its direct sources too.
        for v in info.deps.to_list() + [info]:
            lib_name = v.library or "work"
            entry = grouped.setdefault(lib_name, {"verilog_sources": [], "vhdl_sources": []})
            source_depsets.append(v.srcs)
            source_depsets.append(v.data)
            for f in v.srcs.to_list():
                entry["vhdl_sources"].append(f)

    if VerilogInfo in module:
        info = module[VerilogInfo]
        entry = grouped.setdefault(verilog_lib_name, {"verilog_sources": [], "vhdl_sources": []})
        for v in info.deps.to_list() + [info]:
            source_depsets.append(v.srcs)
            source_depsets.append(v.data)
            for f in v.srcs.to_list():
                entry["verilog_sources"].append(f)

    return grouped, depset(transitive = source_depsets)

def _libraries_json_map_fn(value):
    """Build the libraries.json content from a (grouped, workspace_name) tuple.

    Invoked lazily by `args.add_all(map_each = ...)` at action execution
    time. Doing the File-to-rlocationpath conversion here (rather than at
    analysis time) lets Bazel apply path mapping
    (`--experimental_output_paths=strip` and friends) to `File.path`-derived
    strings before they're baked into the output JSON.
    """
    grouped, workspace_name = value
    descriptor = {}
    for lib_name in sorted(grouped.keys()):
        entry = grouped[lib_name]
        descriptor[lib_name] = {
            "verilog_sources": sorted([
                _rlocationpath(f, workspace_name)
                for f in entry["verilog_sources"]
            ]),
            "vhdl_sources": sorted([
                _rlocationpath(f, workspace_name)
                for f in entry["vhdl_sources"]
            ]),
        }
    return json.encode_indent(descriptor, indent = "  ")

def _vunit_test_impl(ctx):
    toolchain = ctx.toolchains[Label("//vunit:toolchain_type")]
    venv_toolchain = py_venv_common.get_toolchain(ctx)

    sim = toolchain.default_sim
    if ctx.attr.sim:
        sim = ctx.attr.sim
    if not sim:
        fail("No simulator chosen for `{}`".format(ctx.label))

    if sim not in toolchain.simulators:
        fail("No simulator '{}' provided in the current `vunit_toolchain` {}. Options are: {}".format(
            sim,
            toolchain.label,
            ", ".join(toolchain.simulators.keys()),
        ))
    simulator = toolchain.simulators[sim]
    sim_info = simulator[VUnitSimInfo]

    # Validate precompiled_libs at analysis time so a format-vs-sim mismatch
    # fails the build instead of leaking into a confusing runtime error.
    expected_format = _SIM_FORMAT.get(sim_info.name)
    for lib in ctx.attr.precompiled_libs:
        lib_info = lib[VUnitPrecompiledLibraryInfo]
        if expected_format and lib_info.format != expected_format:
            fail(
                ("`{tgt}` attaches precompiled library `{lib}` of format " +
                 "`{lib_format}`, but the test's simulator `{sim}` belongs " +
                 "to format family `{expected}`. Recompile the library for " +
                 "`{expected}` or switch the test's `sim`.").format(
                    tgt = ctx.label,
                    lib = lib.label,
                    lib_format = lib_info.format,
                    sim = sim_info.name,
                    expected = expected_format,
                ),
            )

    libraries_grouped, source_depset = _build_libraries_from_module(
        ctx.attr.module,
    )

    # Hand the per-sim `compile` function a `[(lib_name, root_target)]`
    # single-entry list rather than per-library tuples — the transitive
    # DAG was already walked by `_build_libraries_from_module` and its
    # sources flow into the test's runfiles via `source_depset` below.
    # Sims that need richer per-library structure (e.g. emitting per-lib
    # compile options) would need to walk `module[<Info>].deps` themselves;
    # none of the shipped integrations do today.
    sim_output = vunit_sim_compile(
        ctx = ctx,
        simulator = simulator,
        libraries = [("__module__", ctx.attr.module)],
        sim_opts = ctx.attr.sim_opts,
    )

    # Compose the simulator subprocess env from four layers, right-side
    # wins on overlap (matches `cocotb_test`'s ordering):
    #   1. `toolchain.env` — toolchain-wide defaults (rare; useful when
    #      multiple sims share an install).
    #   2. `sim_info.env` — declared on the `vunit_*_sim` rule. Natural
    #      home for sim-specific install vars (license server, install
    #      root). `VUnitSimInfo`'s init guarantees this is at least `{}`.
    #   3. `sim_output.sim_env` — derived at compile time by the sim's
    #      `compile` function (e.g. `VUNIT_SIMULATOR`).
    #   4. `ctx.attr.env` — per-`vunit_test` override; also flows into
    #      `RunEnvironmentInfo` below for the test process env so the
    #      test and its simulator subprocess see the same values.
    #      Expanded for make-variables / `$(rlocationpath ...)` against
    #      `ctx.attr.data` so users can reference data deps by label.
    expanded_user_env = {
        k: ctx.expand_location(v, ctx.attr.data)
        for k, v in ctx.attr.env.items()
    }
    sim_env = (
        toolchain.env |
        sim_info.env |
        (getattr(sim_output, "sim_env", None) or {}) |
        expanded_user_env
    )
    sim_test_args = getattr(sim_output, "test_args", None) or []

    libraries_json = ctx.actions.declare_file("{}.libraries.json".format(ctx.label.name))
    libraries_args = ctx.actions.args()
    libraries_args.set_param_file_format("multiline")
    libraries_args.add_all(
        [(libraries_grouped, ctx.workspace_name)],
        map_each = _libraries_json_map_fn,
    )
    ctx.actions.write(
        output = libraries_json,
        content = libraries_args,
    )

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add("--sim", sim)
    for bin_name, bin_file in sim_info.bins.items():
        args.add("--sim_bin={}:{}".format(
            bin_name,
            _rlocationpath(bin_file, ctx.workspace_name),
        ))
    for name, value in sim_env.items():
        args.add("--sim_env={}={}".format(name, value))
    args.add("--run_py", _rlocationpath(toolchain.run_py, ctx.workspace_name))
    args.add("--libraries_json", _rlocationpath(libraries_json, ctx.workspace_name))
    for a in sim_test_args:
        args.add("--vunit_arg={}".format(a))

    # Precompiled libs the test should link before compiling its own
    # sources. The wrapper's per-format runner patch emits the link
    # directive (e.g. `vmap -link` for Aldec). Encoded as
    # `format:vendor:flags:rlocationpath`, where `flags` is a comma-
    # separated subset of `{links_secureip, provides_glbl}` advertising
    # ecosystem quirks the run.py needs to apply (e.g. `-L secureip` link
    # flag, glbl sibling-top injection). `vendor` is advisory only — the
    # behavioral hooks read the typed flags, not the vendor string.
    for lib in ctx.attr.precompiled_libs:
        lib_info = lib[VUnitPrecompiledLibraryInfo]
        flags = []
        if lib_info.links_secureip:
            flags.append("links_secureip")
        if lib_info.provides_glbl:
            flags.append("provides_glbl")
        args.add("--precompiled_lib_dir={}:{}:{}:{}".format(
            lib_info.format,
            lib_info.vendor,
            ",".join(flags),
            _rlocationpath(lib_info.library_dir, ctx.workspace_name),
        ))

    # Coverage is gated solely by `bazel coverage` (via
    # `ctx.configuration.coverage_enabled`, which Bazel flips on whenever
    # `--collect_code_coverage` is in effect — `bazel coverage` sets it
    # implicitly). No per-target attr. We use the configuration flag
    # rather than `ctx.coverage_instrumented()` because the latter
    # additionally requires the rule to produce an `InstrumentedFilesInfo`
    # provider — meaningful for source-language rules where Bazel tracks
    # which files to instrument, but a bad fit for HDL where the simulator
    # decides what to instrument from its compile list. The artifact
    # lands under VUnit's output dir, which the wrapper points at
    # `TEST_UNDECLARED_OUTPUTS_DIR/vunit_out` so Bazel gathers it without
    # the rule needing a declared output.
    coverage_runfiles = ctx.runfiles()
    if ctx.configuration.coverage_enabled:
        args.add("--coverage")

        # When the resolved sim ships a coverage post-processor, plumb the
        # tool + its data glob + its args template so the wrapper can
        # translate the sim's raw coverage output into lcov at
        # `$COVERAGE_OUTPUT_FILE`. Sims that don't have coverage support
        # (the commercial stubs, GHDL until its gcc backend is wired)
        # leave `coverage = None`; the wrapper then no-ops the post-step.
        if sim_info.coverage:
            # `sim_info.coverage.tool` is a Target — pull its executable
            # File for the wrapper arg AND its default_runfiles so the
            # whole tool (launcher + interpreter + helper data) is
            # available to the test at runtime. A `File` would only
            # ship the launcher script and miss the venv_config /
            # interpreter / sibling .py files rules_venv-based
            # binaries need to start up.
            tool_exec = sim_info.coverage.tool[DefaultInfo].files_to_run.executable
            args.add("--coverage_tool={}".format(
                _rlocationpath(tool_exec, ctx.workspace_name),
            ))
            args.add("--coverage_data_glob={}".format(sim_info.coverage.data_glob))
            for a in sim_info.coverage.args:
                args.add("--coverage_arg={}".format(a))
            coverage_runfiles = ctx.runfiles(files = [tool_exec]).merge(
                sim_info.coverage.tool[DefaultInfo].default_runfiles,
            )

    args_file = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = args,
    )

    # The wrapper venv carries the process wrapper, the active toolchain's
    # `vunit` py_library (so `run.py` can `import vunit`), and any extra
    # Python deps the test target declares.
    dep_info = py_venv_common.create_dep_info(
        ctx = ctx,
        deps = [ctx.attr._runner, toolchain.vunit] + ctx.attr.deps,
    )

    py_info = py_venv_common.create_py_info(
        ctx = ctx,
        imports = [],
        srcs = [ctx.file._runner_main, toolchain.run_py],
        dep_info = dep_info,
    )

    precompiled_lib_dirs = [
        lib[VUnitPrecompiledLibraryInfo].library_dir
        for lib in ctx.attr.precompiled_libs
    ]
    direct_files = sim_info.bins.values() + [
        args_file,
        libraries_json,
        toolchain.run_py,
    ] + ctx.files.data + precompiled_lib_dirs

    direct_runfiles = ctx.runfiles(
        files = direct_files,
        transitive_files = depset(transitive = [sim_info.all_files, source_depset]),
    ).merge_all([
        dep_info.runfiles,
        sim_output.runfiles,
        coverage_runfiles,
    ] + [
        target[DefaultInfo].default_runfiles
        for target in ctx.attr.data
        if DefaultInfo in target
    ])

    executable, runfiles = py_venv_common.create_venv_entrypoint(
        ctx = ctx,
        venv_toolchain = venv_toolchain,
        py_info = py_info,
        main = ctx.file._runner_main,
        runfiles = direct_runfiles,
    )

    return [
        RunEnvironmentInfo(
            environment = expanded_user_env | {
                "VUNIT_TEST_ARGS_FILE": _rlocationpath(args_file, ctx.workspace_name),
            },
        ),
        DefaultInfo(
            executable = executable,
            files = depset([executable]),
            runfiles = runfiles,
        ),
        coverage_common.instrumented_files_info(
            ctx,
            source_attributes = ["module"],
            dependency_attributes = ["module"],
            extensions = ["vhd", "vhdl", "v", "sv", "vh", "svh"],
        ),
    ]

vunit_test = rule(
    doc = "Run a VUnit test over the given HDL libraries.",
    implementation = _vunit_test_impl,
    attrs = {
        "data": attr.label_list(
            doc = "Additional runtime data used by the test.",
            allow_files = True,
        ),
        "deps": attr.label_list(
            doc = "Extra Python dependencies merged into the wrapper's venv. Use this to make helper packages importable from a custom toolchain `run.py`.",
            providers = [PyInfo],
        ),
        "env": attr.string_dict(
            doc = "Environment variables to set for the test.",
        ),
        "module": attr.label(
            doc = ("Root HDL library target whose transitive " +
                   "`VhdlInfo`/`VerilogInfo` `deps` are walked to discover " +
                   "every source the test should compile. Each reachable " +
                   "`VhdlInfo` contributes its sources under its own " +
                   "`library` field (fallback `\"work\"`). Verilog sources " +
                   "land in the module's own VHDL `library` when `module` " +
                   "is a `vhdl_library` (mixed-language testbench → one " +
                   "shared library by default), otherwise `\"work\"`. " +
                   "`VhdlInfo.deps` / `VerilogInfo.deps` are already " +
                   "transitive depsets, so no aspect or extra walking " +
                   "machinery is involved — the provider IS the DAG."),
            providers = [[VhdlInfo], [VerilogInfo]],
            mandatory = True,
        ),
        "precompiled_libs": attr.label_list(
            doc = ("Precompiled simulator library sets to link before the " +
                   "test's own compile step. Each target must produce a " +
                   "`VUnitPrecompiledLibraryInfo` whose `simulator` field " +
                   "matches this test's resolved sim (analysis-time " +
                   "check). At runtime the per-format runner patch in " +
                   "`vunit_process_wrapper` emits the vendor's link " +
                   "directive (`vmap -link` for Aldec, etc.) so HDL that " +
                   "references libraries inside the precompiled set (e.g. " +
                   "Xilinx's `xil_defaultlib`, `unisim`) resolves."),
            providers = [VUnitPrecompiledLibraryInfo],
            default = [],
        ),
        "sim": attr.string(
            doc = "The name of the simulator to use. Must match a key in the vunit_toolchain's `simulators` dict.",
        ),
        "sim_opts": attr.string_list(
            doc = "Additional command line arguments to forward to the simulator via VUnit.",
        ),
        "_runner": attr.label(
            doc = "The process wrapper for running vunit tests.",
            default = Label("//tools/vunit_process_wrapper"),
            providers = [PyInfo],
        ),
        "_runner_main": attr.label(
            doc = "The main entrypoint for the vunit process.",
            allow_single_file = True,
            default = Label("//tools/vunit_process_wrapper:vunit_process_wrapper.py"),
        ),
    } | py_venv_common.create_venv_attrs(),
    toolchains = [
        "@rules_cc//cc:toolchain_type",
        "@rules_python//python/cc:toolchain_type",
        str(Label("//vunit:toolchain_type")),
        py_venv_common.TOOLCHAIN_TYPE,
    ],
    fragments = ["cpp"],
    test = True,
)
