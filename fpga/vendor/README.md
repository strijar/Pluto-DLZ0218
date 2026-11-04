# Digilent RGB2DVI snapshot

`rgb2dvi_v1_2` is copied verbatim from the board-tested project:
`/home/master/fpga/Pluto-HDMI/hdmi_test/tmds_ip/rgb2dvi_v1_2`.
Its `src/` also matches the instantiated `rgb2dvi_0/src/` in that project.
IP VLNV: `digilentinc.com:ip:rgb2dvi:1.2`. The original upstream commit is
not recorded in that project; no commit identity is claimed. Exact source
SHA-256 hashes are in `rgb2dvi-source.sha256` (run `sha256sum -c` from the
repository root). BSD 3-clause notices are retained in the VHDL sources.

The serializer, encoder, resets and source XDC are unchanged. As in the
working board example, top-level XDC selects DIFF_HSTL_II_18 for the 1.8 V
bank. External coherent pixel/serial clocks are 40/200 MHz for 800x600.

`../ip/interfaces/tmds` supplies local IP-XACT definitions for the four
logical output ports referenced by the vendor package. These metadata files
are locally authored; they do not modify the Digilent RTL.
