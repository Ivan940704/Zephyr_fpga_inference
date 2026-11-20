# Vivado 2018.3 OOC synthesis for the four-lane gate postprocess.
if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set pe_root [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
}

set rtl_file [file join $pe_root rtl postprocess pe_gate_postprocess.v]
set xdc_file [file join $pe_root constraints pe_gate_postprocess_200mhz.xdc]
set build_dir [file join $pe_root build synth pe_gate_postprocess]
set report_dir [file join $pe_root reports pe_gate_postprocess]

file delete -force $build_dir
file mkdir $build_dir
file mkdir $report_dir

create_project -in_memory -part xc7z020clg400-1
read_verilog $rtl_file
read_xdc $xdc_file
synth_design -top pe_gate_postprocess -part xc7z020clg400-1 \
    -mode out_of_context -flatten_hierarchy rebuilt

write_checkpoint -force [file join $build_dir pe_gate_postprocess_post_synth.dcp]
report_utilization -hierarchical \
    -file [file join $report_dir utilization_post_synth.rpt]
report_timing_summary -delay_type max -max_paths 10 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_synth.rpt]
report_timing -delay_type max -max_paths 10 -nworst 1 \
    -file [file join $report_dir timing_paths_post_synth.rpt]
check_timing -verbose -file [file join $report_dir check_timing_post_synth.rpt]

set timing_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set wns [get_property SLACK $timing_path]
set utilization_text [report_utilization -return_string]
if {![regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
      $utilization_text unused lut_count]} {
    error "Could not parse physical Slice LUT utilization"
}
set logical_lut_count \
    [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == LUT}]]
set ff_count [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]
set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]]
set ramb18_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB18E1}]]
set ramb36_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB36E1}]]
set lutram_count [llength [get_cells -hierarchical -filter \
    {REF_NAME =~ RAM32* || REF_NAME =~ RAM64* || REF_NAME =~ RAM128* || REF_NAME =~ RAM256*}]]
set forbidden_module_count [llength [get_cells -hierarchical -filter \
    {REF_NAME == pe_requant_lane || REF_NAME == pe_local_requant_bank_4lane || REF_NAME == pe_sigmoid_lut_255}]]

set out [open [file join $report_dir metrics_post_synth.txt] w]
puts $out "part=xc7z020clg400-1"
puts $out "target_period_ns=5.000"
puts $out "wns_ns=$wns"
puts $out "lut=$lut_count"
puts $out "logical_lut_primitives=$logical_lut_count"
puts $out "ff_primitives=$ff_count"
puts $out "dsp48_primitives=$dsp_count"
puts $out "ramb18e1_primitives=$ramb18_count"
puts $out "ramb36e1_primitives=$ramb36_count"
puts $out "lutram_primitives=$lutram_count"
puts $out "forbidden_module_instances=$forbidden_module_count"
puts $out "lanes=4"
puts $out "pending_packets=1"
puts $out "guard_shift=8"
puts $out "protocol_initiation_interval_cycles=2"
close $out

puts "PE_GATE_POSTPROCESS_OOC wns_ns=$wns lut=$lut_count ff=$ff_count dsp=$dsp_count ramb18=$ramb18_count ramb36=$ramb36_count lutram=$lutram_count forbidden_modules=$forbidden_module_count"

if {$dsp_count != 0} {
    error "pe_gate_postprocess expected zero DSP48 primitives, got $dsp_count"
}
if {$ramb18_count != 0 || $ramb36_count != 0 || $lutram_count != 0} {
    error "pe_gate_postprocess expected zero memory primitives"
}
if {$forbidden_module_count != 0} {
    error "pe_gate_postprocess contains a forbidden downstream module instance"
}
if {$wns < 0.0} {
    error "pe_gate_postprocess failed 5 ns timing: WNS=$wns"
}
close_project
