"""VUnit GHDL simulator integration"""

load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load(":vunit_sim_utils.bzl", "SIM_ENV_ATTR", "VUnitSimInfo", "VUnitSimOutputInfo")

def _vhdl_lib_root_rloc(ctx, vhdl_libs):
    """Return a runtime rlocation spec for the VHDL library root.

    Picks any `.cf` file from `vhdl_libs` (laid out as
    `<root>/{std,ieee}/v<XX>/<name>.cf`) and returns its rlocationpath
    prefixed with `up3:` — the vunit process wrapper resolves the runfile
    and walks 3 parent directories to land on `<root>`, which is what GHDL
    expects in `GHDL_PREFIX`.
    """
    for f in vhdl_libs.to_list():
        if not f.basename.endswith(".cf"):
            continue
        if f.short_path.startswith("../"):
            rloc = f.short_path[len("../"):]
        else:
            rloc = "{}/{}".format(ctx.workspace_name, f.short_path)
        return "up3:" + rloc
    return ""

VUnitSimGhdlInfo = provider(
    doc = "GHDL-specific extension of `VUnitSimInfo`.",
    fields = {
        "all_files": "depset[File]: All transitive runfiles required by the GHDL tools.",
        "ghdl": "File: The `ghdl` executable.",
        "ghdl_prefix": "str: Literal value to set as `GHDL_PREFIX` at sim time. Empty falls back to deriving from `vhdl_libs` (BCR layout) or to ghdl's compiled-in defaults.",
        "vhdl_libs": "depset[File]: Pre-compiled VHDL standard library files for GHDL_PREFIX (BCR-shaped layout).",
    },
)

def ghdl_compile(ctx, simulator, libraries, sim_opts):
    """Stage VHDL sources and GHDL standard libraries for a VUnit run.

    VUnit drives GHDL through `vu.main()` at test time — no Bazel-time
    `ghdl -a` runs. The JIT backends (`mcode`, `llvm-jit`) bake absolute
    paths into `.cf` metadata, so any sandbox-time work directory wouldn't
    be relocatable to the test sandbox. Instead this function gathers the
    sources from each library target and rolls them into the runfiles;
    `vunit_test` writes them into `libraries.json` and the toolchain's
    `run.py` adds them via `lib.add_source_file(...)`.

    Args:
        ctx (ctx): The rule's context object.
        simulator (Target): The `vunit_ghdl_sim` target.
        libraries (list): List of (lib_name, target) pairs. Each target
            must provide `VhdlInfo` (Verilog inputs aren't valid for GHDL).
        sim_opts (list[str]): Forwarded to VUnit's CLI.

    Returns:
        VUnitSimOutputInfo: Provider carrying source runfiles, env vars,
        and CLI extras.
    """
    sim_info = simulator[VUnitSimGhdlInfo]

    transitive = [sim_info.vhdl_libs]
    for _, lib_target in libraries:
        if VhdlInfo not in lib_target:
            fail("vunit_ghdl_sim only supports VHDL libraries; `{}` lacks VhdlInfo.".format(
                lib_target.label,
            ))
        vhdl_info = lib_target[VhdlInfo]
        transitive.append(vhdl_info.srcs)
        transitive.append(vhdl_info.data)

    sim_env = {"VUNIT_SIMULATOR": "ghdl"}
    if sim_info.ghdl_prefix:
        # Literal path override — appropriate for system installs that know
        # their own prefix (e.g. "/usr/lib/ghdl" on a Debian system).
        sim_env["GHDL_PREFIX"] = sim_info.ghdl_prefix
    else:
        # Fall back to deriving GHDL_PREFIX from BCR-shaped `vhdl_libs`
        # (`<root>/{std,ieee}/v<XX>/...`). If `vhdl_libs` is empty, no
        # GHDL_PREFIX is set — ghdl uses its built-in defaults.
        rloc = _vhdl_lib_root_rloc(ctx, sim_info.vhdl_libs)
        if rloc:
            sim_env["GHDL_PREFIX"] = "abs:" + rloc

    if ctx.attr.coverage:
        # Emit the GHDL-side coverage flags via the generic
        # `VUNIT_COVERAGE_SIM_OPTIONS` contract the default `run.py` reads.
        # `--coverage` translates (at the gcc backend) into
        # `-fprofile-arcs -ftest-coverage` on both the analyze and elab
        # passes, instrumenting the generated objects for gcov.
        #
        # TODO: only the gcc backend actually emits coverage; the BCR
        # `ghdl` module ships `mcode` and `llvm-jit` only, so this path
        # is wired-but-untested against a stock BCR build. See the
        # `### Coverage` section of `vunit_ghdl_sim`'s doc.
        sim_env["VUNIT_COVERAGE_SIM_OPTIONS"] = json.encode({
            "ghdl.a_flags": ["--coverage"],
            "ghdl.elab_flags": ["--coverage"],
        })

    return VUnitSimOutputInfo(
        runfiles = ctx.runfiles(transitive_files = depset(transitive = transitive)),
        sim_env = sim_env,
        test_args = list(sim_opts),
        build_args = [],
    )

def _vunit_ghdl_sim_impl(ctx):
    vhdl_libs = depset(transitive = [t.files for t in ctx.attr.vhdl_libs])
    all_files = depset(
        transitive = [
            ctx.attr.ghdl[DefaultInfo].default_runfiles.files,
            vhdl_libs,
        ],
    )
    ghdl_exe = ctx.executable.ghdl

    return [
        VUnitSimInfo(
            all_files = all_files,
            bins = {"ghdl": ghdl_exe},
            compile = ghdl_compile,
            env = ctx.attr.env,
            name = "ghdl",
        ),
        VUnitSimGhdlInfo(
            all_files = all_files,
            ghdl = ghdl_exe,
            ghdl_prefix = ctx.attr.ghdl_prefix,
            vhdl_libs = vhdl_libs,
        ),
    ]

vunit_ghdl_sim = rule(
    doc = """\
A simulator configuration for running [GHDL](https://ghdl.github.io/ghdl/)
simulations in VUnit tests.

### Status

Working against the BCR `ghdl` module from version `6.0.0.bcr.1` onward.
The backend is selectable with `--@ghdl//:backend={mcode, llvm-jit}`
(default `mcode` on x86_64, `llvm-jit` elsewhere).

### Notes

GHDL only supports VHDL (`VhdlInfo`); pair it with `vhdl_library` targets
in the `libraries` map of `vunit_test`. VUnit drives `ghdl` directly via
its `vu.main()` at test time using sources surfaced through runfiles.

The `vhdl_libs` attribute should point at the pre-compiled IEEE/std
libraries from the BCR `ghdl` module — most projects want
`["@ghdl//:vhdl_libs_v08"]`.

### Coverage

When `coverage = True` is set on a `vunit_test` resolving to this
simulator, `ghdl_compile` publishes
`{"ghdl.a_flags": ["--coverage"], "ghdl.elab_flags": ["--coverage"]}`
via the sim-agnostic `VUNIT_COVERAGE_SIM_OPTIONS` env contract that
the default `run.py` reads (see `_configure_coverage` in
`//tools/run:run.py`). The default driver applies the dict verbatim
via `vu.set_sim_option(...)`; no GHDL-specific code lives in the
driver.

TODO: GHDL only emits coverage data when built with the `gcc` backend.
The BCR `ghdl` module ships only the `mcode` and `llvm-jit` backends —
neither supports coverage — so the wired-up `--coverage` flags are a
no-op (or runtime error) against a stock BCR build. A consumer who
points `vunit_ghdl_sim(ghdl = ...)` at their own GHDL+gcc binary
picks up real coverage out of these flags. The rules_vunit CI cannot
exercise this path today.
""",
    implementation = _vunit_ghdl_sim_impl,
    attrs = {
        "env": SIM_ENV_ATTR,
        "ghdl": attr.label(
            doc = "The `ghdl` binary.",
            executable = True,
            mandatory = True,
            cfg = "exec",
        ),
        "ghdl_prefix": attr.string(
            doc = """\
Literal value to set as `GHDL_PREFIX` at simulation time. Use this for
ghdl installs where the prefix is a stable absolute path on disk —
typically a system/`.deb`/Homebrew install (e.g. `"/usr/lib/ghdl"`).

When unset (default), `GHDL_PREFIX` is auto-derived from `vhdl_libs` if
it's populated (BCR-shaped layout), otherwise left unset so ghdl falls
back to its own compiled-in search paths.
""",
        ),
        "vhdl_libs": attr.label_list(
            doc = """\
Pre-compiled VHDL standard libraries (e.g. `@ghdl//:vhdl_libs_v08`).
**Assumes the BCR `ghdl` module's layout** —
`<root>/{std,ieee}/v<XX>/<name>-objXX.cf` — from which `GHDL_PREFIX`
is derived. If you ship ghdl differently and the IEEE/std libs are
already discoverable by the binary, leave this empty and (optionally)
set `ghdl_prefix` to a literal path, or skip both for a system install
that uses its compiled-in defaults.
""",
            allow_files = True,
            cfg = "exec",
        ),
    },
)
