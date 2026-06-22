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

# Bluespec toolchain root. If the user provides BLUESPEC_HOME, make its bsc
# visible. Otherwise, if bsc is already visible, infer BLUESPEC_HOME from it.
if [ -n "$BLUESPEC_HOME" ]; then
	case ":$PATH:" in
		*":$BLUESPEC_HOME/bin:"*) : ;;
		*) export PATH="$BLUESPEC_HOME/bin:$PATH" ;;
	esac
elif command -v bsc >/dev/null 2>&1; then
	_bsc_bin="$(command -v bsc)"
	export BLUESPEC_HOME="$(cd "$(dirname "$_bsc_bin")/.." && pwd)"
	unset _bsc_bin
fi

# Filelists consume the generated primitive Verilog directory directly. Keep
# explicit BSC_VLIB_* overrides, otherwise derive both from BLUESPEC_HOME.
if [ -n "$BLUESPEC_HOME" ] && [ -d "$BLUESPEC_HOME/lib/Verilog" ]; then
	: "${BSC_VLIB_TOP:=$BLUESPEC_HOME/lib/Verilog}"
	: "${BSC_VLIB_ET:=$BLUESPEC_HOME/lib/Verilog}"
fi
if [ -z "$BSC_VLIB_TOP" ] || [ -z "$BSC_VLIB_ET" ]; then
	echo "Warning: BSC_VLIB_TOP/BSC_VLIB_ET not set; set them directly, set BLUESPEC_HOME, or put bsc on PATH if this flow needs Bluespec Verilog primitives." >&2
fi
export BSC_VLIB_TOP
export BSC_VLIB_ET
export PYTHONPATH=$PYTHONPATH:$HDLET_ROOT
export MINION_DIAGS=$HDLET_ROOT/tb/c_asm_tests

# RISC-V toolchain root. If the user provides RISCV, make its gcc visible.
# Otherwise, if gcc is already visible, infer RISCV from it for Makefile users.
if [ -n "$RISCV" ]; then
	for _rvbin in "$RISCV/bin" "$RISCV"/*/bin; do
		if [ -x "$_rvbin/riscv64-unknown-elf-gcc" ]; then
			case ":$PATH:" in
				*":$_rvbin:"*) : ;;
				*) export PATH="$_rvbin:$PATH" ;;
			esac
			break
		fi
	done
	unset _rvbin
elif command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
	_rvgcc="$(command -v riscv64-unknown-elf-gcc)"
	export RISCV="$(cd "$(dirname "$_rvgcc")/.." && pwd)"
	unset _rvgcc
fi
if ! command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
	echo "Warning: riscv64-unknown-elf-gcc not found; set RISCV or add the toolchain bin directory to PATH if this flow builds RISC-V code." >&2
fi

function update_submodules {
	cd ip/xspi && git checkout feature/hb_debug && git pull && cd -
	cd ip/cpu_subsystem && git checkout main && git pull && cd -
	cd ip/i2c && git checkout master && git pull && cd -
	cd ip/mram_axi_bridge && git checkout erbium/dev && git submodule update && git pull && cd -
	cd ip/erbium_noc && git checkout main && git pull && cd -
	# Proprietary NIC-700 (tapeout only; absent in the open-source checkout)
	[ -d ip/ni700_ErbiumET ] && { cd ip/ni700_ErbiumET && git checkout main && git pull && cd -; }
}
