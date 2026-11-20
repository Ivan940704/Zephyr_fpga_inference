# Vivado 2018.3 isolated out-of-context synthesis/place/route frequency gate
# for the sparse-memory production accelerator_top.

if {$argc < 4} {
    error "Usage: run_accelerator_top_frequency_ooc.tcl <rtl_root> <frequency_mhz> <period_ns> <label>"
}
set rtl_root [file normalize [lindex $argv 0]]
set frequency_mhz [lindex $argv 1]
set period_ns [lindex $argv 2]
set label [lindex $argv 3]
if {![regexp {^[a-z0-9_]+$} $label]} {
    error "Frequency label must contain only lowercase letters, digits, or underscore"
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
set build_dir [file join $rtl_root build frequency_sweep $label]
set report_dir [file join $rtl_root reports accelerator_top_frequency_sweep $label]

foreach required [concat $sv_sources $v_sources] {
    if {![file exists $required]} {
        error "Missing accelerator-top source: $required"
    }
}

file delete -force $build_dir $report_dir
file mkdir $build_dir
file mkdir $report_dir

create_project -in_memory -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set_property include_dirs [list $rtl_root $sparse_rtl \
    [file join $rtl_root experiments realtime_layernorm data]] [current_fileset]
read_verilog -sv $sv_sources
read_verilog $v_sources
set frequency_xdc [file join $build_dir accelerator_top_frequency.xdc]
set xdc_handle [open $frequency_xdc w]
fconfigure $xdc_handle -translation lf
puts $xdc_handle "create_clock -period $period_ns -name clk \[get_ports clk\]"
puts $xdc_handle \
    "set_property HD.CLK_SRC BUFGCTRL_X0Y0 \[get_ports clk\]"
close $xdc_handle
read_xdc $frequency_xdc
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

set wns_ns [get_property SLACK $worst_path]
set estimated_delay_ns [expr {$period_ns - $wns_ns}]
set estimated_fmax_mhz [expr {1000.0 / $estimated_delay_ns}]
set timing_met [expr {$wns_ns >= 0.0 ? 1 : 0}]

set metrics_file [open [file join $report_dir metrics_post_synth.txt] w]
fconfigure $metrics_file -translation lf
puts $metrics_file "evidence=fresh_ooc_post_synthesis"
puts $metrics_file "part=xc7z020clg400-1"
puts $metrics_file "frequency_mhz=$frequency_mhz"
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

puts "ACCELERATOR_TOP_FREQUENCY_SYNTH frequency_mhz=$frequency_mhz wns=$wns_ns"

opt_design
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore

write_checkpoint -force [file join $build_dir accelerator_top_post_route.dcp]
report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical_post_route.rpt]
report_utilization \
    -file [file join $report_dir utilization_post_route.rpt]
report_route_status \
    -file [file join $report_dir route_status_post_route.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_route.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_post_route.rpt]
report_timing -delay_type min -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_hold_post_route.rpt]
check_timing -verbose \
    -file [file join $report_dir check_timing_post_route.rpt]
report_drc -file [file join $report_dir drc_post_route.rpt]

set route_utilization_text [report_utilization -return_string]
set slice_luts NA
set slice_registers NA
regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
    $route_utilization_text unused slice_luts
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
    $route_utilization_text unused slice_registers
set ramb36_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB36E1}]]
set ramb18_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB18E1}]]
set dsp_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ DSP48*}]]

set route_timing_path [get_timing_paths -delay_type max -max_paths 1 \
    -nworst 1 -quiet]
set route_wns_ns NA
set data_path_delay_ns NA
set route_timing_met 0
if {[llength $route_timing_path] > 0} {
    set route_wns_ns [get_property SLACK $route_timing_path]
    set data_path_delay_ns [get_property DATAPATH_DELAY $route_timing_path]
    set route_timing_met [expr {$route_wns_ns >= 0.0 ? 1 : 0}]
}
set hold_path [get_timing_paths -delay_type min -max_paths 1 \
    -nworst 1 -quiet]
set whs_ns NA
set hold_met 0
if {[llength $hold_path] > 0} {
    set whs_ns [get_property SLACK $hold_path]
    set hold_met [expr {$whs_ns >= 0.0 ? 1 : 0}]
}

set route_status_text [report_route_status -return_string]
set timing_check_text [check_timing -return_string]
set route_error_free [regexp \
    {# of nets with routing errors\.*\s*:\s*0\s*:} $route_status_text]
set no_unconstrained_internal [regexp \
    {There are 0 pins that are not constrained for maximum delay\.} \
    $timing_check_text]
set no_clockless_registers [regexp \
    {There are 0 register/latch pins with no clock\.} $timing_check_text]
set no_timing_loops [regexp \
    {There are 0 combinational loops in the design\.} $timing_check_text]
set no_drc_errors [expr {[llength [get_drc_violations -quiet \
    -filter {SEVERITY == Error}]] == 0}]

set bram_equiv [expr {$ramb36_count + ($ramb18_count / 2.0)}]
set resources_below_80 [expr {$slice_luts ne "NA" &&
    $slice_registers ne "NA" && $slice_luts < 42560 &&
    $slice_registers < 85120 && $bram_equiv < 112.0 && $dsp_count < 176}]

set route_metrics [open [file join $report_dir metrics_post_route.txt] w]
fconfigure $route_metrics -translation lf
puts $route_metrics "evidence=fresh_ooc_post_route"
puts $route_metrics "top=accelerator_top"
puts $route_metrics "part=xc7z020clg400-1"
puts $route_metrics "frequency_mhz=$frequency_mhz"
puts $route_metrics "target_period_ns=$period_ns"
puts $route_metrics "wns_ns=$route_wns_ns"
puts $route_metrics "data_path_delay_ns=$data_path_delay_ns"
puts $route_metrics "timing_met=$route_timing_met"
puts $route_metrics "whs_ns=$whs_ns"
puts $route_metrics "hold_met=$hold_met"
puts $route_metrics "slice_luts=$slice_luts"
puts $route_metrics "slice_registers=$slice_registers"
puts $route_metrics "ramb36_primitives=$ramb36_count"
puts $route_metrics "ramb18_primitives=$ramb18_count"
puts $route_metrics "dsp48_primitives=$dsp_count"
puts $route_metrics "resources_below_80_percent=$resources_below_80"
puts $route_metrics "routing_errors_zero=$route_error_free"
puts $route_metrics \
    "unconstrained_internal_endpoints_zero=$no_unconstrained_internal"
puts $route_metrics "clockless_registers_zero=$no_clockless_registers"
puts $route_metrics "combinational_loops_zero=$no_timing_loops"
puts $route_metrics "drc_errors_zero=$no_drc_errors"
close $route_metrics

puts "ACCELERATOR_TOP_FREQUENCY_ROUTE frequency_mhz=$frequency_mhz wns=$route_wns_ns whs=$whs_ns LUT=$slice_luts FF=$slice_registers RAMB36=$ramb36_count RAMB18=$ramb18_count DSP=$dsp_count"
close_project

if {!$route_timing_met || !$hold_met || !$resources_below_80 ||
    !$route_error_free || !$no_unconstrained_internal ||
    !$no_clockless_registers || !$no_timing_loops || !$no_drc_errors} {
    puts stderr "ACCELERATOR_TOP_FREQUENCY_GATE_FAIL frequency_mhz=$frequency_mhz"
    exit 2
}
puts "ACCELERATOR_TOP_FREQUENCY_GATE_PASS frequency_mhz=$frequency_mhz"
exit 0
