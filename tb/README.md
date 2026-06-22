# Run Tests in Erbium

This document explains how to install dependencies, run the test suite, and understand the testing structure of this project.

- [Run Tests in Erbium](#run-tests-in-erbium)
- [Installation](#installation)
- [Setting up the environment](#setting-up-the-environment)
- [Running C / Assembly code in the Minions](#running-c--assembly-code-in-the-minions)
  - [Valid Makefile.elf knobs](#valid-makefileelf-knobs)
    - [ELF\_RUN\_ROOT](#elf_run_root)
    - [RISCV](#riscv)
    - [SIM](#sim)
    - [BOOT\_PC](#boot_pc)
    - [TIMEOUT](#timeout)
    - [VERBOSE](#verbose)
    - [RTL\_COSIM](#rtl_cosim)
    - [STDOUT](#stdout)
    - [MINION\_MASK](#minion_mask)
    - [THREAD\_MASK](#thread_mask)
    - [TEST\_MODE](#test_mode)
  - [How to run an existing ELF](#how-to-run-an-existing-elf)
  - [How to run a C / Assembly test](#how-to-run-a-c--assembly-test)
  - [How to run an MTG test](#how-to-run-an-mtg-test)
    - [Valid MTG knobs](#valid-mtg-knobs)
      - [SEED](#seed)
      - [MTG\_ROOT](#mtg_root)
      - [MTG\_TEST](#mtg_test)

# Setting up the environment
All commands assume `cwd=<repo_root>`

If not already done, initialize all submodules first
```bash
git submodule update --init --recursive
```

Create python virtual environment (`pip install uv` first if needed)
```bash
uv sync
```

Set up RALs
```bash
mkdir tb/ralgen
uv run make -C regblocks/systemrdl ral
```

Finally, activate the environment
```bash
source .venv/bin/activate && source .autoenv.zsh
```

# Running C / Assembly code in the Minions

The `Makefile.elf` supports several environment variables that control how tests are run.
This section documents all valid knobs, their defaults, and how they affect execution.

## Valid Makefile.elf knobs

### ELF\_RUN\_ROOT
Root directory where the run environment is created. If not provided, it defaults to `elf_run_<timestamp>`, where `<timestamp>` is the current Unix time.

When running a test, within `ELF_RUN_ROOT`, two extra directories will be created:
- `build`: Directory where the simulator build artifacts are placed.
- `test`: Each test gets its own subfolder inside `test`. The subfolders are the workspace for the run, containing the log file, waveform dumps, and any other artifacts produced during simulation.

The folder hierarchy will look like this:

```
<ELF_RUN_ROOT>
├── build
│   ├── simv
│   └── ...
│
└── test
    ├── <test_name>
    │   └── ...
    └── <test_name>
        ├── run.log
        ├── test.conf
        ├── vcdplus.vpd
        ├── test_elf_results.xml
        └── ...
```

If you want to build the RTL once and run the same test multiple times or different tests using the same build, you can achieve that by passing the same `ELF_RUN_ROOT` when doing `make`.

### RISCV
Path to the RISC‑V toolchain. Source `.autoenv.zsh` after setting `RISCV`, or
put `riscv64-unknown-elf-gcc` on `PATH` before sourcing `.autoenv.zsh`.

### SIM
Simulator backend. Currently only supports `vcs` or `verilator`. If not provided, it defaults to `vcs`.

### BOOT\_PC
Minion boot PC address. Must be a hexadecimal number without the 0x prefix. When not provided, it defaults to 40000000.

### TIMEOUT
Execution timeout in nanoseconds. When not provided, it defaults to 10000000 ns.

### VERBOSE
Controls cosimulation verbosity. When set to 0, cosimulation will not print the instructions executed by the Minions. The default is 1, meaning verbosity is enabled.

### RTL\_COSIM
Controls whether cosimulation is enabled. When set to 0, cosimulation checks are disabled. The default is 1, meaning cosimulation checking is enabled.

### STDOUT
Controls whether logs are printed to stdout. When set to 1, logs are shown in stdout as well as written to the log file. The default is 0, meaning logs are only written to the file.

### MINION\_MASK
Controls which Minion cores participate in the simulation. This is a bitmask where each bit corresponds to a Minion. The default is 0xFF, meaning all Minions are enabled.

### THREAD\_MASK
Controls which hardware threads are enabled during simulation. This is a bitmask where each bit corresponds to a thread. The default is 0x3, meaning threads 0 and 1 are enabled.

### TEST\_MODE
Controls the TestMode pin at the top. Default is 1, meaning TestMode is enabled.

## How to run an existing ELF
If you have an existing ELF and you just want to run it on the Minions you can achieve that by doing:
```
make -f Makefile.elf TEST_ELF=<path_to_elf>
```

## How to run a C / Assembly test
Each test resides in its own subdirectory under `c_asm_tests`. Every test directory contains its own source files and a Makefile that defines how that particular test is built. The subdirectory name must match the name of the binary produced during compilation, and this same name is the one you must pass when invoking `make`:

```
make -f Makefile.elf <test_name>
```

If you just want to compile the test without running, you can achieve that by doing:
```
make -f Makefile.elf TEST_ELF=<test_name> compile_diag
```

## How to run an MTG test
MTG is a random test generator that specifically targets the Minions custom ISA. MTG flow supports some knobs (see below) but the basic command to run MTG on the Minions is:
```
make -f Makefile.elf mtg_16t_rand
```

If you just want to generate an MTG test without running in the Minions, you can achieve that by doing:
```
make -f Makefile.elf MTG_TEST=rand compile_mtg_16t
```

### Valid MTG knobs

#### SEED
Random seed for MTG. If not provided it assigns a random one.

#### MTG\_ROOT
Path to the MTG tool directory. If not provided it defaults to `$HDLET_ROOT/ip/cpu_subsystem/extern/mtg`.

#### MTG\_TEST
MTG provides different test recipes. You can find them under `$MTG_ROOT/conf/regress`. If not provided it defaults to `rand`.
