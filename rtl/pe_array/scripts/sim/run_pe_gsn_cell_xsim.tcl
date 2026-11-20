if {$argc >= 1} {set pe_root [file normalize [lindex $argv 0]]} else {set pe_root [file normalize [file join [file dirname [file normalize [info script]]] ../..]]}
if {$tcl_platform(platform) eq "windows"} {set work [file normalize [file join $::env(TEMP) zephyr_fpga_xsim pe_gsn_cell_[pid]]]} else {set work [file join $pe_root build xsim pe_gsn_cell]}
set sources [list [file join $pe_root rtl arithmetic pe_requant_lane.sv] [file join $pe_root rtl pe pe_hybrid_mac.sv] [file join $pe_root rtl nonlinear pe_sigmoid_lut_255.sv] [file join $pe_root rtl gsn pe_gsn_cell.sv]]
set tb [file join $pe_root tb integration tb_pe_gsn_cell.sv]
set vector [file join $pe_root tb vectors pe_gsn_cell_vectors.hex];set count_path [file join $pe_root tb vectors pe_gsn_cell_vectors.count]
set lut0 [file join $pe_root tb vectors pe_gsn_cell_lut0.hex];set lut1 [file join $pe_root tb vectors pe_gsn_cell_lut1.hex]
set f [open $count_path r];set count [string trim [read $f]];close $f
file delete -force $work;file mkdir $work
foreach src [list $vector $lut0 $lut1] {file copy -force $src [file join $work [file tail $src]]}
create_project pe_gsn_cell_sim $work -part xc7z020clg400-1 -force
add_files -norecurse $sources;add_files -fileset sim_1 -norecurse $tb
set_property file_type SystemVerilog [get_files [concat $sources [list $tb]]]
set_property top tb_pe_gsn_cell [get_filesets sim_1];set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set opts [format {-testplusarg VECTORS=%s -testplusarg COUNT=%s -testplusarg LUT0=%s -testplusarg LUT1=%s} [file join $work [file tail $vector]] $count [file join $work [file tail $lut0]] [file join $work [file tail $lut1]]]
set_property -name xsim.simulate.xsim.more_options -value $opts -objects [get_filesets sim_1]
update_compile_order -fileset sources_1;update_compile_order -fileset sim_1
launch_simulation;run all
if {[get_value /tb_pe_gsn_cell/test_passed] ne "1"} {error "GSN cell TB failed"}
close_sim;close_project
