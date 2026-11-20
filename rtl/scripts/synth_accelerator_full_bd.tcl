# Synthesize the validated full PYNQ-Z1 block design, then stop before
# opt_design/place_design/route_design.  No bitstream or hardware handoff is
# requested by this script.

if {$argc >= 1} {
    set rtl_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set rtl_root [file normalize [file join $script_dir ..]]
}

set project_dir [file join [file dirname $rtl_root] zephyr_full_bd]
set project_file [file join $project_dir zephyr_full.xpr]
set report_dir [file join $rtl_root reports accelerator_full_bd_preimplementation]
set checkpoint_dir [file join $project_dir checkpoints]
file mkdir $report_dir
file mkdir $checkpoint_dir

if {![file exists $project_file]} {
    error "Validated full-design project is missing: $project_file"
}

open_project $project_file
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "Full-design synthesis did not complete: $synth_status"
}

open_run synth_1

write_checkpoint -force [file join $checkpoint_dir zephyr_full_post_synth.dcp]
report_utilization -hierarchical \
    -file [file join $report_dir utilization_post_synth.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -report_unconstrained \
    -file [file join $report_dir timing_summary_post_synth.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_setup_post_synth.rpt]
report_timing -delay_type min -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_hold_post_synth.rpt]
check_timing -verbose \
    -file [file join $report_dir check_timing_post_synth.rpt]
report_clock_utilization \
    -file [file join $report_dir clock_utilization_post_synth.rpt]
report_drc \
    -file [file join $report_dir drc_post_synth.rpt]
report_methodology \
    -file [file join $report_dir methodology_post_synth.rpt]
if {[catch {
    report_cdc -details \
        -file [file join $report_dir cdc_post_synth.rpt]
} cdc_reason]} {
    set cdc_file [open [file join $report_dir cdc_post_synth.rpt] w]
    fconfigure $cdc_file -translation lf
    puts $cdc_file "report_cdc_status=NO_REPORT"
    puts $cdc_file "reason=$cdc_reason"
    close $cdc_file
}

set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
if {[llength $setup_path] == 0} {
    error "No timed setup path found after full-design synthesis"
}
set setup_wns [get_property SLACK $setup_path]
if {[llength $hold_path] == 0} {
    set hold_whs UNAVAILABLE
} else {
    set hold_whs [get_property SLACK $hold_path]
}

set utilization_text [report_utilization -hierarchical -return_string]
set utilization_pattern {\|\s*zephyr_full_wrapper\s*\|\s*\(top\)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9.]+)\s*\|\s*([0-9.]+)\s*\|\s*([0-9]+)\s*\|}
set utilization_parsed 0
set total_luts UNAVAILABLE
set logic_luts UNAVAILABLE
set lutrams UNAVAILABLE
set srls UNAVAILABLE
set total_ffs UNAVAILABLE
set ramb36 UNAVAILABLE
set ramb18 UNAVAILABLE
set total_dsps UNAVAILABLE
if {[regexp $utilization_pattern $utilization_text unused \
        total_luts logic_luts lutrams srls total_ffs ramb36 ramb18 total_dsps]} {
    set utilization_parsed 1
}
if {!$utilization_parsed} {
    error "Could not parse the synthesized top-level utilization row"
}

# XC7Z020 resource budgets.  The 32-PE image-v5 architecture intentionally
# consumes more than 80 percent of LUTs.  Allow implementation to proceed only
# while every resource remains below 90 percent; post-route timing, routing,
# DRC, and the same resource ceiling remain fail-closed release gates.
set utilization_limit_percent 90.0
set lut_used_percent [format %.2f [expr {100.0 * $total_luts / 53200.0}]]
set ff_used_percent [format %.2f [expr {100.0 * $total_ffs / 106400.0}]]
set bram36_equivalent [expr {$ramb36 + ($ramb18 / 2.0)}]
set bram_used_percent [format %.2f [expr {100.0 * $bram36_equivalent / 140.0}]]
set dsp_used_percent [format %.2f [expr {100.0 * $total_dsps / 220.0}]]
set utilization_gate_pass [expr {
    $lut_used_percent < $utilization_limit_percent &&
    $ff_used_percent < $utilization_limit_percent &&
    $bram_used_percent < $utilization_limit_percent &&
    $dsp_used_percent < $utilization_limit_percent
}]
if {!$utilization_gate_pass} {
    error "Full-design utilization exceeds the ${utilization_limit_percent} percent pre-implementation gate"
}

set impl_status [get_property STATUS [get_runs impl_1]]
set metrics [open [file join $report_dir synthesis_metrics.txt] w]
fconfigure $metrics -translation lf
puts $metrics "evidence=full_block_design_post_synthesis_only"
puts $metrics "vivado_version=[version -short]"
puts $metrics "part=xc7z020clg400-1"
puts $metrics "target_clock_mhz=100"
puts $metrics "synth_status=$synth_status"
puts $metrics "synthesis_checkpoint_mode=global"
puts $metrics "setup_wns_ns=$setup_wns"
puts $metrics "hold_whs_ns=$hold_whs"
puts $metrics "utilization_parsed=$utilization_parsed"
puts $metrics "total_luts=$total_luts"
puts $metrics "logic_luts=$logic_luts"
puts $metrics "lutram_luts=$lutrams"
puts $metrics "srl_luts=$srls"
puts $metrics "total_ffs=$total_ffs"
puts $metrics "ramb36=$ramb36"
puts $metrics "ramb18=$ramb18"
puts $metrics "total_dsps=$total_dsps"
puts $metrics "lut_used_percent=$lut_used_percent"
puts $metrics "ff_used_percent=$ff_used_percent"
puts $metrics "bram36_equivalent=$bram36_equivalent"
puts $metrics "bram_used_percent=$bram_used_percent"
puts $metrics "dsp_used_percent=$dsp_used_percent"
puts $metrics "utilization_limit_percent=$utilization_limit_percent"
puts $metrics "utilization_gate_pass=$utilization_gate_pass"
puts $metrics "implementation_status=$impl_status"
puts $metrics "opt_design=NOT_RUN"
puts $metrics "place_design=NOT_RUN"
puts $metrics "route_design=NOT_RUN"
puts $metrics "bitstream=NOT_GENERATED"
close $metrics

puts "ACCELERATOR_FULL_SYNTH_METRIC setup_wns_ns=$setup_wns"
puts "ACCELERATOR_FULL_SYNTH_METRIC hold_whs_ns=$hold_whs"
puts "ACCELERATOR_FULL_SYNTH_METRIC total_luts=$total_luts"
puts "ACCELERATOR_FULL_SYNTH_METRIC total_ffs=$total_ffs"
puts "ACCELERATOR_FULL_SYNTH_METRIC ramb36=$ramb36"
puts "ACCELERATOR_FULL_SYNTH_METRIC ramb18=$ramb18"
puts "ACCELERATOR_FULL_SYNTH_METRIC total_dsps=$total_dsps"
puts "ACCELERATOR_FULL_SYNTH_IMPLEMENTATION_STATUS $impl_status"

close_project
puts "ACCELERATOR_FULL_SYNTH_PASS"
puts "ACCELERATOR_FULL_IMPLEMENTATION_NOT_RUN"
exit 0
