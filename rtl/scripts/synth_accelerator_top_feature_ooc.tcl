# Vivado 2018.3 out-of-context synthesis for the sparse-memory production
# accelerator_top through the feature/DeepFilter integration boundary.

if {$argc >= 1} {
    set rtl_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set rtl_root [file normalize [file join $script_dir ..]]
}

set pe_root [file join $rtl_root pe_array baseline v1 rtl]
set repo_root [file normalize [file join $rtl_root ..]]
set sparse_rtl [file join $repo_root sparse_memory_v1 rtl]
set sv_sources [list \
    [file join $pe_root arithmetic pe_requant_lane.sv] \
    [file join $pe_root arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $pe_root pe pe_hybrid_mac.sv] \
    [file join $sparse_rtl sparse_memory_service_v1.sv] \
    [file join $sparse_rtl sparse_stage_map_v1.sv] \
    [file join $sparse_rtl sparse_union_planner_v1.sv] \
    [file join $sparse_rtl sparse_recurrent_context_store_v1.sv] \
    [file join $sparse_rtl sequential_v4_sparse_memory_subsystem.sv]]
set v_sources [list \
    [file join $sparse_rtl sparse_memory_dma_v1.v] \
    [file join $sparse_rtl sparse_memory_v4_table_v1.v] \
    [file join $sparse_rtl sparse_recurrent_context_store_core_v1.v] \
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
    [file join $rtl_root memory layernorm_mailbox.v] \
    [file join $rtl_root control fsm.v] \
    [file join $rtl_root integration layernorm_mailbox_fsm_adapter.v] \
    [file join $rtl_root integration sequential_feature_dispatcher.v] \
    [file join $rtl_root integration sequential_df_coefficient_store.v] \
    [file join $rtl_root integration hybrid_pe_deepfilter_controller.v] \
    [file join $rtl_root experiments realtime_layernorm layernorm_engine_q12.v] \
    [file join $rtl_root experiments realtime_layernorm layernorm_parameter_rom_q12.v] \
    [file join $rtl_root experiments realtime_layernorm realtime_layernorm_coordinator.v] \
    [file join $rtl_root top accelerator_top.v]]
set xdc_file [file join $rtl_root top accelerator_top_100mhz.xdc]
set build_dir [file join $rtl_root build synth accelerator_top_feature]
set report_dir [file join $rtl_root reports accelerator_top_sparse_timing]

foreach required [concat $sv_sources $v_sources [list $xdc_file]] {
    if {![file exists $required]} {
        error "Missing accelerator-top source: $required"
    }
}

file delete -force $build_dir
file mkdir $build_dir
file mkdir $report_dir

create_project -in_memory -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set_property include_dirs [list $rtl_root $sparse_rtl \
    [file join $rtl_root experiments realtime_layernorm data]] [current_fileset]
read_verilog -sv $sv_sources
read_verilog $v_sources
read_xdc $xdc_file
synth_design -top accelerator_top -part xc7z020clg400-1 \
    -mode out_of_context -flatten_hierarchy rebuilt

write_checkpoint -force \
    [file join $build_dir accelerator_top_feature_post_synth.dcp]
report_utilization -hierarchical \
    -file [file join $report_dir utilization_post_synth.rpt]
report_timing_summary -delay_type max -max_paths 10 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_synth.rpt]
report_timing -delay_type max -max_paths 10 -sort_by group \
    -file [file join $report_dir timing_paths_post_synth.rpt]
check_timing -verbose \
    -file [file join $report_dir check_timing_post_synth.rpt]

set utilization_text [report_utilization -hierarchical -return_string]
set utilization_pattern {\|\s+accelerator_top\s+\|\s+\(top\)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|}
if {![regexp $utilization_pattern $utilization_text unused \
        total_luts logic_luts lutrams srls total_ffs ramb36 ramb18 total_dsps]} {
    error "Could not parse accelerator_top utilization row"
}

set worst_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $worst_path] == 0} {
    error "No timed accelerator_top path was found after synthesis"
}

set period_ns 10.000
set wns_ns [get_property SLACK $worst_path]
set estimated_delay_ns [expr {$period_ns - $wns_ns}]
set estimated_fmax_mhz [expr {1000.0 / $estimated_delay_ns}]
set timing_met [expr {$wns_ns >= 0.0 ? 1 : 0}]

set metrics_file [open [file join $report_dir metrics_post_synth.txt] w]
fconfigure $metrics_file -translation lf
puts $metrics_file "evidence=ooc_post_synthesis_only"
puts $metrics_file "part=xc7z020clg400-1"
puts $metrics_file "target_period_ns=$period_ns"
puts $metrics_file "wns_ns=$wns_ns"
puts $metrics_file "estimated_critical_delay_ns=$estimated_delay_ns"
puts $metrics_file "estimated_fmax_mhz=$estimated_fmax_mhz"
puts $metrics_file "timing_met=$timing_met"
puts $metrics_file "total_luts=$total_luts"
puts $metrics_file "logic_luts=$logic_luts"
puts $metrics_file "lutram_luts=$lutrams"
puts $metrics_file "srl_luts=$srls"
puts $metrics_file "total_ffs=$total_ffs"
puts $metrics_file "ramb36=$ramb36"
puts $metrics_file "ramb18=$ramb18"
puts $metrics_file "total_dsps=$total_dsps"
close $metrics_file

puts "ACCELERATOR_TOP_FEATURE_OOC_METRIC wns_ns=$wns_ns"
puts "ACCELERATOR_TOP_FEATURE_OOC_METRIC total_luts=$total_luts"
puts "ACCELERATOR_TOP_FEATURE_OOC_METRIC total_ffs=$total_ffs"
puts "ACCELERATOR_TOP_FEATURE_OOC_METRIC ramb36=$ramb36"
puts "ACCELERATOR_TOP_FEATURE_OOC_METRIC ramb18=$ramb18"
puts "ACCELERATOR_TOP_FEATURE_OOC_METRIC total_dsps=$total_dsps"
close_project

if {$timing_met} {
    puts "ACCELERATOR_TOP_FEATURE_SYNTH_TIMING_PASS"
} else {
    puts "ACCELERATOR_TOP_FEATURE_SYNTH_TIMING_PENDING_ROUTE WNS=$wns_ns"
}
