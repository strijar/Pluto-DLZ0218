set here [file dirname [file normalize [info script]]]
set dest [file normalize [lindex $argv 0]]

create_project -in_memory -part xc7z020clg400-2
add_files [glob $here/hdl/*.vhd]
set_property top axi_video_to_rgb [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $dest -vendor dlz0218.local -library video -taxonomy /Video_Imaging -import_files -set_current true

set core [ipx::current_core]

set_property name axi_video_to_rgb $core
set_property version 1.0 $core
set_property display_name {DLZ0218 AXIS to RGB 800x600} $core
ipx::infer_bus_interfaces xilinx.com:interface:axis_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:reset_rtl:1.0 $core
ipx::associate_bus_interfaces -busif s_axis -clock aclk $core

set rst [ipx::get_bus_interfaces aresetn -of_objects $core]
set p [ipx::add_bus_parameter POLARITY $rst]

set_property value ACTIVE_LOW $p

set clk [ipx::get_bus_interfaces aclk -of_objects $core]
set p [ipx::add_bus_parameter ASSOCIATED_RESET $clk]

set_property value aresetn $p
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

exit
