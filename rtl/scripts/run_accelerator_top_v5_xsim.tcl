# Vivado 2018.3 connected elaboration/timing-cut regression for the image-v5,
# PL-LayerNorm, 32-lane production accelerator top.
# Argument: <repo_root>
if {$argc < 1} {
    error "Usage: run_accelerator_top_v5_xsim.tcl <repo_root>"
}
set repo_root [file normalize [lindex $argv 0]]
set rtl_root [file join $repo_root rtl]
set baseline [file join $rtl_root pe_array baseline v1 rtl]
set v2 [file join $rtl_root pe_array production_v2]
set layernorm [file join $rtl_root experiments realtime_layernorm]
if {$tcl_platform(platform) eq "windows"} {
    set work_dir [file normalize [file join $::env(TEMP) \
        zephyr_fpga_xsim accelerator_top_v5_[pid]]]
} else {
    set work_dir [file join $rtl_root build xsim accelerator_top_v5]
}

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
    [file join $rtl_root memory sequential_v5_pe_memory_subsystem.v] \
    [file join $rtl_root memory layernorm_mailbox.v] \
    [file join $rtl_root control fsm.v] \
    [file join $rtl_root integration layernorm_mailbox_fsm_adapter.v] \
    [file join $rtl_root integration sequential_feature_dispatcher.v] \
    [file join $rtl_root integration sequential_df_coefficient_store.v] \
    [file join $rtl_root integration hybrid_pe_deepfilter_controller.v] \
    [file join $layernorm layernorm_engine_q12.v] \
    [file join $layernorm layernorm_parameter_rom_q12.v] \
    [file join $layernorm realtime_layernorm_coordinator.v] \
    [file join $rtl_root top accelerator_top.v]]
set tb [file join $rtl_root tb tb_accelerator_top_timing_cut.sv]
set headers [glob -nocomplain [file join $layernorm data *.vh]]
set sources [concat $sv_sources $verilog_sources]
foreach required [concat $sources $headers [list $tb]] {
    if {![file isfile $required]} {
        error "Missing accelerator-top-v5 XSim input: $required"
    }
}

file delete -force $work_dir
file mkdir $work_dir
foreach header $headers {
    file copy -force $header [file join $work_dir [file tail $header]]
}
create_project accelerator_top_v5_sim $work_dir \
    -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
set include_dirs [list $work_dir $rtl_root [file join $layernorm data]]
set_property include_dirs $include_dirs [current_fileset]
add_files -norecurse $sources
add_files -fileset sim_1 -norecurse $tb
set_property file_type SystemVerilog [get_files [concat $sv_sources [list $tb]]]
set_property file_type Verilog [get_files $verilog_sources]
set_property include_dirs $include_dirs [get_filesets sources_1]
set_property include_dirs $include_dirs [get_filesets sim_1]
set_property top tb_accelerator_top_timing_cut [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
set checks [get_value /tb_accelerator_top_timing_cut/checks]
if {$checks ne "17"} {
    error "accelerator_top_v5 timing-cut checks=$checks expected=17"
}
puts "ACCELERATOR_TOP_V5_CONNECTED_XSIM_PASS"
close_sim
close_project
