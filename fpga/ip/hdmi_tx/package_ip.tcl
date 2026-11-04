set here [file dirname [file normalize [info script]]]
set vendor [file normalize [file join $here ../../vendor/rgb2dvi_v1_2/src]]
set dest [file normalize [lindex $argv 0]]

create_project -in_memory -part xc7z020clg400-2

add_files [glob $here/hdl/*.vhd]

foreach name {DVI_Constants.vhd SyncAsyncReset.vhd SyncAsync.vhd OutputSERDES.vhd} {
 add_files [file join $vendor $name]
}

add_files -fileset constrs_1 [file join $vendor rgb2dvi.xdc]
set_property SCOPED_TO_REF rgb2hdmi [get_files rgb2dvi.xdc]
set_property top rgb2hdmi [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $dest -vendor dlz0218.local -library video -taxonomy /Video_Imaging -import_files -set_current true

set core [ipx::current_core]

set_property name rgb2hdmi $core
set_property version 1.0 $core
set_property display_name {DLZ0218 HDMI 800x600 + 48kHz test tone} $core
ipx::infer_bus_interfaces xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:reset_rtl:1.0 $core

# TMDS clock pins carry serialized symbols, not fabric clock interfaces.

foreach port {TMDS_Clk_p TMDS_Clk_n} {
 ipx::remove_bus_interface $port $core
}

set rgbif [ipx::add_bus_interface RGB $core]

set_property bus_type_vlnv xilinx.com:interface:vid_io:1.0 $rgbif
set_property abstraction_type_vlnv xilinx.com:interface:vid_io_rtl:1.0 $rgbif
set_property interface_mode slave $rgbif

foreach {logical physical} {DATA rgb ACTIVE_VIDEO de HSYNC hsync VSYNC vsync} {
 set mapping [ipx::add_port_map $logical $rgbif]
 set_property physical_name $physical $mapping
}

ipx::associate_bus_interfaces -busif RGB -clock pixel_clk $core
set audioif [ipx::add_bus_interface pcm $core]
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 $audioif
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 $audioif
set_property interface_mode slave $audioif

foreach {logical physical} {TDATA pcm_data TVALID pcm_valid TREADY pcm_ready} {
 set p [ipx::add_port_map $logical $audioif]
 set_property physical_name $physical $p
}

ipx::associate_bus_interfaces -busif pcm -clock pixel_clk $core

foreach clock {pixel_clk serial_clk} {
 set clk [ipx::get_bus_interfaces $clock -of_objects $core]
 set p [ipx::add_bus_parameter ASSOCIATED_RESET $clk]
 set_property value resetn $p
}

set rst [ipx::get_bus_interfaces resetn -of_objects $core]
set p [ipx::add_bus_parameter POLARITY $rst]
set_property value ACTIVE_LOW $p

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

exit
