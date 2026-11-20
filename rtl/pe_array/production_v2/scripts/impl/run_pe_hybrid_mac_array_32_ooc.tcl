if {$argc < 1} {
    error "Usage: run_pe_hybrid_mac_array_32_ooc.tcl <100mhz|102mhz>"
}
set script_dir [file dirname [string map {\\ /} [info script]]]
set repo_root [file join $script_dir .. .. .. .. ..]
set label [lindex $argv 0]
if {$label eq "100mhz"} {
    set frequency_mhz 100
    set period_ns 10.000
} elseif {$label eq "102mhz"} {
    set frequency_mhz 102
    set period_ns 9.804
} else {
    error "Unsupported Phase 5A frequency label: $label"
}

set v2_root [file join $repo_root rtl pe_array production_v2]
set mac [file join $repo_root rtl pe_array baseline v1 rtl pe pe_hybrid_mac.sv]
set array [file join $v2_root rtl pe pe_hybrid_mac_array_32.v]
set xdc [file join $v2_root constraints pe_hybrid_mac_array_32_${label}.xdc]
set build_dir [file join $repo_root rtl build production_v2_pe_hybrid_mac_array_32 $label]
set report_dir [file join $repo_root rtl reports production_v2_pe_hybrid_mac_array_32 $label]

foreach required [list $mac $array $xdc] {
    if {![file isfile $required]} {
        error "Missing Phase 5A implementation input: $required"
    }
}
file delete -force $build_dir $report_dir
file mkdir $build_dir
file mkdir $report_dir

create_project -in_memory -part xc7z020clg400-1
set_property target_language Verilog [current_project]
read_verilog -sv $mac
read_verilog $array
read_xdc $xdc
synth_design -top pe_hybrid_mac_array_32 -part xc7z020clg400-1 \
    -mode out_of_context -flatten_hierarchy none

write_checkpoint -force [file join $build_dir post_synth.dcp]
report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical_post_synth.rpt]
report_utilization -file [file join $report_dir utilization_post_synth.rpt]
report_timing_summary -delay_type max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_synth.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_post_synth.rpt]
check_timing -verbose \
    -file [file join $report_dir check_timing_post_synth.rpt]

set synth_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 -quiet]
set synth_wns_ns NA
if {[llength $synth_path] > 0} {
    set synth_wns_ns [get_property SLACK $synth_path]
}
set synth_hybrid_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ pe_hybrid_mac*}]]
set synth_dsp_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ DSP48*}]]

set synth_metrics [open [file join $report_dir metrics_post_synth.txt] w]
fconfigure $synth_metrics -translation lf
puts $synth_metrics "evidence=fresh_ooc_post_synthesis"
puts $synth_metrics "scope=production_v2_32_lane_hybrid_mac_array"
puts $synth_metrics "part=xc7z020clg400-1"
puts $synth_metrics "frequency_mhz=$frequency_mhz"
puts $synth_metrics "target_period_ns=$period_ns"
puts $synth_metrics "wns_ns=$synth_wns_ns"
puts $synth_metrics "hybrid_mac_instances=$synth_hybrid_count"
puts $synth_metrics "dsp48_primitives=$synth_dsp_count"
close $synth_metrics

opt_design
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
write_checkpoint -force [file join $build_dir post_route.dcp]

report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical_post_route.rpt]
report_utilization -file [file join $report_dir utilization_post_route.rpt]
report_route_status -file [file join $report_dir route_status_post_route.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_route.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_post_route.rpt]
report_timing -delay_type min -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_hold_post_route.rpt]
check_timing -verbose -file [file join $report_dir check_timing_post_route.rpt]
report_drc -file [file join $report_dir drc_post_route.rpt]

set utilization_text [report_utilization -return_string]
set slice_luts NA
set slice_registers NA
regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
    $utilization_text unused slice_luts
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
    $utilization_text unused slice_registers
set dsp_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ DSP48*}]]
set ramb18_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB18E1}]]
set ramb36_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB36E1}]]
set hybrid_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ pe_hybrid_mac*}]]

set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 -quiet]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1 -quiet]
set internal_hold_path [get_timing_paths -delay_type min \
    -from [all_registers] -to [all_registers] -max_paths 1 -nworst 1 -quiet]
set wns_ns NA
set all_path_whs_ns NA
set internal_whs_ns NA
set data_path_delay_ns NA
set startpoint NA
set endpoint NA
if {[llength $setup_path] > 0} {
    set wns_ns [get_property SLACK $setup_path]
    set data_path_delay_ns [get_property DATAPATH_DELAY $setup_path]
    set startpoint [get_property STARTPOINT_PIN $setup_path]
    set endpoint [get_property ENDPOINT_PIN $setup_path]
}
if {[llength $hold_path] > 0} {
    set all_path_whs_ns [get_property SLACK $hold_path]
}
if {[llength $internal_hold_path] > 0} {
    set internal_whs_ns [get_property SLACK $internal_hold_path]
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
set no_input_delay [regexp \
    {There are 0 input ports with no input delay} $timing_check_text]
set no_output_delay [regexp \
    {There are 0 ports with no output delay} $timing_check_text]
set no_drc_errors [expr {[llength [get_drc_violations -quiet \
    -filter {SEVERITY == Error}]] == 0}]
set resources_below_80 [expr {$slice_luts ne "NA" &&
    $slice_registers ne "NA" && $slice_luts < 42560 &&
    $slice_registers < 85120 && $dsp_count < 176 &&
    $ramb18_count == 0 && $ramb36_count == 0}]
set setup_met [expr {$wns_ns ne "NA" && $wns_ns >= 0.0}]
set internal_hold_met [expr {$internal_whs_ns ne "NA" &&
    $internal_whs_ns >= 0.0}]
set hierarchy_met [expr {$hybrid_count == 32 && $dsp_count == 32}]

set metrics [open [file join $report_dir metrics_post_route.txt] w]
fconfigure $metrics -translation lf
puts $metrics "evidence=fresh_ooc_post_route"
puts $metrics "scope=production_v2_32_lane_hybrid_mac_array"
puts $metrics "part=xc7z020clg400-1"
puts $metrics "frequency_mhz=$frequency_mhz"
puts $metrics "target_period_ns=$period_ns"
puts $metrics "wns_ns=$wns_ns"
puts $metrics "all_path_whs_ns=$all_path_whs_ns"
puts $metrics "internal_register_to_register_whs_ns=$internal_whs_ns"
puts $metrics "data_path_delay_ns=$data_path_delay_ns"
puts $metrics "critical_startpoint=$startpoint"
puts $metrics "critical_endpoint=$endpoint"
puts $metrics "slice_luts=$slice_luts"
puts $metrics "slice_registers=$slice_registers"
puts $metrics "dsp48_primitives=$dsp_count"
puts $metrics "ramb18_primitives=$ramb18_count"
puts $metrics "ramb36_primitives=$ramb36_count"
puts $metrics "hybrid_mac_instances=$hybrid_count"
puts $metrics "command_to_accumulate_latency_cycles=1"
puts $metrics "initiation_interval_cycles=1"
puts $metrics "routing_errors_zero=$route_error_free"
puts $metrics "unconstrained_internal_endpoints_zero=$no_unconstrained_internal"
puts $metrics "clockless_registers_zero=$no_clockless_registers"
puts $metrics "combinational_loops_zero=$no_timing_loops"
puts $metrics "input_delay_coverage_clean=$no_input_delay"
puts $metrics "output_delay_coverage_clean=$no_output_delay"
puts $metrics "drc_errors_zero=$no_drc_errors"
puts $metrics "resources_below_80_percent=$resources_below_80"
puts $metrics "bitstream=NOT_GENERATED_OOC_ONLY"
close $metrics

puts "PHASE5A_OOC_RESULT frequency_mhz=$frequency_mhz wns=$wns_ns internal_whs=$internal_whs_ns all_path_whs=$all_path_whs_ns LUT=$slice_luts FF=$slice_registers DSP=$dsp_count hybrid=$hybrid_count"
close_project

if {!$setup_met || !$internal_hold_met || !$route_error_free ||
    !$no_unconstrained_internal || !$no_clockless_registers ||
    !$no_timing_loops || !$no_input_delay || !$no_output_delay ||
    !$no_drc_errors || !$resources_below_80 || !$hierarchy_met} {
    puts stderr "PHASE5A_OOC_GATE_FAIL frequency_mhz=$frequency_mhz"
    exit 2
}
puts "PHASE5A_OOC_GATE_PASS frequency_mhz=$frequency_mhz"
exit 0
