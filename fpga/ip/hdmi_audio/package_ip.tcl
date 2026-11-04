set here [file dirname [file normalize [info script]]]
set dest [file normalize [lindex $argv 0]]

create_project -in_memory -part xc7z020clg400-2

add_files [glob $here/hdl/*.vhd]
add_files -fileset constrs_1 $here/audio_cdc.xdc
set_property SCOPED_TO_REF axi_hdmi_audio [get_files audio_cdc.xdc]
set_property top axi_hdmi_audio [current_fileset]

update_compile_order -fileset sources_1
ipx::package_project -root_dir $dest -vendor dlz0218.local -library audio -taxonomy /Audio -import_files -set_current true

set core [ipx::current_core]

set_property name axi_hdmi_audio $core
set_property version 1.0 $core
set_property display_name {DLZ0218 ADI-compatible HDMI PCM TX} $core
ipx::infer_bus_interfaces xilinx.com:interface:aximm_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:reset_rtl:1.0 $core

proc stream {name mode mapping clock reset} {
 global core
 set bus [ipx::add_bus_interface $name $core]
 set_property bus_type_vlnv xilinx.com:interface:axis:1.0 $bus
 set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 $bus
 set_property interface_mode $mode $bus

 foreach {logical physical} $mapping {
  set p [ipx::add_port_map $logical $bus]
  set_property physical_name $physical $p
 }

 ipx::associate_bus_interfaces -busif $name -clock $clock $core
}

stream dma_req master {TVALID dma_drvalid TREADY dma_drready TUSER dma_drtype TLAST dma_drlast} s_axi_aclk s_axi_aresetn
stream dma_ack slave {TVALID dma_davalid TREADY dma_daready TUSER dma_datype} s_axi_aclk s_axi_aresetn
stream pcm master {TDATA pcm_data TVALID pcm_valid TREADY pcm_ready} pixel_clk pixel_resetn
ipx::associate_bus_interfaces -busif s_axi -clock s_axi_aclk $core

foreach {clock reset} {s_axi_aclk s_axi_aresetn pixel_clk pixel_resetn} {
 set p [ipx::add_bus_parameter ASSOCIATED_RESET [ipx::get_bus_interfaces $clock -of_objects $core]]
 set_property value $reset $p
 set p [ipx::add_bus_parameter POLARITY [ipx::get_bus_interfaces $reset -of_objects $core]]
 set_property value ACTIVE_LOW $p
}

# Standard register aperture, including the DMA FIFO at 0x2c.

set mm [ipx::get_memory_maps s_axi -of_objects $core]

if {![llength $mm]} {set mm [ipx::add_memory_map s_axi $core]}

set ab [ipx::get_address_blocks reg0 -of_objects $mm]

if {![llength $ab]} {set ab [ipx::add_address_block reg0 $mm]}

set_property range 65536 $ab
set_property width 32 $ab
set_property slave_memory_map_ref s_axi [ipx::get_bus_interfaces s_axi -of_objects $core]

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

exit
