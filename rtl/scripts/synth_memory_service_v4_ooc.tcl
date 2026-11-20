# Vivado 2018.3 OOC synthesis for the sequential-v4 memory service.
# First argument is the staged rtl root.

if {$argc < 1} {
    error "Usage: synth_memory_service_v4_ooc.tcl <rtl_root>"
}

set rtl_root [file normalize [lindex $argv 0]]
set part_name xc7z020clg400-1
set period_ns 10.000
set report_dir [file join $rtl_root reports memory_service_v4]
set build_dir [file join $rtl_root build synth memory_service_v4]
file mkdir $report_dir
file mkdir $build_dir

set rtl_files [list \
    [file join $rtl_root memory memory.v] \
    [file join $rtl_root memory model_memory_v4_table.v] \
    [file join $rtl_root memory memory_service.v]]
set xdc_file [file join $rtl_root memory memory_service_v4_100mhz.xdc]
foreach required [concat $rtl_files [list $xdc_file]] {
    if {![file exists $required]} {
        error "Missing required file: $required"
    }
}

create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file
synth_design -top memory_service -part $part_name -mode out_of_context \
    -flatten_hierarchy rebuilt

write_checkpoint -force [file join $build_dir memory_service_post_synth.dcp]
report_utilization -hierarchical \
    -file [file join $report_dir utilization_post_synth.rpt]
report_timing_summary -delay_type max -max_paths 10 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_synth.rpt]
report_timing -delay_type max -max_paths 10 -sort_by group \
    -file [file join $report_dir timing_paths_post_synth.rpt]
check_timing -verbose \
    -file [file join $report_dir check_timing_post_synth.rpt]

set lut_count [llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]
set ff_count [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]
set ramb36_count [llength [get_cells -hierarchical \
    -filter {REF_NAME == RAMB36E1}]]
set ramb18_count [llength [get_cells -hierarchical \
    -filter {REF_NAME == RAMB18E1}]]
set dsp_count [llength [get_cells -hierarchical \
    -filter {REF_NAME =~ DSP48*}]]

set worst_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $worst_path] == 0} {
    set wns_ns NA
    set delay_ns NA
    set fmax_mhz NA
    set timing_met 0
} else {
    set wns_ns [get_property SLACK $worst_path]
    set delay_ns [expr {$period_ns - $wns_ns}]
    set fmax_mhz [expr {1000.0 / $delay_ns}]
    set timing_met [expr {$wns_ns >= 0.0 ? 1 : 0}]
}

set metrics [open [file join $report_dir metrics_post_synth.txt] w]
puts $metrics "top=memory_service"
puts $metrics "part=$part_name"
puts $metrics "target_period_ns=$period_ns"
puts $metrics "wns_ns=$wns_ns"
puts $metrics "estimated_critical_delay_ns=$delay_ns"
puts $metrics "estimated_fmax_mhz=$fmax_mhz"
puts $metrics "timing_met=$timing_met"
puts $metrics "lut_primitives=$lut_count"
puts $metrics "ff_primitives=$ff_count"
puts $metrics "ramb36_primitives=$ramb36_count"
puts $metrics "ramb18_primitives=$ramb18_count"
puts $metrics "dsp48_primitives=$dsp_count"
close $metrics

puts "MEMORY_SERVICE_V4_OOC wns_ns=$wns_ns"
puts "MEMORY_SERVICE_V4_OOC lut_primitives=$lut_count"
puts "MEMORY_SERVICE_V4_OOC ff_primitives=$ff_count"
puts "MEMORY_SERVICE_V4_OOC ramb36_primitives=$ramb36_count"
puts "MEMORY_SERVICE_V4_OOC ramb18_primitives=$ramb18_count"
puts "MEMORY_SERVICE_V4_OOC dsp48_primitives=$dsp_count"

if {!$timing_met} {
    puts stderr "MEMORY_SERVICE_V4_OOC_TIMING_FAIL"
    exit 2
}
if {$ramb36_count != 64} {
    puts stderr "MEMORY_SERVICE_V4_OOC_RAM_FAIL expected=64 actual=$ramb36_count"
    exit 3
}
puts "MEMORY_SERVICE_V4_OOC_PASS"
exit 0
