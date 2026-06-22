# hdl-et

README written: March 4, 2026

HDL repository for Erbium-ET SoC integration, IP composition, and verification.

## What is in this repo

- `erbium_digital/`: top-level digital RTL integration and legacy/full-chip testbench collateral
- `tb/`: cocotb-based top-level Erbium-ET testbench (`tb.v`) and smoke/feature tests
- `regblocks/`: SystemRDL and generated register collateral
- `ip/`: major IP dependencies (`xspi`, `mram_axi_bridge`, `cpu_subsystem`, `i2c`, `erbium_noc`, etc.)
  - `erbium_noc` is an open-source NoC stub, used by default for CI and simulation.
    It is a drop-in for the proprietary `ni700_ErbiumET` NIC-700: the wrapper module
    name and ports are identical, so the NIC-700 can be swapped in via `NOC_FLIST`
    (see below) with no RTL changes.
- `doc/`: generated memory-map documentation and design notes

## Environment setup

This repo uses `uv` + `.venv` for Python tooling and cocotb packages.

From repo root:

```bash
cd <hdl-et-repo-root>
uv sync
source .venv/bin/activate
```

### About `autozsh` / `.autoenv.zsh`

This repo includes `.autoenv.zsh` (not `autozsh`).
If you use an autoenv plugin in zsh, it can source this automatically on directory entry.
If you do not use autoenv, source it manually:

```bash
source .autoenv.zsh
```

That file exports critical variables used by test compilation:

- `HDLET_ROOT`
- `RTLROOT`
- `NOC_FLIST` — selects the NoC filelist. Defaults to the open-source `erbium_noc`
  stub (`$HDLET_ROOT/ip/erbium_noc/flow/erbium_noc.f`). Pre-export it before
  sourcing to swap in a different NoC filelist (e.g. the proprietary NIC-700).
- `BOOKER_NCI` — proprietary NIC-700 generator output path (only used when the
  NIC-700 is swapped in)
- `BSC_VLIB_TOP` / `BSC_VLIB_ET` — Bluespec Verilog primitive library paths.
  Derived from `BLUESPEC_HOME` or `bsc` on `PATH`; pre-export these when a flow
  needs specific generated primitive versions.
- `RISCV` — RISC-V toolchain root. Pre-export it before sourcing
  `.autoenv.zsh`, or put `riscv64-unknown-elf-gcc` on `PATH`.
  When `RISCV` is set, `.autoenv.zsh` checks `$RISCV/bin` and `$RISCV/*/bin`.

Manual fallback if you do not want to source `.autoenv.zsh`:

```bash
export HDLET_ROOT="$(git rev-parse --show-toplevel)"
export RTLROOT="$HDLET_ROOT/ip/cpu_subsystem/rtl"
export NOC_FLIST="$HDLET_ROOT/ip/erbium_noc/flow/erbium_noc.f"
export RISCV="<riscv-toolchain-root>"
export BLUESPEC_HOME="<bluespec-root>"
for rvbin in "$RISCV/bin" "$RISCV"/*/bin; do
  [ -x "$rvbin/riscv64-unknown-elf-gcc" ] && export PATH="$rvbin:$PATH" && break
done
export PATH="$BLUESPEC_HOME/bin:$PATH"
export BSC_VLIB_TOP="<bluespec-root>/lib/Verilog"
export BSC_VLIB_ET="$BSC_VLIB_TOP"
```

## Getting submodules

IPs are checked in as git submodules. Initialize/update them before running tests:

```bash
git submodule update --init --recursive
```

## Running tb tests

Main cocotb top-level testbench lives under `tb/`.

### Run default test

```bash
cd <hdl-et-repo-root>
source .venv/bin/activate
source .autoenv.zsh
make -C tb sim MODULE=test_default
```

or simply:

```bash
make -C tb
```

(`tb/Makefile` defaults `MODULE:=test_default`)

### Run specific tb tests

```bash
make -C tb sim MODULE=test_gpio
make -C tb sim MODULE=test_xspi
```

### Run regression target in `tb/Makefile`

```bash
make -C tb regression
```

Current note: `tb/Makefile` lists `test_regions`, but no `tb/test_regions.py` exists in this checkout, so that target is stale as-is.

## Simulator notes

- `tb/Makefile` defaults to `SIM=vcs`
- Alternative verilator flow is available via `tb/Makefile.verilator`
- VCS command line is built from:
  - `erbium_digital/verilog/rtl.f`
  - `tb/tb.v`

## Register collateral and docs

To regenerate register models and markdown:

```bash
make -C regblocks/systemrdl
```

This updates outputs such as:

- `tb/ral/*`
- `doc/cpu_mm.md`
- `doc/xspi_mm.md`
- `regblocks/verilog/System_Reg.sv`
