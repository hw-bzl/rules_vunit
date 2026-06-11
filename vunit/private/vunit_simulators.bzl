"""VUnit simulator dispatch"""

load(
    "//vunit/private/simulators:vunit_activehdl.bzl",
    _VUnitSimActiveHdlInfo = "VUnitSimActiveHdlInfo",
    _vunit_activehdl_sim = "vunit_activehdl_sim",
)
load(
    "//vunit/private/simulators:vunit_ghdl.bzl",
    _VUnitSimGhdlInfo = "VUnitSimGhdlInfo",
    _vunit_ghdl_sim = "vunit_ghdl_sim",
)
load(
    "//vunit/private/simulators:vunit_modelsim.bzl",
    _VUnitSimModelsimInfo = "VUnitSimModelsimInfo",
    _vunit_modelsim_sim = "vunit_modelsim_sim",
)
load(
    "//vunit/private/simulators:vunit_nvc.bzl",
    _VUnitSimNvcInfo = "VUnitSimNvcInfo",
    _vunit_nvc_sim = "vunit_nvc_sim",
)
load(
    "//vunit/private/simulators:vunit_questa.bzl",
    _VUnitSimQuestaInfo = "VUnitSimQuestaInfo",
    _vunit_questa_sim = "vunit_questa_sim",
)
load(
    "//vunit/private/simulators:vunit_riviera.bzl",
    _VUnitSimRivieraInfo = "VUnitSimRivieraInfo",
    _vunit_riviera_sim = "vunit_riviera_sim",
)
load(
    "//vunit/private/simulators:vunit_sim_utils.bzl",
    _VUnitSimInfo = "VUnitSimInfo",
    _VUnitSimOutputInfo = "VUnitSimOutputInfo",
)

VUnitSimActiveHdlInfo = _VUnitSimActiveHdlInfo
VUnitSimGhdlInfo = _VUnitSimGhdlInfo
VUnitSimInfo = _VUnitSimInfo
VUnitSimModelsimInfo = _VUnitSimModelsimInfo
VUnitSimNvcInfo = _VUnitSimNvcInfo
VUnitSimOutputInfo = _VUnitSimOutputInfo
VUnitSimQuestaInfo = _VUnitSimQuestaInfo
VUnitSimRivieraInfo = _VUnitSimRivieraInfo
vunit_activehdl_sim = _vunit_activehdl_sim
vunit_ghdl_sim = _vunit_ghdl_sim
vunit_modelsim_sim = _vunit_modelsim_sim
vunit_nvc_sim = _vunit_nvc_sim
vunit_questa_sim = _vunit_questa_sim
vunit_riviera_sim = _vunit_riviera_sim

def vunit_sim_compile(ctx, simulator, **kwargs):
    """Dispatch source-gathering to the simulator's compile function via its provider.

    Each `vunit_*_sim` target carries a `VUnitSimInfo` provider whose `compile`
    field references the simulator-specific compile function. This dispatcher
    simply calls it, removing the need for a static mapping of simulator names
    to functions.

    Args:
        ctx (ctx): The rule's context object.
        simulator (Target): The `vunit_*_sim` target that provides `VUnitSimInfo`.
        **kwargs: Arguments forwarded to the compile function (typically
            `libraries` and `sim_opts`).

    Returns:
        VUnitSimOutputInfo: The simulator's compile output.
    """
    return simulator[VUnitSimInfo].compile(ctx = ctx, simulator = simulator, **kwargs)
