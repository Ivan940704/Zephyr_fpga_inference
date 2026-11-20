# Vivado 2018.3 out-of-context synthesis for pe_requant_lane.
# Optional first tclarg: absolute path to rtl/pe_array.

if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set pe_root [file normalize [file join $script_dir ../..]]
}

set rtl_file   [file join $pe_root rtl arithmetic pe_requant_lane.sv]
set xdc_file   [file join $pe_root constraints pe_requant_lane_200mhz.xdc]
set build_dir  [file join $pe_root build synth pe_requant_lane]
set report_dir [file join $pe_root reports pe_requant_lane]

foreach required [list $rtl_file $xdc_file] {
    if {![file exists $required]} {
        error "Missing required file: $required"
    }
}

file delete -force $build_dir
file mkdir $build_dir
file mkdir $report_dir

create_project -in_memory -part xc7z020clg400-1
set_property target_language Verilog [current_project]
read_verilog -sv $rtl_file
read_xdc $xdc_file
synth_design -top pe_requant_lane -part xc7z020clg400-1 -mode out_of_context -flatten_hierarchy rebuilt

write_checkpoint -force [file join $build_dir pe_requant_lane_post_synth.dcp]
report_utilization -hierarchical -file [file join $report_dir utilization_post_synth.rpt]
report_timing_summary -delay_type max -max_paths 10 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_synth.rpt]
report_timing -delay_type max -max_paths 10 -sort_by group \
    -file [file join $report_dir timing_paths_post_synth.rpt]
check_timing -verbose -file [file join $report_dir check_timing_post_synth.rpt]

set utilization_text [report_utilization -hierarchical -return_string]
set utilization_pattern {\|\s+pe_requant_lane\s+\|\s+\(top\)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|\s+([0-9]+)\s+\|}
if {![regexp $utilization_pattern $utilization_text unused \
        total_luts logic_luts lutrams srls total_ffs ramb36 ramb18 total_dsps]} {
    error "Could not parse top-level utilization row"
}

set worst_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $worst_path] == 0} {
    error "No timed path was found after synthesis"
}

set period_ns 5.000
set wns_ns [get_property SLACK $worst_path]
set estimated_delay_ns [expr {$period_ns - $wns_ns}]
set estimated_fmax_mhz [expr {1000.0 / $estimated_delay_ns}]
set lut_count [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == LUT}]]
set ff_count [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]
set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]]
set timing_met [expr {$wns_ns >= 0.0 ? 1 : 0}]

set metrics_file [open [file join $report_dir metrics_post_synth.txt] w]
puts $metrics_file "part=xc7z020clg400-1"
puts $metrics_file "target_period_ns=$period_ns"
puts $metrics_file "wns_ns=$wns_ns"
puts $metrics_file "estimated_critical_delay_ns=$estimated_delay_ns"
puts $metrics_file "estimated_fmax_mhz=$estimated_fmax_mhz"
puts $metrics_file "timing_met=$timing_met"
puts $metrics_file "total_luts=$total_luts"
puts $metrics_file "logic_luts=$logic_luts"
puts $metrics_file "srl_luts=$srls"
puts $metrics_file "total_ffs=$total_ffs"
puts $metrics_file "total_dsps=$total_dsps"
puts $metrics_file "lut_primitives=$lut_count"
puts $metrics_file "ff_primitives=$ff_count"
puts $metrics_file "dsp48_primitives=$dsp_count"
puts $metrics_file "pipeline_latency_cycles=9"
puts $metrics_file "initiation_interval_cycles=1"
close $metrics_file

puts "PE_REQUANT_METRIC part=xc7z020clg400-1"
puts "PE_REQUANT_METRIC target_period_ns=$period_ns"
puts "PE_REQUANT_METRIC wns_ns=$wns_ns"
puts "PE_REQUANT_METRIC estimated_fmax_mhz=$estimated_fmax_mhz"
puts "PE_REQUANT_METRIC timing_met=$timing_met"
puts "PE_REQUANT_METRIC total_luts=$total_luts"
puts "PE_REQUANT_METRIC logic_luts=$logic_luts"
puts "PE_REQUANT_METRIC srl_luts=$srls"
puts "PE_REQUANT_METRIC total_ffs=$total_ffs"
puts "PE_REQUANT_METRIC total_dsps=$total_dsps"
puts "PE_REQUANT_METRIC lut_primitives=$lut_count"
puts "PE_REQUANT_METRIC ff_primitives=$ff_count"
puts "PE_REQUANT_METRIC dsp48_primitives=$dsp_count"
puts "PE_REQUANT_METRIC pipeline_latency_cycles=9"
puts "PE_REQUANT_METRIC initiation_interval_cycles=1"

close_project

if {!$timing_met} {
    error "pe_requant_lane failed the 5 ns timing target: WNS=$wns_ns ns"
}
