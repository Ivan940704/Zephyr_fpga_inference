# Vivado 2018.3 out-of-context synthesis for production-v1 memory blocks.
# Optional first tclarg: absolute path to the staged rtl directory.

if {$argc >= 1} {
    set rtl_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set rtl_root [file normalize [file join $script_dir ..]]
}

set part_name xc7z020clg400-1
set period_ns 10.000
set xdc_file [file join $rtl_root memory memory_v1_100mhz.xdc]
set report_root [file join $rtl_root reports memory_v1]
set build_root [file join $rtl_root build synth memory_v1]

proc run_memory_ooc {rtl_root part_name period_ns xdc_file report_root \
                     build_root top_name rtl_files} {
    set report_dir [file join $report_root $top_name]
    set build_dir [file join $build_root $top_name]
    file delete -force $build_dir
    file mkdir $build_dir
    file mkdir $report_dir

    foreach required [concat $rtl_files [list $xdc_file]] {
        if {![file exists $required]} {
            error "Missing required file: $required"
        }
    }

    create_project -in_memory -part $part_name
    set_property target_language Verilog [current_project]
    # Vivado 2018.3 does not yet support read_verilog -include_dirs.  The
    # Windows runner invokes Vivado from rtl_root, so repository-qualified
    # `include paths resolve against the current working directory.
    read_verilog -sv $rtl_files
    read_xdc $xdc_file
    synth_design -top $top_name -part $part_name -mode out_of_context \
        -flatten_hierarchy rebuilt

    write_checkpoint -force [file join $build_dir ${top_name}_post_synth.dcp]
    report_utilization -hierarchical \
        -file [file join $report_dir utilization_post_synth.rpt]
    report_timing_summary -delay_type max -max_paths 10 \
        -report_unconstrained \
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
        set estimated_delay_ns NA
        set estimated_fmax_mhz NA
        set timing_met 0
    } else {
        set wns_ns [get_property SLACK $worst_path]
        set estimated_delay_ns [expr {$period_ns - $wns_ns}]
        set estimated_fmax_mhz [expr {1000.0 / $estimated_delay_ns}]
        set timing_met [expr {$wns_ns >= 0.0 ? 1 : 0}]
    }

    set metrics_file [open [file join $report_dir metrics_post_synth.txt] w]
    puts $metrics_file "top=$top_name"
    puts $metrics_file "part=$part_name"
    puts $metrics_file "target_period_ns=$period_ns"
    puts $metrics_file "wns_ns=$wns_ns"
    puts $metrics_file "estimated_critical_delay_ns=$estimated_delay_ns"
    puts $metrics_file "estimated_fmax_mhz=$estimated_fmax_mhz"
    puts $metrics_file "timing_met=$timing_met"
    puts $metrics_file "lut_primitives=$lut_count"
    puts $metrics_file "ff_primitives=$ff_count"
    puts $metrics_file "ramb36_primitives=$ramb36_count"
    puts $metrics_file "ramb18_primitives=$ramb18_count"
    puts $metrics_file "dsp48_primitives=$dsp_count"
    close $metrics_file

    puts "MEMORY_V1_OOC top=$top_name"
    puts "MEMORY_V1_OOC target_period_ns=$period_ns"
    puts "MEMORY_V1_OOC wns_ns=$wns_ns"
    puts "MEMORY_V1_OOC estimated_fmax_mhz=$estimated_fmax_mhz"
    puts "MEMORY_V1_OOC timing_met=$timing_met"
    puts "MEMORY_V1_OOC lut_primitives=$lut_count"
    puts "MEMORY_V1_OOC ff_primitives=$ff_count"
    puts "MEMORY_V1_OOC ramb36_primitives=$ramb36_count"
    puts "MEMORY_V1_OOC ramb18_primitives=$ramb18_count"
    puts "MEMORY_V1_OOC dsp48_primitives=$dsp_count"

    close_project
    return $timing_met
}

if {[catch {
    file mkdir $report_root
    file mkdir $build_root

    set service_timing_met [run_memory_ooc \
        $rtl_root $part_name $period_ns $xdc_file $report_root \
        $build_root memory_service [list \
            [file join $rtl_root memory memory.v] \
            [file join $rtl_root memory model_memory_v4_table.v] \
            [file join $rtl_root memory memory_service.v]]]

    set mailbox_timing_met [run_memory_ooc \
        $rtl_root $part_name $period_ns $xdc_file $report_root \
        $build_root layernorm_mailbox [list \
            [file join $rtl_root memory layernorm_mailbox.v]]]
} failure_reason]} {
    puts stderr "MEMORY_V1_OOC_FATAL $failure_reason"
    exit 1
}

puts "MEMORY_V1_OOC_ALL_COMPLETED"
if {$service_timing_met && $mailbox_timing_met} {
    puts "MEMORY_V1_OOC_ALL_TIMING_PASS"
    exit 0
}
puts stderr "MEMORY_V1_OOC_ALL_TIMING_FAIL"
exit 2
