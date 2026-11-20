# Vivado 2018.3 OOC synthesis for one Hybrid MAC PE.
if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set pe_root [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
}
set rtl_file [file join $pe_root rtl pe pe_hybrid_mac.sv]
set xdc_file [file join $pe_root constraints pe_hybrid_mac_200mhz.xdc]
set build_dir [file join $pe_root build synth pe_hybrid_mac]
set report_dir [file join $pe_root reports pe_hybrid_mac]
file delete -force $build_dir
file mkdir $build_dir
file mkdir $report_dir
create_project -in_memory -part xc7z020clg400-1
read_verilog -sv $rtl_file
read_xdc $xdc_file
synth_design -top pe_hybrid_mac -part xc7z020clg400-1 -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force [file join $build_dir pe_hybrid_mac_post_synth.dcp]
report_utilization -hierarchical -file [file join $report_dir utilization_post_synth.rpt]
report_timing_summary -delay_type max -max_paths 10 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_synth.rpt]
check_timing -verbose -file [file join $report_dir check_timing_post_synth.rpt]
set util [report_utilization -hierarchical -return_string]
set timing_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set wns [get_property SLACK $timing_path]
set lut_count [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == LUT}]]
set ff_count [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]
set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]]
set out [open [file join $report_dir metrics_post_synth.txt] w]
puts $out "part=xc7z020clg400-1"
puts $out "target_period_ns=5.000"
puts $out "wns_ns=$wns"
puts $out "lut_primitives=$lut_count"
puts $out "ff_primitives=$ff_count"
puts $out "dsp48_primitives=$dsp_count"
close $out
puts "PE_HYBRID_OOC wns_ns=$wns lut=$lut_count ff=$ff_count dsp=$dsp_count"
if {$dsp_count != 1} { error "pe_hybrid_mac expected exactly one DSP, got $dsp_count" }
if {$wns < 0.0} { error "pe_hybrid_mac failed 5 ns timing: WNS=$wns" }
close_project
