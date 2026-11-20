# Vivado 2018.3/XSim connected integration runner for pe_array_datapath.
if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set pe_root [file normalize [file join \
        [file dirname [file normalize [info script]]] ../..]]
}

if {$tcl_platform(platform) eq "windows"} {
    set work_dir [file normalize [file join $::env(TEMP) \
        zephyr_fpga_xsim pe_array_datapath_[pid]]]
    set python_command [list py -3]
} else {
    set work_dir [file join $pe_root build xsim pe_array_datapath]
    set python_command [list python3]
}

set baseline [file join $pe_root baseline v1]
set reference [file join $pe_root reference pe_array_datapath_reference.py]
set wrapper [file join $pe_root rtl top pe_array_datapath.v]
set tb [file join $pe_root tb integration tb_pe_array_datapath.sv]
set sigmoid_table [file join $baseline tb vectors \
    pe_sigmoid_lut_255_tables.hex]

set sources [list \
    [file join $baseline rtl arithmetic pe_requant_lane.sv] \
    [file join $baseline rtl arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $baseline rtl pe pe_hybrid_mac.sv] \
    [file join $baseline rtl nonlinear pe_sigmoid_lut_255.v] \
    [file join $baseline rtl postprocess pe_gate_postprocess.v] \
    [file join $baseline rtl pe pe_membrane_sequencer.v] \
    [file join $baseline rtl stream pe_output_serializer.v] \
    [file join $baseline rtl stream pe_shared_requant_engine.v] \
    [file join $baseline rtl index pe_spike_decision.v] \
    [file join $baseline rtl index pe_active_index_writer.v] \
    [file join $baseline rtl pe pe_cdf_sequencer.v] \
    $wrapper]

foreach required [concat $sources [list $reference $tb $sigmoid_table]] {
    if {![file exists $required]} {
        error "Missing required PE-datapath integration file: $required"
    }
}

file delete -force $work_dir
file mkdir $work_dir
set local_sigmoid_table [file join $work_dir [file tail $sigmoid_table]]
file copy -force $sigmoid_table $local_sigmoid_table

set reference_command [concat $python_command [list $reference \
    --sigmoid-table $sigmoid_table --output-dir $work_dir]]
puts "PE_ARRAY_DATAPATH_REFERENCE_COMMAND=$reference_command"
if {[catch {exec {*}$reference_command} reference_output]} {
    puts $reference_output
    error "PE Array datapath Python reference failed"
}
puts $reference_output
if {[string first "PE_ARRAY_DATAPATH_REFERENCE_PASS" $reference_output] < 0} {
    error "PE Array datapath Python reference PASS marker missing"
}

create_project pe_array_datapath_sim $work_dir \
    -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse $sources
add_files -fileset sim_1 -norecurse $tb

# Preserve the production wrapper's Verilog-2001 compile mode.  Only the
# three archived historical .sv leaves and the verification TB use SV mode.
set_property file_type SystemVerilog [get_files [list \
    [file join $baseline rtl arithmetic pe_requant_lane.sv] \
    [file join $baseline rtl arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $baseline rtl pe pe_hybrid_mac.sv] $tb]]
set_property file_type Verilog [get_files [lrange $sources 3 end]]

set_property include_dirs [list $work_dir] [get_filesets sim_1]
set_property top tb_pe_array_datapath [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
set plusargs [format {-testplusarg LUT=%s} $local_sigmoid_table]
set_property -name xsim.simulate.xsim.more_options -value $plusargs \
    -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation
run all
set pass_value [get_value /tb_pe_array_datapath/test_passed]
if {$pass_value ne "1"} {
    error "tb_pe_array_datapath did not assert test_passed"
}
puts "PE_ARRAY_DATAPATH_CONNECTED_XSIM_PASS"
close_sim
close_project

