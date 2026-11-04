# Standard VDMA, synchronous AXIS FIFO and our fixed raster adapter.

set_property CONFIG.PCW_USE_S_AXI_HP0 1 $ps7

ad_ip_instance clk_wiz video_clocks {
 PRIM_IN_FREQ 100.000 CLKOUT1_REQUESTED_OUT_FREQ 40.000
 CLKOUT2_USED true CLKOUT2_REQUESTED_OUT_FREQ 200.000
 USE_RESET true RESET_TYPE ACTIVE_LOW}

ad_connect sys_cpu_clk video_clocks/clk_in1
ad_connect sys_cpu_resetn video_clocks/resetn
ad_ip_instance proc_sys_reset video_reset {C_EXT_RST_WIDTH 1}
ad_connect video_clocks/clk_out1 video_reset/slowest_sync_clk
ad_connect video_clocks/locked video_reset/dcm_locked
ad_connect sys_cpu_resetn video_reset/ext_reset_in

ad_ip_instance axi_vdma video_vdma {
 c_include_s2mm 0 c_include_mm2s 1 c_include_sg 0
 c_m_axi_mm2s_data_width 64 c_m_axis_mm2s_tdata_width 24
 c_mm2s_linebuffer_depth 2048 c_num_fstores 1
 c_use_mm2s_fsync 0 c_include_mm2s_dre 1}

ad_connect sys_cpu_clk video_vdma/s_axi_lite_aclk
ad_connect sys_cpu_clk video_vdma/m_axi_mm2s_aclk
ad_connect video_clocks/clk_out1 video_vdma/m_axis_mm2s_aclk
ad_connect sys_cpu_resetn video_vdma/axi_resetn
ad_cpu_interconnect 0x43000000 video_vdma
ad_mem_hp0_interconnect sys_cpu_clk sys_ps7/S_AXI_HP0
ad_mem_hp0_interconnect sys_cpu_clk video_vdma/M_AXI_MM2S

ad_ip_instance axis_data_fifo video_fifo {
 TDATA_NUM_BYTES 3 TUSER_WIDTH 1 HAS_TLAST 1 FIFO_DEPTH 2048
 IS_ACLK_ASYNC 0 FIFO_MODE 1}

ad_connect video_clocks/clk_out1 video_fifo/s_axis_aclk
ad_connect video_reset/peripheral_aresetn video_fifo/s_axis_aresetn
ad_connect video_vdma/M_AXIS_MM2S video_fifo/S_AXIS

create_bd_cell -type ip -vlnv dlz0218.local:video:axi_video_to_rgb:1.0 video_out

ad_connect video_clocks/clk_out1 video_out/aclk
ad_connect video_reset/peripheral_aresetn video_out/aresetn
ad_connect video_fifo/M_AXIS video_out/s_axis

create_bd_cell -type ip -vlnv digilentinc.com:ip:rgb2dvi:1.2 video_phy
set_property -dict [list CONFIG.kGenerateSerialClk false CONFIG.kRstActiveHigh false] [get_bd_cells video_phy]

ad_connect video_clocks/clk_out1 video_phy/PixelClk
ad_connect video_clocks/clk_out2 video_phy/SerialClk
ad_connect video_reset/peripheral_aresetn video_phy/aRst_n

# fbdev words: R[23:16], G[15:8], B[7:0]. Digilent expects R,B,G.

foreach {name hi lo} {red 23 16 green 15 8 blue 7 0} {
 ad_ip_instance xlslice video_$name [list DIN_WIDTH 24 DIN_FROM $hi DIN_TO $lo DOUT_WIDTH 8]
 ad_connect video_out/rgb video_$name/Din
}

ad_ip_instance xlconcat video_rgb {NUM_PORTS 3 IN0_WIDTH 8 IN1_WIDTH 8 IN2_WIDTH 8}
ad_connect video_green/Dout video_rgb/In0
ad_connect video_blue/Dout video_rgb/In1
ad_connect video_red/Dout video_rgb/In2
ad_connect video_rgb/dout video_phy/vid_pData
ad_connect video_out/de video_phy/vid_pVDE
ad_connect video_out/hsync video_phy/vid_pHSync
ad_connect video_out/vsync video_phy/vid_pVSync

foreach p {TMDS_Clk_p TMDS_Clk_n} {
 create_bd_port -dir O $p
 ad_connect video_phy/$p $p
}

foreach p {TMDS_Data_p TMDS_Data_n} {
 create_bd_port -dir O -from 2 -to 0 $p
 ad_connect video_phy/$p $p
}

create_bd_port -dir O HDMI_OUT_EN1
ad_connect HDMI_OUT_EN1 VCC
