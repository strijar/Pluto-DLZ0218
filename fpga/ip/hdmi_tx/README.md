# HDMI transmitter: fixed video + PCM audio

`rgb2hdmi` accepts aligned RGB888, DE/HS/VS and raster coordinates from
`axi_video_to_rgb`. It sends 800x600 at a 40 MHz pixel/character clock and
uses the existing coherent 200 MHz serializer clock. The default source is the PCM AXIS input from `axi_hdmi_audio` (ALSA/PL330).
The optional `TEST_TONE=true` source generates a continuous 1 kHz stereo sine
at 48 kHz / 16 bits, peak 8191 (-12.04 dBFS), entirely in PL.

## Raster and latency contract

Coordinates are zero-based, active at x=0..799, y=0..599, total 1056x628.
The adapter registers coordinates together with RGB and synchronization.
`hdmi_protocol` feeds the original three-stage Digilent TMDS encoder for
active pixels and delays auxiliary symbols by the same three registers.
The serializer and output buffers are the unchanged Digilent implementation.
A first partial active line immediately after reset is suppressed, so every
transmitted video line has a complete preamble and guard band.

| Interval in each line | Characters |
|---|---|
| Data preamble | x=808..815 (8) |
| Leading data guard | x=816..817 (2) |
| Four packets | x=818..945 (4 x 32) |
| Trailing data guard | x=946..947 (2) |
| Control after island | x=948..1045 (98) |
| Video preamble if next line is active | x=1046..1053 (8) |
| Video guard if next line is active | x=1054..1055 (2) |

There are at least 12 control characters before each data/video period and
an extended control interval of at least 32 characters on every line. No
island crosses a line boundary. During vertical blanking the same four-packet
slots remain available; no video preamble is emitted before inactive lines.
HS/VS continue in channel 0, including within data islands.

## Packets and audio

Each packet is selected one clock before transmission and remains stable
for all 32 characters. Priority: pending Audio InfoFrame, queued PCM, ACR,
pending AVI InfoFrame, otherwise Null. The initial Audio InfoFrame precedes
the first PCM sample. Both InfoFrames repeat every frame.

- Audio Sample Packet: layout 0, one stereo pair in subpacket 0; other
  subpackets are zero and marked absent. Internal PCM is L[15:0], R[31:16],
  signed two's complement, left-aligned to 24 HDMI sample bits.
- IEC 60958 consumer status: LPCM, copyright not asserted, general category,
  source 0, channels 1/2, 48 kHz, original 48 kHz, 16-bit word. B flags and
  channel status wrap after 192 samples. Validity/user bits are zero and
  even parity includes sample, V/U/C.
- ACR: N=6144, CTS=40000. A new CTS is queued every 40000 pixel clocks
  (1 ms), then transmitted at the next available slot after audio. These
  constants are valid only for this 40 MHz / 48 kHz clock relationship.
- Audio InfoFrame: two channels, FL/FR, coding/rate/size refer to stream.
- AVI: RGB, 4:3 picture, underscan, IT content, full range, no repetition,
  VIC=0 for the VESA mode. No CTA video code is invented for 800x600.
- Each header/subpacket has BCH ECC; InfoFrames additionally have a checksum.

The fractional audio accumulator adds 3 modulo 2500, yielding exactly
48 kHz on average. A 16-entry synchronous FIFO separates tone sample timing
from packet slots. Empty FIFO produces Null packets, not bogus audio samples.
The test source flags a simulation error if stalled for an entire sample
period; the scheduler's four slots per line provide ample capacity for this
fixed mode. The protocol's PCM valid/ready interface is connected to `axi_hdmi_audio`,
which paces the ARM-produced stream and supplies silence when idle.

## Build and verification

`make -C fpga hdmi-ip` packages the IP into `fpga/build/ip/hdmi_tx`, including
`component.xml`, RGB/clock/reset interfaces and imported serializer sources.
The normal FPGA build invokes this target automatically. `video_bd.tcl`
contains the integration with VDMA and the existing SDR subsystem.

`make -C fpga test` runs GHDL and then `fpga/sim/check_hdmi.py`. The trace
covers three frames plus a partial frame, reset, and three further frames.
The Python receiver uses only the emitted 10-bit symbols, raster positions
and the independently logged PCM input; it does not import RTL packet helpers.
It checks every video pixel and blanking character, TMDS running disparity,
TERC4 mapping, preambles/guards, polynomial BCH syndrome, InfoFrame checksums,
ACR timing, PCM sequence, IEC status/parity/B flags and 48 kHz sample timing.
Generated traces are under `fpga/build/ghdl-hdmi` and are not source files.
OSERDES electrical behavior is inherited from the board-tested video stage;
this simulation checks its parallel symbol input, not a transistor-level link.

## Sources and provenance

Packet definitions and timing were checked against the HDMI specification,
sections 5.2-5.3, 7.8 and 8.2:
[HDMI 1.3 specification, MIT course mirror](https://fpga.mit.edu/6205/_static/F24/default_files/CEC_HDMI_Specification.pdf).
The implemented packet types and encodings are also used by HDMI 1.4.
Cross-check reference:
[hdl-util/hdmi, commit 83b1c9543a91b776671a44e68e130f81cae437b7](https://github.com/hdl-util/hdmi/tree/83b1c9543a91b776671a44e68e130f81cae437b7/src).
That SystemVerilog project is not a build dependency. IEC status constants
were additionally checked against `include/sound/asoundef.h` in the pinned
ADI Linux tree.

Digilent sources and BSD notices are retained in `fpga/vendor`. The local
`TMDS_Encoder.vhd` copy changes only its function return-type declaration to
a named subtype, making the otherwise unchanged logic accepted by GHDL.
The complete protocol/scheduler/tone implementation is VHDL.

## Hardware acceptance

The user confirmed boot console, test bars and the autonomous PL tone on
this board. ALSA playback is a new stage and still needs board verification;
see [system instructions](../../../system/README.md#hdmi-alsa). No EDID/DDC/HPD
automation or HDCP is implemented.

## Validation result, 2026-11-04

GHDL + independent decoder passed: 3,991,347 traced character positions,
4,788 recovered stereo sample pairs, 99 ACR packets, seven AVI and seven Audio
InfoFrames across two reset epochs. All emitted packet BCH blocks/checksums
and all active RGB symbols were checked. Input audio pacing and exact sine
samples were checked independently. Up to two samples pending at end/reset
are allowed by the delivery-latency check; no emitted samples may be reordered.

Vivado 2019.2: IP integrity check, BD validation, synthesis, implementation
and bitstream generation passed. Routed WNS +1.196 ns, WHS +0.028 ns;
zero unconstrained internal endpoints. Whole SDR+HDMI design: 13,490 LUT,
20,756 FF, 8.5 BRAM tiles, 28 DSP (increment over video-only: 281 LUT, 238 FF).
DRC has no errors, two existing VDMA reset warnings and 26 advisory entries.
The previously documented external timing limitations remain (13 inputs,
20 outputs without external delays); these numbers do not certify the cable
or receiver. The autonomous tone was subsequently confirmed on the board.

These resource/timing results describe the autonomous-tone stage. Current
artifacts include the ALSA bridge and require matching kernel, DTB and rootfs.
Use the rebuilt `system/output_system/images/sdcard.img`. The previous tone
bitstream is preserved locally as `fpga/build/export/system-hdmi-tone.bit`.
