# CMOS AD9363, two RX/TX channels. ADI packers run on the interface clock;
# valid strobes avoid the LVDS-specific clock divider used by FMCOMMS2.
set_property -dict [list \
 CONFIG.PCW_USE_M_AXI_GP0 1 CONFIG.PCW_USE_S_AXI_HP1 1 CONFIG.PCW_USE_S_AXI_HP2 1 \
 CONFIG.PCW_EN_CLK0_PORT 1 CONFIG.PCW_EN_CLK1_PORT 1 CONFIG.PCW_EN_RST0_PORT 1 \
 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100 CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ 200 \
 CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE 1 CONFIG.PCW_GPIO_EMIO_GPIO_IO 6 \
 CONFIG.PCW_SPI0_PERIPHERAL_ENABLE 1 CONFIG.PCW_SPI0_SPI0_IO EMIO \
 CONFIG.PCW_USE_FABRIC_INTERRUPT 1 CONFIG.PCW_IRQ_F2P_INTR 1 CONFIG.PCW_IRQ_F2P_MODE REVERSE] $ps7
ad_ip_instance proc_sys_reset sys_rstgen {C_EXT_RST_WIDTH 1}
ad_connect sys_cpu_clk sys_ps7/FCLK_CLK0
ad_connect sys_200m_clk sys_ps7/FCLK_CLK1
ad_connect sys_cpu_clk sys_rstgen/slowest_sync_clk
ad_connect sys_ps7/FCLK_RESET0_N sys_rstgen/ext_reset_in
ad_connect sys_cpu_resetn sys_rstgen/peripheral_aresetn
ad_connect sys_cpu_reset sys_rstgen/peripheral_reset
ad_ip_instance xlconcat sys_concat_intc {NUM_PORTS 16}
ad_connect sys_concat_intc/dout sys_ps7/IRQ_F2P
for {set i 0} {$i < 16} {incr i} {ad_connect sys_concat_intc/In$i GND}

ad_ip_instance axi_ad9361 axi_ad9361 {ID 0 CMOS_OR_LVDS_N 1 MODE_1R1T 0 ADC_INIT_DELAY 21 DAC_DDS_TYPE 1 DAC_DDS_CORDIC_DW 14}
foreach p {rx_clk_in rx_frame_in} {create_bd_port -dir I $p; ad_connect $p axi_ad9361/$p}
create_bd_port -dir I -from 11 -to 0 rx_data_in
ad_connect rx_data_in axi_ad9361/rx_data_in
foreach p {tx_clk_out tx_frame_out enable txnrx} {create_bd_port -dir O $p; ad_connect $p axi_ad9361/$p}
create_bd_port -dir O -from 11 -to 0 tx_data_out
ad_connect tx_data_out axi_ad9361/tx_data_out
# Unused negative clock/frame inputs of AD9363 must be low in CMOS mode.
foreach p {tx_clk_unused tx_frame_unused} {create_bd_port -dir O $p; ad_connect $p GND}
ad_connect axi_ad9361/tdd_sync GND
ad_connect sys_200m_clk axi_ad9361/delay_clk
ad_connect axi_ad9361/l_clk axi_ad9361/clk

foreach {p pin dir} {spi_csn SPI0_SS_O O spi_clk SPI0_SCLK_O O spi_mosi SPI0_MOSI_O O spi_miso SPI0_MISO_I I} {
 create_bd_port -dir $dir $p
 ad_connect $p sys_ps7/$pin
}
ad_connect sys_ps7/SPI0_SS_I VCC
ad_connect sys_ps7/SPI0_SCLK_I GND
ad_connect sys_ps7/SPI0_MOSI_I GND
ad_connect sys_ps7/GPIO_O sys_ps7/GPIO_I
set i 0
foreach p {radio_resetn en_agc up_enable up_txnrx sw_rx sw_tx} {
 ad_ip_instance xlslice gpio_$p [list DIN_WIDTH 6 DIN_FROM $i DIN_TO $i DOUT_WIDTH 1]
 ad_connect sys_ps7/GPIO_O gpio_$p/Din
 if {$p in {up_enable up_txnrx}} {
  ad_connect gpio_$p/Dout axi_ad9361/$p
 } else {
  create_bd_port -dir O $p
  ad_connect gpio_$p/Dout $p
 }
 incr i
}
create_bd_port -dir O -from 3 -to 0 ctrl_in
ad_connect ctrl_in GND

ad_ip_instance util_cpack2 rx_pack {NUM_OF_CHANNELS 4 SAMPLE_DATA_WIDTH 16}
ad_ip_instance util_upack2 tx_unpack {NUM_OF_CHANNELS 4 SAMPLE_DATA_WIDTH 16}
foreach p {rx_pack tx_unpack} {
 ad_connect axi_ad9361/l_clk $p/clk
 ad_connect axi_ad9361/rst $p/reset
}
set i 0
foreach ch {i0 q0 i1 q1} {
 ad_connect axi_ad9361/adc_enable_$ch rx_pack/enable_$i
 ad_connect axi_ad9361/adc_data_$ch rx_pack/fifo_wr_data_$i
 ad_connect axi_ad9361/dac_enable_$ch tx_unpack/enable_$i
 ad_connect axi_ad9361/dac_data_$ch tx_unpack/fifo_rd_data_$i
 incr i
}
ad_connect axi_ad9361/adc_valid_i0 rx_pack/fifo_wr_en
ad_connect axi_ad9361/dac_valid_i0 tx_unpack/fifo_rd_en
ad_connect rx_pack/fifo_wr_overflow axi_ad9361/adc_dovf
ad_connect tx_unpack/fifo_rd_underflow axi_ad9361/dac_dunf
ad_ip_instance axi_dmac axi_ad9361_adc_dma {DMA_TYPE_SRC 2 DMA_TYPE_DEST 0 CYCLIC 0 SYNC_TRANSFER_START 0 DMA_2D_TRANSFER 0 DMA_DATA_WIDTH_SRC 64}
ad_ip_instance axi_dmac axi_ad9361_dac_dma {DMA_TYPE_SRC 0 DMA_TYPE_DEST 1 CYCLIC 1 DMA_2D_TRANSFER 0 DMA_DATA_WIDTH_DEST 64}
ad_connect axi_ad9361/l_clk axi_ad9361_adc_dma/fifo_wr_clk
ad_connect axi_ad9361/l_clk axi_ad9361_dac_dma/m_axis_aclk
ad_connect rx_pack/packed_fifo_wr axi_ad9361_adc_dma/fifo_wr
ad_connect tx_unpack/s_axis axi_ad9361_dac_dma/m_axis
ad_connect sys_cpu_resetn axi_ad9361_adc_dma/m_dest_axi_aresetn
ad_connect sys_cpu_resetn axi_ad9361_dac_dma/m_src_axi_aresetn
ad_cpu_interconnect 0x79020000 axi_ad9361
ad_cpu_interconnect 0x7c400000 axi_ad9361_adc_dma
ad_cpu_interconnect 0x7c420000 axi_ad9361_dac_dma
ad_mem_hp1_interconnect sys_cpu_clk sys_ps7/S_AXI_HP1
ad_mem_hp1_interconnect sys_cpu_clk axi_ad9361_adc_dma/m_dest_axi
ad_mem_hp2_interconnect sys_cpu_clk sys_ps7/S_AXI_HP2
ad_mem_hp2_interconnect sys_cpu_clk axi_ad9361_dac_dma/m_src_axi
ad_cpu_interrupt ps-13 mb-13 axi_ad9361_adc_dma/irq
ad_cpu_interrupt ps-12 mb-12 axi_ad9361_dac_dma/irq
