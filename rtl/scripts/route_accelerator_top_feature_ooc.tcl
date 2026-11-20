if {$argc < 1} {
    error "Usage: route_accelerator_top_feature_ooc.tcl <rtl_root>"
}
set rtl_root [file normalize [lindex $argv 0]]
set part_name xc7z020clg400-1
set period_ns 10.000
set dcp_file [file join $rtl_root build synth accelerator_top_feature \
    accelerator_top_feature_post_synth.dcp]
set build_dir [file join $rtl_root build route accelerator_top_feature]
set report_dir [file join $rtl_root reports accelerator_top_sparse_timing]

if {![file isfile $dcp_file]} {
    error "Missing accelerator-top post-synthesis checkpoint: $dcp_file"
}
file delete -force $build_dir
file mkdir $build_dir
file mkdir $report_dir

open_checkpoint $dcp_file
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

set utilization_text [report_utilization -return_string]
set slice_luts NA
set slice_registers NA
regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
    $utilization_text unused slice_luts
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
    $utilization_text unused slice_registers
set ramb36_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB36E1}]]
set ramb18_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB18E1}]]
set dsp_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ DSP48*}]]

set timing_path [get_timing_paths -delay_type max -max_paths 1 \
    -nworst 1 -quiet]
set wns_ns NA
set data_path_delay_ns NA
set timing_met 0
if {[llength $timing_path] > 0} {
    set wns_ns [get_property SLACK $timing_path]
    set data_path_delay_ns [get_property DATAPATH_DELAY $timing_path]
    set timing_met [expr {$wns_ns >= 0.0 ? 1 : 0}]
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

set bram_equiv [expr {$ramb36_count + ($ramb18_count / 2.0)}]
set resources_below_80 [expr {$slice_luts ne "NA" &&
    $slice_registers ne "NA" && $slice_luts < 42560 &&
    $slice_registers < 85120 && $bram_equiv < 112.0 && $dsp_count < 176}]

set metrics [open [file join $report_dir metrics_post_route.txt] w]
fconfigure $metrics -translation lf
puts $metrics "evidence=ooc_post_route_only"
puts $metrics "top=accelerator_top"
puts $metrics "part=$part_name"
puts $metrics "target_period_ns=$period_ns"
puts $metrics "wns_ns=$wns_ns"
puts $metrics "data_path_delay_ns=$data_path_delay_ns"
puts $metrics "timing_met=$timing_met"
puts $metrics "whs_ns=$whs_ns"
puts $metrics "hold_met=$hold_met"
puts $metrics "slice_luts=$slice_luts"
puts $metrics "slice_registers=$slice_registers"
puts $metrics "ramb36_primitives=$ramb36_count"
puts $metrics "ramb18_primitives=$ramb18_count"
puts $metrics "dsp48_primitives=$dsp_count"
puts $metrics "resources_below_80_percent=$resources_below_80"
puts $metrics "routing_errors_zero=$route_error_free"
puts $metrics "unconstrained_internal_endpoints_zero=$no_unconstrained_internal"
puts $metrics "clockless_registers_zero=$no_clockless_registers"
puts $metrics "combinational_loops_zero=$no_timing_loops"
close $metrics

puts "ACCELERATOR_TOP_POST_ROUTE wns=$wns_ns whs=$whs_ns LUT=$slice_luts FF=$slice_registers RAMB36=$ramb36_count RAMB18=$ramb18_count DSP=$dsp_count"
close_design

if {!$timing_met || !$hold_met || !$resources_below_80 || !$route_error_free ||
    !$no_unconstrained_internal || !$no_clockless_registers ||
    !$no_timing_loops} {
    puts stderr "ACCELERATOR_TOP_ROUTE_GATE_FAIL"
    exit 2
}
puts "ACCELERATOR_TOP_ROUTE_PASS"
exit 0
