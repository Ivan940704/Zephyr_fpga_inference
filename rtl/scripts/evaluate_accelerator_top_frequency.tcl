if {$argc < 2} {
    error "Usage: evaluate_accelerator_top_frequency.tcl <routed_dcp> <output_tsv>"
}

set routed_dcp [file normalize [lindex $argv 0]]
set output_tsv [file normalize [lindex $argv 1]]
if {![file isfile $routed_dcp]} {
    error "Missing routed checkpoint: $routed_dcp"
}

open_checkpoint $routed_dcp
set clk_port [get_ports clk]
set output [open $output_tsv w]
fconfigure $output -translation lf
puts $output "evidence\tpost_route_checkpoint_period_sensitivity_only"
puts $output "frequency_mhz\tperiod_ns\twns_ns\tdata_path_delay_ns\tsource\tdestination"

foreach candidate {
    {100 10.000000}
    {102 9.803922}
    {103 9.708738}
    {104 9.615385}
    {105 9.523810}
    {111.111 9.000009}
    {125 8.000000}
} {
    lassign $candidate frequency_mhz period_ns
    reset_timing
    create_clock -period $period_ns -name clk $clk_port
    set path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
    set wns_ns [get_property SLACK $path]
    set data_path_delay_ns [get_property DATAPATH_DELAY $path]
    set source [get_property STARTPOINT_PIN $path]
    set destination [get_property ENDPOINT_PIN $path]
    puts $output "$frequency_mhz\t$period_ns\t$wns_ns\t$data_path_delay_ns\t$source\t$destination"
}

close $output
close_design
puts "ACCELERATOR_TOP_FREQUENCY_SENSITIVITY_COMPLETE output=$output_tsv"
