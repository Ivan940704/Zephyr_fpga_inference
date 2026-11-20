# Synthesise the complete AXI-Lite wrapper + memory service + 256 KiB cache.
# This script intentionally stops after synth_design: no opt/place/route or bitstream.

if {$argc >= 1} {
    set rtl_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set rtl_root [file normalize [file join $script_dir ..]]
}

set part_name xc7z020clg400-1
set top_name parameter_bram_bringup_top
set period_ns 10.000
set report_dir [file join $rtl_root reports parameter_bram_bringup synthesis]
set build_dir [file join $rtl_root build synth parameter_bram_bringup]
file delete -force $build_dir
file mkdir $build_dir
file mkdir $report_dir

set rtl_files [list \
    [file join $rtl_root memory memory.v] \
    [file join $rtl_root memory model_memory_v3_table.v] \
    [file join $rtl_root memory memory_service.v] \
    [file join $rtl_root memory memory_service_axil.v] \
    [file join $rtl_root memory parameter_bram_bringup_top.v]]
set xdc_file [file join $rtl_root memory parameter_bram_bringup_100mhz.xdc]

foreach required [concat $rtl_files [list $xdc_file]] {
    if {![file exists $required]} {
        error "Missing required file: $required"
    }
}

if {[catch {
    create_project -in_memory -part $part_name
    set_property target_language Verilog [current_project]
    read_verilog -sv $rtl_files
    read_xdc $xdc_file
    synth_design -top $top_name -part $part_name -mode out_of_context \
        -flatten_hierarchy rebuilt

    write_checkpoint -force [file join $build_dir ${top_name}_post_synth.dcp]
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
    set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]]
    set worst_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
    if {[llength $worst_path] == 0} {
        set wns_ns NA
        set critical_delay_ns NA
        set estimated_fmax_mhz NA
        set timing_met 0
    } else {
        set wns_ns [get_property SLACK $worst_path]
        set critical_delay_ns [expr {$period_ns - $wns_ns}]
        set estimated_fmax_mhz [expr {1000.0 / $critical_delay_ns}]
        set timing_met [expr {$wns_ns >= 0.0 ? 1 : 0}]
    }

    set metrics [open [file join $report_dir metrics_post_synth.txt] w]
    puts $metrics "evidence=post_synthesis_ooc"
    puts $metrics "top=$top_name"
    puts $metrics "part=$part_name"
    puts $metrics "target_period_ns=$period_ns"
    puts $metrics "wns_ns=$wns_ns"
    puts $metrics "estimated_critical_delay_ns=$critical_delay_ns"
    puts $metrics "estimated_fmax_mhz=$estimated_fmax_mhz"
    puts $metrics "timing_met=$timing_met"
    puts $metrics "lut_primitives=$lut_count"
    puts $metrics "ff_primitives=$ff_count"
    puts $metrics "ramb36_primitives=$ramb36_count"
    puts $metrics "ramb18_primitives=$ramb18_count"
    puts $metrics "dsp48_primitives=$dsp_count"
    puts $metrics "implementation_run=NOT_RUN"
    puts $metrics "bitstream=NOT_GENERATED"
    close $metrics

    puts "PARAMETER_BRAM_SYNTH top=$top_name"
    puts "PARAMETER_BRAM_SYNTH wns_ns=$wns_ns"
    puts "PARAMETER_BRAM_SYNTH estimated_fmax_mhz=$estimated_fmax_mhz"
    puts "PARAMETER_BRAM_SYNTH timing_met=$timing_met"
    puts "PARAMETER_BRAM_SYNTH lut_primitives=$lut_count ff_primitives=$ff_count"
    puts "PARAMETER_BRAM_SYNTH ramb36_primitives=$ramb36_count ramb18_primitives=$ramb18_count dsp48_primitives=$dsp_count"
    puts "PARAMETER_BRAM_SYNTH_IMPLEMENTATION_NOT_RUN"
    close_project
} reason]} {
    puts stderr "PARAMETER_BRAM_SYNTH_FATAL $reason"
    catch {close_project}
    exit 1
}

puts "PARAMETER_BRAM_SYNTH_COMPLETED"
if {$timing_met} {
    puts "PARAMETER_BRAM_SYNTH_TIMING_PASS"
    exit 0
}
puts stderr "PARAMETER_BRAM_SYNTH_TIMING_FAIL"
exit 2
