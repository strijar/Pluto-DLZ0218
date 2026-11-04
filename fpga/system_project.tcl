# Run from any directory; all generated files stay in fpga/build.
set src_dir [file dirname [file normalize [info script]]]
set build_dir [file join $src_dir build]
set export_dir [file join $build_dir export]
set action [lindex $argv 0]
if {$action eq ""} {set action build}
if {$action ni {project build}} {error "Expected project or build"}
file mkdir $export_dir
cd $build_dir
create_project dlz0218_sdr $build_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set ad_hdl_dir [file normalize [file join $src_dir .. hdl]]
source [file join $ad_hdl_dir projects scripts adi_board.tcl]
set sys_zynq 1
set_property ip_repo_paths [file join $build_dir hdl library] [current_project]
update_ip_catalog
source [file join $src_dir system_bd.tcl]
add_files -fileset constrs_1 [file join $src_dir system_constr.xdc]
set bd_file [get_files system.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

# Copy the init generated from this exact configuration, never from the seller SDK.
set ip_dir [file join $build_dir dlz0218_sdr.srcs sources_1 bd system ip system_sys_ps7_0]
foreach name {ps7_init.tcl ps7_init.c ps7_init.h ps7_init_gpl.c ps7_init_gpl.h ps7_init.html ps7_parameters.xml} {
  set path [file join $ip_dir $name]
  if {![file exists $path]} {error "Missing generated PS7 file: $path"}
  file copy -force $path $export_dir
}
write_bd_tcl -force [file join $export_dir system_bd_generated.tcl]
write_hw_platform -fixed -force -file [file join $export_dir dlz0218_sdr.xsa]
if {$action eq "project"} {exit 0}
set jobs 4
if {[info exists ::env(JOBS)]} {set jobs $::env(JOBS)}
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_timing_summary -file [file join $export_dir timing_summary.rpt]
report_drc -file [file join $export_dir drc.rpt]
write_hw_platform -fixed -include_bit -force -file [file join $export_dir dlz0218_sdr.xsa]
file copy -force [file join $build_dir dlz0218_sdr.runs impl_1 system_wrapper.bit] [file join $export_dir system.bit]
exit 0
