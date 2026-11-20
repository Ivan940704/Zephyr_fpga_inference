# CP3 out-of-context implementation for the isolated sparse union planner.
# All inputs and durable reports are rooted below sparse_memory_v1/.

set script_dir [file dirname [file normalize [info script]]]
set sparse_root [file normalize [file join $script_dir ..]]
set build_dir [file join $sparse_root build cp3_planner_ooc]
set report_dir [file join $sparse_root reports cp3]

file mkdir $build_dir
file mkdir $report_dir
cd $build_dir

read_verilog -sv [file join $sparse_root rtl sparse_stage_map_v1.sv]
read_verilog -sv [file join $sparse_root rtl sparse_union_planner_v1.sv]
read_xdc [file join $sparse_root constraints sparse_union_planner_v1_100mhz.xdc]

synth_design -top sparse_union_planner_v1 \
    -part xc7z020clg400-1 -mode out_of_context
opt_design
place_design
route_design

report_utilization -file [file join $report_dir planner_utilization.rpt]
report_timing_summary -delay_type max -report_unconstrained \
    -check_timing_verbose -max_paths 10 \
    -file [file join $report_dir planner_timing_summary.rpt]
report_route_status -file [file join $report_dir planner_route_status.rpt]
write_checkpoint -force [file join $build_dir sparse_union_planner_v1_routed.dcp]

set timing_path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
if {[llength $timing_path] == 0} {
    error "CP3_GATE_FAIL: no maximum-delay timing path found"
}
set wns [get_property SLACK $timing_path]
set dsp_count [llength [get_cells -hier -filter {REF_NAME =~ DSP*}]]
set bram_count [llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]]
set unrouted_count [llength [get_nets -hier -filter {ROUTE_STATUS == UNROUTED}]]

set summary_path [file join $report_dir planner_ooc_summary.txt]
set summary_file [open $summary_path w]
puts $summary_file "checkpoint=CP3"
puts $summary_file "top=sparse_union_planner_v1"
puts $summary_file "part=xc7z020clg400-1"
puts $summary_file "clock_period_ns=10.000"
puts $summary_file "wns_ns=$wns"
puts $summary_file "bram_primitives=$bram_count"
puts $summary_file "dsp_primitives=$dsp_count"
puts $summary_file "unrouted_nets=$unrouted_count"
close $summary_file

# Vivado on Windows emits CRLF reports even when the destination is the WSL
# filesystem. Normalize durable evidence so repository checks stay portable.
proc normalize_report {path} {
    set input_file [open $path rb]
    set contents [read $input_file]
    close $input_file
    set contents [string map [list "\r\n" "\n" "\r" "\n"] $contents]
    regsub -all -line {[ \t]+$} $contents "" contents
    set contents "[string trimright $contents "\n"]\n"
    set output_file [open $path wb]
    puts -nonewline $output_file $contents
    close $output_file
}
foreach report_path [list \
    [file join $report_dir planner_utilization.rpt] \
    [file join $report_dir planner_timing_summary.rpt] \
    [file join $report_dir planner_route_status.rpt] \
    $summary_path] {
    normalize_report $report_path
}

puts "CP3_METRICS wns_ns=$wns bram=$bram_count dsp=$dsp_count unrouted=$unrouted_count"
if {$wns < 0.0} {
    error "CP3_GATE_FAIL: routed WNS is negative ($wns ns)"
}
if {$bram_count != 0 || $dsp_count != 0} {
    error "CP3_GATE_FAIL: planner inferred BRAM=$bram_count DSP=$dsp_count"
}
if {$unrouted_count != 0} {
    error "CP3_GATE_FAIL: $unrouted_count nets remain unrouted"
}
puts "CP3_GATE_PASS"
