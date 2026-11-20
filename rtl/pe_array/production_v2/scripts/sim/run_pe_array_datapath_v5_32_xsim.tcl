# Vivado 2018.3/XSim connected integration runner for the image-v5 32-lane
# production datapath.  The frozen baseline leaf modules are compiled in place
# and are never copied back into the production tree.
if {$argc >= 1} {
    set repo_root [file normalize [lindex $argv 0]]
} else {
    set repo_root [file normalize [file join \
        [file dirname [file normalize [info script]]] ../../../../..]]
}

if {$tcl_platform(platform) eq "windows"} {
    set work_dir [file normalize [file join $::env(TEMP) \
        zephyr_fpga_xsim pe_array_datapath_v5_32_[pid]]]
    set python_command [list py -3]
} else {
    set work_dir [file join $repo_root rtl build xsim \
        pe_array_datapath_v5_32]
    set python_command [list python3]
}

set baseline [file join $repo_root rtl pe_array baseline v1 rtl]
set v2 [file join $repo_root rtl pe_array production_v2]
set reference [file join $v2 reference \
    pe_array_datapath_reference_v5_32.py]
set tb [file join $v2 tb integration tb_pe_array_datapath_v5_32.sv]
set sigmoid_table [file join $repo_root rtl pe_array baseline v1 tb vectors \
    pe_sigmoid_lut_255_tables.hex]

set sv_sources [list \
    [file join $baseline arithmetic pe_requant_lane.sv] \
    [file join $baseline arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $baseline pe pe_hybrid_mac.sv]]
set verilog_sources [list \
    [file join $baseline nonlinear pe_sigmoid_lut_255.v] \
    [file join $baseline postprocess pe_gate_postprocess.v] \
    [file join $baseline stream pe_shared_requant_engine.v] \
    [file join $baseline index pe_spike_decision.v] \
    [file join $baseline index pe_active_index_writer.v] \
    [file join $baseline pe pe_cdf_sequencer.v] \
    [file join $v2 rtl pe pe_hybrid_mac_array_32.v] \
    [file join $v2 rtl pe pe_membrane_sequencer_32.v] \
    [file join $v2 rtl stream pe_output_serializer_32.v] \
    [file join $v2 rtl top pe_array_datapath_v5_32.v]]
set sources [concat $sv_sources $verilog_sources]

foreach required [concat $sources [list $reference $tb $sigmoid_table]] {
    if {![file isfile $required]} {
        error "Missing image-v5 32-lane datapath input: $required"
    }
}

file delete -force $work_dir
file mkdir $work_dir
set local_sigmoid_table [file join $work_dir [file tail $sigmoid_table]]
file copy -force $sigmoid_table $local_sigmoid_table

set reference_command [concat $python_command [list $reference \
    --sigmoid-table $sigmoid_table --output-dir $work_dir]]
puts "PE_ARRAY_DATAPATH_V5_32_REFERENCE_COMMAND=$reference_command"
if {[catch {exec {*}$reference_command} reference_output]} {
    puts $reference_output
    error "Image-v5 32-lane datapath Python reference failed"
}
puts $reference_output
if {[string first "PE_ARRAY_DATAPATH_REFERENCE_PASS" $reference_output] < 0} {
    error "Image-v5 32-lane datapath reference PASS marker missing"
}

create_project pe_array_datapath_v5_32_sim $work_dir \
    -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse $sources
add_files -fileset sim_1 -norecurse $tb
set_property file_type SystemVerilog [get_files [concat $sv_sources [list $tb]]]
set_property file_type Verilog [get_files $verilog_sources]
set_property include_dirs [list $work_dir] [get_filesets sim_1]
set_property top tb_pe_array_datapath_v5_32 [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
set plusargs [format {-testplusarg LUT=%s} $local_sigmoid_table]
set_property -name xsim.simulate.xsim.more_options -value $plusargs \
    -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation
run all
set pass_value [get_value /tb_pe_array_datapath_v5_32/test_passed]
if {$pass_value ne "1"} {
    error "tb_pe_array_datapath_v5_32 did not assert test_passed"
}
puts "PE_ARRAY_DATAPATH_V5_32_CONNECTED_XSIM_PASS"
close_sim
close_project
