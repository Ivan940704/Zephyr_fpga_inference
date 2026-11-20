if {$argc < 1} {
    error "Usage: synth_sequential_recurrent_context_store_ooc.tcl <rtl_root>"
}
set rtl_root [file normalize [lindex $argv 0]]
set part_name xc7z020clg400-1
set period_ns 10.000
set report_dir [file join $rtl_root reports sequential_recurrent_context_store]
set build_dir [file join $rtl_root build synth sequential_recurrent_context_store]
file mkdir $report_dir
file mkdir $build_dir

set rtl_file [file join $rtl_root memory sequential_recurrent_context_store.v]
set xdc_file [file join $rtl_root memory sequential_recurrent_context_store_100mhz.xdc]
create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
read_verilog $rtl_file
read_xdc $xdc_file
synth_design -top sequential_recurrent_context_store -part $part_name \
    -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force [file join $build_dir context_store_post_synth.dcp]
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
set ramb36_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB36E1}]]
set ramb18_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB18E1}]]
set lutram_count [llength [get_cells -hierarchical -filter {REF_NAME =~ RAM* && REF_NAME != RAMB36E1 && REF_NAME != RAMB18E1}]]
set srl_count [llength [get_cells -hierarchical -filter {REF_NAME =~ SRL*}]]
set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]]
set worst_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set wns_ns [get_property SLACK $worst_path]
set delay_ns [expr {$period_ns - $wns_ns}]
set timing_met [expr {$wns_ns >= 0.0 ? 1 : 0}]

set metrics [open [file join $report_dir metrics_post_synth.txt] w]
puts $metrics "top=sequential_recurrent_context_store"
puts $metrics "part=$part_name"
puts $metrics "target_period_ns=$period_ns"
puts $metrics "wns_ns=$wns_ns"
puts $metrics "estimated_critical_delay_ns=$delay_ns"
puts $metrics "timing_met=$timing_met"
puts $metrics "lut_primitives=$lut_count"
puts $metrics "ff_primitives=$ff_count"
puts $metrics "ramb36_primitives=$ramb36_count"
puts $metrics "ramb18_primitives=$ramb18_count"
puts $metrics "lutram_primitives=$lutram_count"
puts $metrics "srl_primitives=$srl_count"
puts $metrics "dsp48_primitives=$dsp_count"
close $metrics

puts "CONTEXT_STORE_OOC wns_ns=$wns_ns ramb36=$ramb36_count ramb18=$ramb18_count lutram=$lutram_count srl=$srl_count dsp=$dsp_count"
if {!$timing_met || $ramb36_count != 4 || $ramb18_count != 0 ||
    $lutram_count != 0 || $srl_count != 0 || $dsp_count != 0} {
    puts stderr "CONTEXT_STORE_OOC_GATE_FAIL"
    exit 2
}
puts "CONTEXT_STORE_OOC_PASS"
exit 0
