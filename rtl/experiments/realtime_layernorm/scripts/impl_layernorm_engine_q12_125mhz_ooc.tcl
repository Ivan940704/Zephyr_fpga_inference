if {$argc >= 1} {
    set repo_root [file normalize [lindex $argv 0]]
} else {
    error "repo root argument is required"
}
set experiment [file join $repo_root rtl experiments realtime_layernorm]
set engine [file join $experiment layernorm_engine_q12.v]
set xdc [file join $experiment constraints layernorm_engine_q12_125mhz.xdc]
set build_dir [file join $repo_root rtl build realtime_layernorm_q12_125mhz]
set report_dir [file join $repo_root rtl reports realtime_layernorm_q12_125mhz]
foreach required [list $engine $xdc] {
    if {![file isfile $required]} {
        error "Missing LayerNorm implementation input: $required"
    }
}
file delete -force $build_dir
file delete -force $report_dir
file mkdir $build_dir
file mkdir $report_dir

create_project -in_memory -part xc7z020clg400-1
read_verilog $engine
read_xdc $xdc
synth_design -top layernorm_engine_q12 -part xc7z020clg400-1 \
    -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force [file join $build_dir post_synth.dcp]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $build_dir post_route.dcp]

report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
set check_timing_path [file join $report_dir check_timing.rpt]
check_timing -verbose -file $check_timing_path
set check_handle [open $check_timing_path r]
set check_text [read $check_handle]
close $check_handle

set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 -quiet]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1 -quiet]
set internal_hold_path [get_timing_paths -delay_type min \
    -from [all_registers] -to [all_registers] -max_paths 1 -nworst 1 -quiet]
set wns "NA"
set whs "NA"
set internal_whs "NA"
set data_path_delay "NA"
set startpoint "NA"
set endpoint "NA"
if {[llength $setup_path] > 0} {
    set wns [get_property SLACK $setup_path]
    set data_path_delay [get_property DATAPATH_DELAY $setup_path]
    set startpoint [get_property STARTPOINT_PIN $setup_path]
    set endpoint [get_property ENDPOINT_PIN $setup_path]
}
if {[llength $hold_path] > 0} {
    set whs [get_property SLACK $hold_path]
}
if {[llength $internal_hold_path] > 0} {
    set internal_whs [get_property SLACK $internal_hold_path]
}
set route_handle [open [file join $report_dir route_status.rpt] r]
set route_text [read $route_handle]
close $route_handle
set route_error_nets "NA"
regexp {# of nets with routing errors\.*\s*:\s*([0-9]+)\s*:} \
    $route_text unused route_error_nets
set utilization_text [report_utilization -return_string]
set lut_count "NA"
regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
    $utilization_text unused lut_count
set ff_count [llength [get_cells -hierarchical -quiet -filter {REF_NAME =~ FD*}]]
set dsp_count [llength [get_cells -hierarchical -quiet -filter {REF_NAME =~ DSP48*}]]
set ramb18_count [llength [get_cells -hierarchical -quiet -filter {REF_NAME == RAMB18E1}]]
set ramb36_count [llength [get_cells -hierarchical -quiet -filter {REF_NAME == RAMB36E1}]]
set actual_period [get_property PERIOD [get_clocks clk]]
set no_input_delay "NA"
set no_output_delay "NA"
regexp {There are ([0-9]+) input ports with no input delay} \
    $check_text unused no_input_delay
regexp {There are ([0-9]+) ports with no output delay} \
    $check_text unused no_output_delay

set metrics [open [file join $report_dir metrics.txt] w]
puts $metrics "evidence=Vivado_2018.3_OOC_place_and_route"
puts $metrics "scope=experimental_shared_layernorm_leaf_not_full_system"
puts $metrics "numeric_contract=signed_Q12_variance_Q24_reciprocal_Q20"
puts $metrics "part=xc7z020clg400-1"
puts $metrics "target_frequency_mhz=125"
puts $metrics "target_period_ns=8.000"
puts $metrics "clock_uncertainty_ns=0.250"
puts $metrics "io_delay_ns=0.250"
puts $metrics "actual_clock_period_ns=$actual_period"
puts $metrics "implementation_run=OOC_PLACE_AND_ROUTE"
puts $metrics "bitstream=NOT_GENERATED"
puts $metrics "wns_ns=$wns"
puts $metrics "all_path_whs_ns=$whs"
puts $metrics "internal_register_to_register_whs_ns=$internal_whs"
puts $metrics "worst_data_path_delay_ns=$data_path_delay"
puts $metrics "critical_startpoint=$startpoint"
puts $metrics "critical_endpoint=$endpoint"
puts $metrics "route_error_nets=$route_error_nets"
puts $metrics "lut=$lut_count"
puts $metrics "ff_primitives=$ff_count"
puts $metrics "dsp48_primitives=$dsp_count"
puts $metrics "ramb18e1_primitives=$ramb18_count"
puts $metrics "ramb36e1_primitives=$ramb36_count"
puts $metrics "input_ports_without_delay=$no_input_delay"
puts $metrics "output_ports_without_delay=$no_output_delay"
close $metrics

set failed 0
if {$wns eq "NA" || $wns < 0.0} {
    puts stderr "TIMING ERROR: 125 MHz post-route WNS=$wns"
    set failed 1
}
if {$internal_whs eq "NA" || $internal_whs < 0.0} {
    puts stderr "INTERNAL HOLD ERROR: register-to-register WHS=$internal_whs"
    set failed 1
}
if {$route_error_nets eq "NA" || $route_error_nets != 0} {
    puts stderr "ROUTE ERROR: routed-net error count=$route_error_nets"
    set failed 1
}
if {[expr {abs($actual_period - 8.000)}] > 0.001} {
    puts stderr "CLOCK ERROR: period=$actual_period"
    set failed 1
}
if {$no_input_delay ne "0" || $no_output_delay ne "0"} {
    puts stderr "TIMING COVERAGE ERROR: no_input_delay=$no_input_delay no_output_delay=$no_output_delay"
    set failed 1
}
if {$failed} {
    error "LayerNorm Q12 125 MHz OOC checkpoint failed"
}
puts "LAYER_NORM_Q12_125MHZ_OOC_PASS wns_ns=$wns internal_whs_ns=$internal_whs lut=$lut_count ff=$ff_count dsp=$dsp_count bram18=$ramb18_count bram36=$ramb36_count"
close_project
exit
