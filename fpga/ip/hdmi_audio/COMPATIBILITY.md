# HDMI PCM bridge and ADI Linux compatibility

The bridge implements the TX subset used by the unmodified ADI `axi-i2s`
driver. It is not a general replacement for the ADI I2S core: there are no
I2S pins, capture path or selectable sample rates. HDMI payload is signed
PCM16, two channels, 48 kHz. No additional audio DMA IP is needed.

## Audited sources

- ADI Linux commit `86d61468a7856e952c7ca237f798d86d6abd2e27`:
  `sound/soc/adi/axi-i2s.c`, `sound/soc/generic/simple-card-utils.c`,
  `sound/soc/codecs/spdif_transmitter.c`, `drivers/dma/pl330.c`,
  `arch/arm/boot/dts/zynq-7000.dtsi`, `zynq-zed-adv7511.dtsi`.
- ADI HDL commit `ae6e248f219a5bb2e63733c762e9561c072d037e`:
  `library/axi_i2s_adi/axi_i2s_adi.vhd`,
  `library/common/pl330_dma_fifo.vhd`, `library/common/dma_fifo.vhd`.
- AMD UG585, [Peripheral Request Interface](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/Peripheral-Request-Interface)
  and [PL Peripheral Length Managed by DMAC](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/PL-Peripheral-Length-Managed-by-DMAC).

The custom bridge is VHDL. Existing Linux drivers are built without audio
patches. The unrelated framebuffer patch remains in use.

## Register subset

Base address `0x43c00000`, 64 KiB aperture, AXI4-Lite at 100 MHz through GP0.
AW and W are accepted independently; B/R responses remain stable under
backpressure. Unsupported addresses return SLVERR.

| Offset | Function |
|---|---|
| 0x00 | RESET: bit 0 global reset, bit 1 TX FIFO reset; write pulse |
| 0x04 | CTRL: bit 0 TX enable; disabling flushes pending samples |
| 0x08 | CLK_CTRL: driver must write 0x001f0000 for this fixed mode |
| 0x10 | Local status: bit 0 sticky underrun, 1 full, 2 pending left word, 3 flushing, 4 invalid clock configuration |
| 0x2c | TX FIFO: full 32-bit writes, left word then right word; retain bits 31:16 |

The driver uses 32-bit DMA transfers and maxburst=1. Its CPU DAI advertises
S32_LE/U32_LE; the dummy codec restricts the joint formats to S32_LE.
`asound.conf` uses ALSA plug to convert application PCM16 into these words.
Conversion leaves the significant signed 16-bit sample in bits 31:16;
HDMI transmits that sample left-aligned in its 24-bit packet field.

The fixed reference clock in DT is a **logical driver ABI clock**, 6.144 MHz.
No physical MCLK is generated. With `mclk-fs=128`, fixed system clock and the
ADI divider formula, the only hardware rate is 48 kHz and CLK_CTRL is
0x001f0000. Actual sampling uses a 3/2500 fractional tick from 40 MHz.
A different divider is rejected and silences the bridge. The standard
`linux,spdif-dit` dummy codec supplies ASoC capabilities; it does not create
a physical S/PDIF output.

## PL330 and clocks

DT `dmas = <&dmac_s 0>` selects PS DMA0_REQ/ACK. The argument is a peripheral
request index, not a Linux IRQ or a DMA thread number. DMA0_ACLK, GP0 and the
bridge AXI clock use FCLK0=100 MHz. PL330 writes through M_AXI_GP0.
Requests use DRTYPE=00 (SINGLE), DRLAST=0. DATYPE=00 acknowledges a single
transfer. DATYPE=10 initiates FLUSH, answered with DRTYPE=10 even while TX
is disabled. Request valid/type remain stable until accepted. Writes already
in flight after stopping are acknowledged and discarded.

A dual-clock BRAM FIFO holds 256 complete stereo pairs (5.33 ms at 48 kHz).
Each pointer crosses as Gray code through two ASYNC_REG stages; the scoped
XDC bounds Gray bus flight time and skew to the source period. Level
synchronizers handle enable, reset request/acknowledgment and underrun.
Reset assertion is asynchronous, release is synchronized separately in each
domain. FIFO reset uses a held request/acknowledgment so both pointers reset
before accepting a new stream. The pixel domain supplies zeros continuously
when disabled, flushing or empty. HDMI packet generation continues normally.

## Validation and limits

`make -C fpga test-audio` checks AXI AW/W skew, B/R backpressure, PL330
SINGLE/FLUSH, FIFO full/wrap, channel order and signed upper-half conversion,
PCM backpressure, silence, underrun, stop/reset and restart. The HDMI packet
encoder is unchanged from the separately decoded and board-tested tone stage.
Linux and DTB compile with the existing driver; board ALSA playback remains
to be tested. Simulation does not execute the real PS PL330 or Linux driver.

FIFO underrun inserts silence and sets local status; it does not interrupt
Linux or directly report an ALSA XRUN. The ADI driver does not read the local
status extension and does not account for this FIFO's additional latency.
Stop may leave a few already packetized samples before silence. No capture,
variable rate, multichannel or higher-resolution HDMI payload is supported.
ALSA plug may resample application streams to the fixed hardware mode.

## Build result, 2026-11-04

Final Vivado 2019.2 route: WNS +1.110 ns, WHS +0.016 ns, no failing timing
endpoints. Whole SDR/video/audio design uses 13,656 LUT, 20,933 FF, 9 BRAM
tiles and 28 DSP. DRC: no errors, two existing VDMA asynchronous-reset
warnings and 26 advisory entries; no audio BRAM reset warnings remain.
Local reset enables are synchronously registered before reaching BRAM.

The routed CDC report recognizes all four control crossings as synchronized.
It reports the two 9-bit Gray pointer crossings as CDC-6; their datapath
max-delay and bus-skew constraints are applied and met. Two CDC-10 entries
remain specifically on the asynchronous CLR inputs of the reset synchronizers:
the AND of the two active-low reset sources intentionally asserts reset in
both domains. Release passes through three local stages and a synchronous
local enable stage. These reset-path entries are reviewed, not suppressed;
they do not describe PCM/control data crossings. Reports are exported locally
as `audio_cdc.rpt`, `audio_bus_skew.rpt` and `timing_exceptions.rpt`.

The full Buildroot SD image includes the matching bitstream, kernel, DTB,
ALSA utilities and `/etc/asound.conf`. Rootfs filesystem checks pass.
Real ALSA playback and concurrent sustained SDR traffic still require the board.
