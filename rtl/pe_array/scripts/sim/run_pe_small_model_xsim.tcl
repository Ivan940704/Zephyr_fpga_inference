if {$argc >= 1} {set pe_root [file normalize [lindex $argv 0]]} else {
 set pe_root [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
}
if {$tcl_platform(platform) eq "windows"} {set work_dir [file normalize [file join $::env(TEMP) zephyr_fpga_xsim pe_small_model_[pid]]]} else {set work_dir [file join $pe_root build xsim pe_small_model]}
set mac [file join $pe_root rtl pe pe_hybrid_mac.sv]
set ctl [file join $pe_root rtl control pe_array_controller.sv]
set top [file join $pe_root rtl top pe_array_top.sv]
set tb [file join $pe_root tb integration tb_pe_small_model.sv]
set vectors [file join $pe_root tb vectors pe_small_model_commands.hex]
set count_file [file join $pe_root tb vectors pe_small_model_commands.count]
set f [open $count_file r];set command_count [string trim [read $f]];close $f
file delete -force $work_dir;file mkdir $work_dir
set local_vectors [file join $work_dir pe_small_model_commands.hex];file copy -force $vectors $local_vectors
create_project pe_small_model_sim $work_dir -part xc7z020clg400-1 -force
add_files -norecurse [list $mac $ctl $top];add_files -fileset sim_1 -norecurse $tb
set_property file_type SystemVerilog [get_files [list $mac $ctl $top $tb]]
set_property top tb_pe_small_model [get_filesets sim_1];set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set opts [format {-testplusarg COMMAND_FILE=%s -testplusarg COMMAND_COUNT=%s} [file normalize $local_vectors] $command_count]
set_property -name xsim.simulate.xsim.more_options -value $opts -objects [get_filesets sim_1]
update_compile_order -fileset sources_1;update_compile_order -fileset sim_1
launch_simulation;run all
if {[get_value /tb_pe_small_model/test_passed] ne "1"} {error "small-model TB failed"}
close_sim;close_project
