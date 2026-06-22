# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2026 Ainekko, Co.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

export HDLET_ROOT=`git rev-parse --show-toplevel`
# NoC interconnect filelist selector (swap point). Default: the open-source
# erbium_noc stub. Pre-export NOC_FLIST before sourcing this file to point at a
# different NoC filelist, e.g. the proprietary NIC-700 (ip/ni700_ErbiumET).
export NOC_FLIST=${NOC_FLIST:-$HDLET_ROOT/ip/erbium_noc/flow/erbium_noc.f}
# Include dirs for the selected NoC, injected on the VCS command line via
# COMPILE_ARGS in tb/Makefile. These must be fully-resolved absolute paths:
# VCS does not expand env vars inside +incdir+ tokens, nor relocate relative
# +incdir+ paths reached through -F, so passing them through the NoC filelist
# does not work. Override alongside NOC_FLIST when swapping in a different NoC.
export NOC_INCDIRS=${NOC_INCDIRS:-"+incdir+$HDLET_ROOT/ip/erbium_noc/deps/common_cells/include +incdir+$HDLET_ROOT/ip/erbium_noc/deps/axi/include"}
# Proprietary NIC-700 generator output path (only used when the NIC-700 is
# swapped in; absent in the default checkout, which is fine for the stub).
export BOOKER_NCI=$HDLET_ROOT/ip/ni700_ErbiumET/logical/ni700_ErbiumET/logical/ni700_ErbiumET
export REPOROOT=$HDLET_ROOT/ip/cpu_subsystem/
export RTLROOT=$REPOROOT/rtl
export BSC_PATH=/prj/bsvlib/bdir:+
# Bluespec-generated Verilog primitive libraries used by the RTL filelists.
# Defaults preserve the historical install paths/versions; override to point at
# a Bluespec install in an arbitrary path. BSC_VLIB_TOP is used by the top
# integration filelists, BSC_VLIB_ET by the MRAM (erbium-et) bridge.
export BSC_VLIB_TOP=${BSC_VLIB_TOP:-/tools/opt/bsc/latest/lib/Verilog}
export BSC_VLIB_ET=${BSC_VLIB_ET:-/tools/bluespec/2025.07/lib/Verilog}
export PYTHONPATH=$PYTHONPATH:$HDLET_ROOT
export MINION_DIAGS=$HDLET_ROOT/tb/c_asm_tests

source $HDLET_ROOT/scripts/select_riscv_tools.sh

function update_submodules {
	cd ip/xspi && git checkout feature/hb_debug && git pull && cd -
	cd ip/cpu_subsystem && git checkout main && git pull && cd -
	cd ip/i2c && git checkout master && git pull && cd -
	cd ip/mram_axi_bridge && git checkout erbium/dev && git submodule update && git pull && cd -
	cd ip/erbium_noc && git checkout main && git pull && cd -
	# Proprietary NIC-700 (tapeout only; absent in the open-source checkout)
	[ -d ip/ni700_ErbiumET ] && { cd ip/ni700_ErbiumET && git checkout main && git pull && cd -; }
}
