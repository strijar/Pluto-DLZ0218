# Gray buses: flight time bounded to one source period (not false-pathed).
# This file is scoped to axi_hdmi_audio by the IP package.

set wr_src [get_cells -hier -filter {NAME =~ *wg_reg* || NAME =~ *wb_reg*}]
set rd_src [get_cells -hier -filter {NAME =~ *rg_reg* || NAME =~ *rb_reg*}]
set wr_dst [get_cells -hier -filter {NAME =~ *wg_s1_reg*}]
set rd_dst [get_cells -hier -filter {NAME =~ *rg_s1_reg*}]
set_max_delay -datapath_only 10.0 -from $wr_src -to $wr_dst
set_bus_skew 10.0 -from $wr_src -to $wr_dst
set_max_delay -datapath_only 25.0 -from $rd_src -to $rd_dst
set_bus_skew 25.0 -from $rd_src -to $rd_dst
set single_sync [get_cells -hier -filter {NAME =~ *en_s1_reg || NAME =~ *hold_s1_reg || NAME =~ *ack_s1_reg || NAME =~ *under_s1_reg}]
set_false_path -to [get_pins -of_objects $single_sync -filter {REF_PIN_NAME == D || REF_PIN_NAME == S || REF_PIN_NAME == R}]
set reset_sync [get_cells -hier -filter {NAME =~ *axi_rst_pipe_reg* || NAME =~ *pix_rst_pipe_reg*}]
set_false_path -to [get_pins -of_objects $reset_sync -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
