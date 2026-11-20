if {$argc >= 1} { set pe_root [file normalize [lindex $argv 0]] } else {
  set pe_root [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
}
if {$tcl_platform(platform) eq "windows"} {
  set work_dir [file normalize [file join $::env(TEMP) zephyr_fpga_xsim pe_array_support_[pid]]]
} else { set work_dir [file join $pe_root build xsim pe_array_support] }
set sources [list \
  [file join $pe_root rtl arithmetic pe_requant_lane.sv] \
  [file join $pe_root rtl nonlinear pe_sigmoid_lut_255.sv] \
  [file join $pe_root rtl stream pe_output_serializer.sv] \
  [file join $pe_root rtl stream pe_shared_requant_engine.sv] \
  [file join $pe_root rtl index pe_spike_decision.sv] \
  [file join $pe_root rtl index pe_active_index_writer.sv] \
  [file join $pe_root rtl index pe_active_index_buffer.sv] \
  [file join $pe_root rtl pe pe_membrane_sequencer.sv] \
  [file join $pe_root rtl control pe_array_controller.sv]]
set tb [file join $pe_root tb unit tb_pe_array_support.sv]
set vectors [file join $pe_root tb vectors pe_sigmoid_lut_fb1.hex]
file delete -force $work_dir; file mkdir $work_dir
file copy -force $vectors [file join $work_dir pe_sigmoid_lut_fb1.hex]
create_project pe_array_support_sim $work_dir -part xc7z020clg400-1 -force
add_files -norecurse $sources; add_files -fileset sim_1 -norecurse $tb
set_property file_type SystemVerilog [get_files [concat $sources [list $tb]]]
set_property top tb_pe_array_support [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set plusarg [format {-testplusarg LUT_FILE=%s} [file normalize [file join $work_dir pe_sigmoid_lut_fb1.hex]]]
set_property -name xsim.simulate.xsim.more_options -value $plusarg -objects [get_filesets sim_1]
update_compile_order -fileset sources_1; update_compile_order -fileset sim_1
launch_simulation; run all
if {[get_value /tb_pe_array_support/test_passed] ne "1"} { error "support TB failed" }
close_sim; close_project
