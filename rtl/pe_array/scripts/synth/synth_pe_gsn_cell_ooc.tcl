if {$argc >= 1} {set pe_root [file normalize [lindex $argv 0]]} else {set pe_root [file normalize [file join [file dirname [file normalize [info script]]] ../..]]}
set build [file join $pe_root build synth pe_gsn_cell];set reports [file join $pe_root reports pe_gsn_cell]
file delete -force $build;file mkdir $build;file mkdir $reports
create_project -in_memory -part xc7z020clg400-1
read_verilog -sv [file join $pe_root rtl arithmetic pe_requant_lane.sv]
read_verilog -sv [file join $pe_root rtl pe pe_hybrid_mac.sv]
read_verilog -sv [file join $pe_root rtl nonlinear pe_sigmoid_lut_255.sv]
read_verilog -sv [file join $pe_root rtl gsn pe_gsn_cell.sv]
read_xdc [file join $pe_root constraints pe_gsn_cell_200mhz.xdc]
synth_design -top pe_gsn_cell -part xc7z020clg400-1 -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force [file join $build pe_gsn_cell_post_synth.dcp]
report_utilization -hierarchical -file [file join $reports utilization_post_synth.rpt]
report_timing_summary -delay_type max -max_paths 10 -report_unconstrained -file [file join $reports timing_summary_post_synth.rpt]
check_timing -verbose -file [file join $reports check_timing_post_synth.rpt]
set path [get_timing_paths -delay_type max -max_paths 1 -nworst 1];set wns [get_property SLACK $path]
set lut [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == LUT}]]
set ff [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]
set dsp [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]]
set bram [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}]]
set f [open [file join $reports metrics_post_synth.txt] w]
puts $f "part=xc7z020clg400-1\ntarget_period_ns=5.000\nwns_ns=$wns\nlut_primitives=$lut\nff_primitives=$ff\ndsp48_primitives=$dsp\nbram_primitives=$bram";close $f
puts "PE_GSN_CELL_OOC wns_ns=$wns lut=$lut ff=$ff dsp=$dsp bram=$bram"
if {$dsp != 5} {error "expected 5 DSP, got $dsp"}
if {$wns < 0} {error "GSN cell failed 5 ns timing WNS=$wns"}
close_project
