# MRAM

The MRAM subsystem provides the non-volatile memory target behind the SoC
interconnect. At the IP level, the AXI-to-MRAM bridge accepts a 512-bit AXI4
slave interface and converts each transaction into commands for four ET MRAM
banks. Each bank has its own controller path for startup, ECC, BIST, interrupt
capture, and the physical or behavioral bank instance.

The bridge is a local-memory target. System address maps may place the MRAM at
different external base addresses for CPU, xSPI, or chiplet views, but the
bridge itself sees a zero-based local MRAM address.

## Address Space

The normal MRAM data window is 16 MB at local address `0x0000_0000` through
`0x00ff_ffff`.

The bridge also recognizes a 12 KB OTP aperture at local address
`0x3fff_d000` through `0x3fff_ffff`. That aperture is translated into reserved
MRAM rows and columns inside the bank address space. Software sees the OTP
window as a contiguous byte range; the bridge performs the sparse physical
mapping internally.

Any AXI transaction outside the supported local windows is rejected:

| Access | Behavior |
| --- | --- |
| Read | Returns `SLVERR` on each beat, `RDATA = 0`, and normal `RLAST` cadence |
| Write | Drains all write-data beats, issues no MRAM command, and returns `SLVERR` |

The bridge also returns `SLVERR` if the MRAM side is not ready, is not powered,
or is in maintenance mode. These status conditions are aggregated across the
four banks before the AXI transaction is accepted.

## Top-Level Data Path

The current ET integration uses:

| Item | Value |
| --- | --- |
| AXI data width | 512 bits |
| AXI address width | 32 bits |
| AXI ID width | 9 bits |
| AXI burst length field | 8 bits, so up to 256 beats |
| Bridge bank lanes | 4 |
| Per-bank read return | 128 bits |
| Per-bank write payload | 64 bits |
| Physical bank address | 17 bits |

The high-level path is:

```text
AXI4 slave
  -> mkAxi2Mram
  -> four MramBankTranslator lanes
  -> four ET bank wrappers
  -> ET controller, ECC, BIST, startup, interrupt, and bank logic
```

Each 512-bit AXI beat is split into four 128-bit bank lanes. Inside each bank
lane, writes are handled as 64-bit chunks, while reads return a 128-bit pair.
The bridge therefore has to track both AXI beat-level ordering and the lower
level bank instance and pair selection.

## AXI Front End

The bridge accepts AXI read and write address channels independently, then uses
an internal arbiter whenever both sides are ready at the same time. The
arbitration mode is software configurable:

| Mode | Policy |
| --- | --- |
| Write priority | Writes win every read/write conflict |
| Read priority | Reads win every read/write conflict |
| Round robin | Alternates after simultaneous conflicts |
| Oldest first | Chooses the channel that became pending first |

Round-robin is the reset-default policy.

The bridge serializes active read and write work at the AXI sequencing level.
This keeps the bank translators from seeing ambiguous ownership of a bank read
or write sequence while still allowing the AXI channels to queue work through
the AXI transactor.

## Read Flow

For a read, the bridge builds two plans:

| Plan | Purpose |
| --- | --- |
| MRAM issue plan | Which bank lanes must be read and at which translated bank address |
| AXI beat plan | Which bytes belong in each AXI `RDATA` beat and when bank responses can retire |

This split is important for unaligned accesses and bursts whose bytes cross
64-byte AXI line boundaries. The bridge only issues a bank read when a new bank
lane or physical group is needed, but it still emits AXI read beats in the
requested order.

When all selected bank responses for an AXI beat are available, the bridge
assembles the 512-bit `RDATA` value from the four 128-bit bank responses. Bytes
outside the requested transfer size are masked to zero. The response code is
normally `OKAY`, or `EXOKAY` for a successful exclusive read, unless the access
was rejected.

## Write Flow

For a write, the bridge drains the AXI `W` channel, masks `WDATA` by `WSTRB`,
and accumulates data until either the current 64-byte line is complete or
`WLAST` is observed. It then splits the accumulated value into per-bank
commands.

Each bank lane contains two 64-bit write chunks per 128-bit lane:

| Strobe shape | Bank command |
| --- | --- |
| Full 8-byte chunk | Direct write |
| Partial 8-byte chunk | Read-modify-write |

Partial writes are handled by reading the old 64-bit word from the bank,
merging only the strobed bytes, and then writing the merged word back. This
keeps the stored ECC word coherent after byte-granular writes.

`BRESP` is returned after the bridge has drained the AXI write data and accepted
or suppressed the corresponding bank commands. A rejected write drains normally
but does not enqueue any bank command.

## Exclusive Accesses

The bridge includes an AXI exclusive-access monitor. Exclusive reads create a
reservation and return `EXOKAY`. Exclusive writes return `EXOKAY` only when a
matching reservation is present; otherwise they return `OKAY` and suppress the
MRAM write.

Normal writes snoop the monitor and invalidate overlapping reservations.

The monitor tracks up to 32 AXI IDs at a time, with up to four reservations per
ID. Both levels use round-robin replacement when full.

## Bank Translator

Each of the four bank lanes has a `MramBankTranslator`. This block converts
bridge commands into MRAM-facing control signals:

| Signal group | Purpose |
| --- | --- |
| `ce_o[7:0]` | Selects one write instance or one adjacent read pair |
| `dout_en_o[7:0]` | Captures a read result from the selected pair |
| `we_o` | Selects write versus read behavior |
| `addr_o[16:0]` | Physical bank word address |
| `din_o[63:0]` | 64-bit write payload |
| `bwe_o[63:0]` | Bit write-enable mask for the 64-bit payload |

Reads are pair-based: a read selects two adjacent instances and returns a
128-bit value. Writes are instance-based: a write selects one of the eight
instances and writes a 64-bit value.

The translator also owns the bank timing hazards:

| Hazard | Handling |
| --- | --- |
| Read/read pair conflict | Fixed read-pair busy pipeline |
| Read/write pair conflict | Writes wait through the read launch and `dout_en` window |
| Write/write instance conflict | Writes wait for local early-busy and sampled MRAM busy to clear |
| RMW atomicity | The selected pair stays reserved until the write-back phase completes |

Write busy is tracked conservatively. The translator asserts local busy as soon
as it launches a write, holds it while the command reaches the MRAM, and then
tracks the MRAM busy signal sampled on the bank clock edge. This avoids issuing
a conflicting command in the gap before the memory macro reports busy.

## ET Controller Path

Behind each bank translator is an ET bank wrapper. At a public architectural
level, that wrapper contains:

| Block | Role |
| --- | --- |
| Boot sequencer | Waits for power-good, releases MRAM reset, performs startup sequencing, and reports bank ready |
| Control mux | Chooses between normal AXI traffic and internal maintenance/BIST traffic |
| ECC wrapper | Encodes writes and corrects reads |
| BIST wrapper | Drives built-in memory test and reference-trim flows |
| Interrupt logic | Captures ECC error class and address for CPU interrupt reporting |
| Global configuration logic | Drives bank configuration and sleep behavior |
| Bank instance | Physical macro wrapper or behavioral model |

The bridge observes each bank's ready, power-good, maintenance, busy, data, and
ECC error signals through this controller path.

## ECC

Normal data writes start as 64-bit payload words. The controller ECC path
encodes each payload into the wider stored MRAM word. On reads, the lower and
upper stored words from the bank are corrected and returned to the bridge as a
128-bit payload.

The ET path reports single-bit, double-bit, and triple-bit ECC events per read
lane. The wrapper counts these events and can raise the MRAM interrupt. The
interrupt path captures the first unmasked ECC event until software clears it
through the system-level interrupt flow.

The controller also has a separate reference-word ECC path used by reference
programming and trim behavior. That path is distinct from the normal payload
BCH path.

## Address Translation And Layout

The AXI side addresses memory as bytes. Internally, the bridge converts those
byte addresses into bank, instance, and word locations.

At the bridge level, each 64-byte AXI data beat maps naturally onto the four
bank lanes:

| AXI byte range within a beat | Bank lane |
| --- | --- |
| Bytes 0-15 | Bank 0 |
| Bytes 16-31 | Bank 1 |
| Bytes 32-47 | Bank 2 |
| Bytes 48-63 | Bank 3 |

Within each bank lane, the lower 8 bytes select one 64-bit instance write and
the upper 8 bytes select the adjacent instance write. Reads select the pair and
return both 64-bit halves as one 128-bit bank response.

The OTP aperture is not a separate physical memory. It is a software-visible
window that the bridge translates into reserved MRAM locations. Only the OTP
window receives this special translation; normal MRAM data addresses are passed
through the regular bank-address mapping.

## Functional Guarantees

The MRAM block behaves as a strongly ordered memory target at the bridge
interface. It does not expose out-of-order read data or write responses to the
requester. When read and write work arrive together, the selected arbitration
policy chooses which channel enters the memory pipeline first.

Important software-visible guarantees are:

| Topic | Guarantee |
| --- | --- |
| Rejected reads | Complete with `SLVERR`, zero data, and normal burst length |
| Rejected writes | Drain all write-data beats and return `SLVERR` without changing MRAM contents |
| Byte writes | Honor `WSTRB`; unstrobbed bytes are preserved through RMW when needed |
| Exclusive writes | Modify MRAM only on a matching reservation |
| Normal writes | Invalidate overlapping exclusive reservations |
| MRAM not ready | Transactions are rejected rather than queued indefinitely |
| Clock gating | Does not change software-visible memory ordering |

The bridge and bank translators also prevent same-bank timing hazards from
leaking up to the AXI interface. Reads and writes may stall internally while a
bank pair or instance is busy, but accepted transactions still complete through
the normal AXI response channels.

## BIST And Maintenance Traffic

The controller includes built-in memory test support for write, read, and
reference-trim flows. BIST traffic is muxed onto the same bank command pins as
normal AXI traffic, so the controller arbitrates the source before commands
reach the bank macro.

BIST and maintenance flows can exercise ranges, loop over addresses, compare
read data against expected patterns, stop on error, count replacement or
compare failures, and run reference-trim search behavior. These flows are used
for bring-up, manufacturing, and health checks rather than normal software data
movement.

## Clocking, Reset, And Power

The AXI bridge has one main clock and generates one gated MRAM-facing clock per
bank lane. During startup, the bridge bypasses clock gating for an initial
window. After that, each bank clock is enabled when any of the following is
true:

| Condition |
| --- |
| Clock gating is disabled for that bank |
| AXI work is pending |
| The bank reports busy |
| The translator has tracked local busy |
| The per-bank command queue is active |

The controller path has its own startup sequencing. It synchronizes power-good,
holds MRAM reset until the bank is powered, optionally bypasses startup, and
reports ready only after the startup sequence has completed.

Deep sleep and maintenance status are treated as transaction-blocking
conditions by the bridge.

## Register Visibility

The public bridge register block exposes control and status for:

| Register class | Contents |
| --- | --- |
| Arbitration | Read/write conflict policy |
| Bridge status | AXI busy, command queue activity, per-bank ready |
| Error status | Sticky clear-on-read SLVERR causes |
| Control | Per-bank clock-gate disable and ECC interrupt masks |
| ECC counters | Saturating counts of observed ECC lane events |

The register block is generated from SystemRDL as part of the integration
collateral.
