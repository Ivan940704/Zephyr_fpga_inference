# Elaborated hierarchy gate for the connected sequential-v4 subsystem.

if {$argc < 1} {
    error "Usage: check_sequential_v4_pe_memory_subsystem_hierarchy.tcl <rtl_root>"
}
set rtl_root [file normalize [lindex $argv 0]]
set pe_root [file join $rtl_root pe_array baseline v1 rtl]
set report_dir [file join $rtl_root reports sequential_v4_pe_memory_subsystem]
file mkdir $report_dir

set sv_sources [list \
    [file join $pe_root arithmetic pe_requant_lane.sv] \
    [file join $pe_root arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $pe_root pe pe_hybrid_mac.sv]]
set v_sources [list \
    [file join $rtl_root memory memory.v] \
    [file join $rtl_root memory model_memory_v4_table.v] \
    [file join $rtl_root memory memory_service.v] \
    [file join $rtl_root memory sequential_recurrent_context_store.v] \
    [file join $rtl_root memory sequential_pe_job_controller.v] \
    [file join $pe_root nonlinear pe_sigmoid_lut_255.v] \
    [file join $pe_root postprocess pe_gate_postprocess.v] \
    [file join $pe_root pe pe_membrane_sequencer.v] \
    [file join $pe_root stream pe_output_serializer.v] \
    [file join $pe_root stream pe_shared_requant_engine.v] \
    [file join $pe_root index pe_spike_decision.v] \
    [file join $pe_root index pe_active_index_writer.v] \
    [file join $pe_root pe pe_cdf_sequencer.v] \
    [file join $pe_root top pe_array_datapath.v] \
    [file join $rtl_root memory sequential_v4_pe_memory_subsystem.v]]
foreach required [concat $sv_sources $v_sources] {
    if {![file isfile $required]} {
        error "Missing hierarchy input: $required"
    }
}

create_project -in_memory -part xc7z020clg400-1
foreach source $sv_sources { read_verilog -sv $source }
foreach source $v_sources { read_verilog $source }
synth_design -rtl -top sequential_v4_pe_memory_subsystem \
    -part xc7z020clg400-1 -flatten_hierarchy none

proc count_ref {ref_name} {
    return [llength [get_cells -hierarchical -quiet -filter \
        "REF_NAME == $ref_name || REF_NAME =~ ${ref_name}__parameterized*"]]
}

set expected [list \
    [list memory_service 1] \
    [list memory 1] \
    [list model_memory_v4_table 1] \
    [list sequential_recurrent_context_store 1] \
    [list sequential_pe_job_controller 1] \
    [list pe_array_datapath 1] \
    [list pe_hybrid_mac 16] \
    [list pe_local_requant_bank_4lane 1] \
    [list pe_requant_lane 5] \
    [list pe_sigmoid_lut_255 1] \
    [list pe_gate_postprocess 1] \
    [list pe_membrane_sequencer 1] \
    [list pe_output_serializer 1] \
    [list pe_shared_requant_engine 1] \
    [list pe_spike_decision 1] \
    [list pe_active_index_writer 1] \
    [list pe_cdf_sequencer 1]]
set forbidden [list \
    parameter_weight_bank \
    matrix0_raw_accumulator_scratch \
    parameter_source_directory \
    active_index_list_store \
    parameter_membership_binding \
    parameter_axi_prefetch \
    parameter_tile_provider \
    parameter_ping_pong_owner]

set failed 0
set report [open [file join $report_dir hierarchy_elaborated.txt] w]
puts $report "top=sequential_v4_pe_memory_subsystem"
puts $report "part=xc7z020clg400-1"
foreach item $expected {
    set ref_name [lindex $item 0]
    set wanted [lindex $item 1]
    set actual [count_ref $ref_name]
    puts $report "$ref_name expected=$wanted actual=$actual"
    if {$actual != $wanted} {
        puts stderr "HIERARCHY ERROR: $ref_name expected=$wanted actual=$actual"
        set failed 1
    }
}
foreach ref_name $forbidden {
    set actual [count_ref $ref_name]
    puts $report "$ref_name forbidden actual=$actual"
    if {$actual != 0} {
        puts stderr "HIERARCHY ERROR: forbidden $ref_name actual=$actual"
        set failed 1
    }
}
close $report
if {$failed} {
    error "Sequential-v4 subsystem hierarchy does not match its contract"
}
puts "SEQUENTIAL_V4_SUBSYSTEM_HIERARCHY_PASS"
close_project
exit 0
