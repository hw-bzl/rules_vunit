"""VUnit rules"""

load(
    "//vunit/private:vunit_precompiled_library_info.bzl",
    _VUnitPrecompiledLibraryInfo = "VUnitPrecompiledLibraryInfo",
)
load(
    ":vunit_activehdl_sim.bzl",
    _vunit_activehdl_sim = "vunit_activehdl_sim",
)
load(
    ":vunit_ghdl_sim.bzl",
    _vunit_ghdl_sim = "vunit_ghdl_sim",
)
load(
    ":vunit_modelsim_sim.bzl",
    _vunit_modelsim_sim = "vunit_modelsim_sim",
)
load(
    ":vunit_nvc_sim.bzl",
    _vunit_nvc_sim = "vunit_nvc_sim",
)
load(
    ":vunit_questa_sim.bzl",
    _vunit_questa_sim = "vunit_questa_sim",
)
load(
    ":vunit_riviera_sim.bzl",
    _vunit_riviera_sim = "vunit_riviera_sim",
)
load(
    ":vunit_test.bzl",
    _vunit_test = "vunit_test",
)
load(
    ":vunit_toolchain.bzl",
    _vunit_toolchain = "vunit_toolchain",
)

VUnitPrecompiledLibraryInfo = _VUnitPrecompiledLibraryInfo
vunit_activehdl_sim = _vunit_activehdl_sim
vunit_ghdl_sim = _vunit_ghdl_sim
vunit_modelsim_sim = _vunit_modelsim_sim
vunit_nvc_sim = _vunit_nvc_sim
vunit_questa_sim = _vunit_questa_sim
vunit_riviera_sim = _vunit_riviera_sim
vunit_test = _vunit_test
vunit_toolchain = _vunit_toolchain
