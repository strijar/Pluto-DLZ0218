create_bd_design system

set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 sys_ps7]
source [file join $src_dir ps7_config.tcl]

foreach interface {DDR FIXED_IO} {
  make_bd_intf_pins_external [get_bd_intf_pins sys_ps7/$interface]
  set_property name $interface [get_bd_intf_ports ${interface}_0]
}

source [file join $src_dir radio_bd.tcl]
source [file join $src_dir video_bd.tcl]

validate_bd_design
save_bd_design
