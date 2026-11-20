# Vivado 2018.3/XSim connected two-frame regression for the image-v5 memory,
# 32-row controller/context store, and production-v2 32-lane datapath.
# Arguments: <repo_root> ?parameter_image? ?sparse_mode?
if {$argc < 1} {
    error "Usage: run_sequential_v5_pe_memory_subsystem_xsim.tcl <repo_root> ?parameter_image? ?sparse_mode?"
}
# Vivado 2018.3 on this Windows host incorrectly collapses the literal
# "Documents" component while normalizing the workspace path.  Keep the
# caller-supplied absolute path verbatim; all derived paths are absolute.
set repo_root [lindex $argv 0]
set rtl_root [file join $repo_root rtl]
set image_path [expr {$argc >= 2
    ? [lindex $argv 1]
    : [file join $repo_root outputs memory 2026-09-09 v5 parameters_v5.bin]}]
set sparse_mode [expr {$argc >= 3 ? [lindex $argv 2] : 0}]
set state_path [file join $rtl_root tb \
    sequential_v5_stage0_two_frame_state.hex]
set baseline [file join $rtl_root pe_array baseline v1 rtl]
set v2 [file join $rtl_root pe_array production_v2]

set work_dir [file join $rtl_root build xsim sequential_v5_subsystem_[pid]]

set sv_sources [list \
    [file join $rtl_root memory sparse_stage_map_v5.sv] \
    [file join $rtl_root memory sparse_union_planner_v5.sv] \
    [file join $baseline arithmetic pe_requant_lane.sv] \
    [file join $baseline arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $baseline pe pe_hybrid_mac.sv]]
set verilog_sources [list \
    [file join $rtl_root memory memory_wide256.v] \
    [file join $rtl_root memory model_memory_v5_table.v] \
    [file join $rtl_root memory memory_service_v5.v] \
    [file join $rtl_root memory sequential_recurrent_context_store_v5.v] \
    [file join $rtl_root memory sequential_pe_job_controller_v5.v] \
    [file join $baseline nonlinear pe_sigmoid_lut_255.v] \
    [file join $baseline postprocess pe_gate_postprocess.v] \
    [file join $baseline stream pe_shared_requant_engine.v] \
    [file join $baseline index pe_spike_decision.v] \
    [file join $baseline index pe_active_index_writer.v] \
    [file join $baseline pe pe_cdf_sequencer.v] \
    [file join $v2 rtl pe pe_hybrid_mac_array_32.v] \
    [file join $v2 rtl pe pe_membrane_sequencer_32.v] \
    [file join $v2 rtl stream pe_output_serializer_32.v] \
    [file join $v2 rtl top pe_array_datapath_v5_32.v] \
    [file join $rtl_root integration hybrid_pe_deepfilter_controller.v] \
    [file join $rtl_root memory sequential_v5_pe_memory_subsystem.v]]
set tb [file join $rtl_root tb tb_sequential_v5_pe_memory_subsystem.sv]
set sources [concat $sv_sources $verilog_sources]

foreach required [concat $sources [list $tb $image_path $state_path]] {
    if {![file isfile $required]} {
        error "Missing sequential-v5 connected-test input: $required"
    }
}

file delete -force $work_dir
file mkdir $work_dir
create_project sequential_v5_subsystem_sim $work_dir \
    -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
set_property include_dirs [list $rtl_root] [current_fileset]
add_files -norecurse $sources
add_files -fileset sim_1 -norecurse $tb
set_property file_type SystemVerilog [get_files [concat $sv_sources [list $tb]]]
set_property file_type Verilog [get_files $verilog_sources]
set_property include_dirs [list $rtl_root] [get_filesets sim_1]
set_property top tb_sequential_v5_pe_memory_subsystem [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
set plusargs [format \
    {-testplusarg IMAGE=%s -testplusarg STATE=%s -testplusarg SPARSE=%s} \
    $image_path $state_path $sparse_mode]
set_property -name xsim.simulate.xsim.more_options -value $plusargs \
    -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation
run all
set failures [get_value /tb_sequential_v5_pe_memory_subsystem/failures]
if {$failures ne "0"} {
    error "Sequential-v5 connected subsystem reported $failures failures"
}
puts "SEQUENTIAL_V5_PE_MEMORY_SUBSYSTEM_CONNECTED_XSIM_PASS"
close_sim
close_project
