if {$argc >= 1} {
    set repo_root [file normalize [lindex $argv 0]]
} else {
    error "repo root argument is required"
}
set experiment [file join $repo_root rtl experiments latency_scaling]
set mac [file join $repo_root rtl pe_array baseline v1 rtl pe pe_hybrid_mac.sv]
set bank [file join $experiment pe_hybrid_mac_bank_32.v]
set xdc [file join $experiment constraints pe_hybrid_mac_bank_32_125mhz.xdc]
set build_dir [file join $repo_root rtl build latency_scaling_32pe_125mhz]
set report_dir [file join $repo_root rtl reports latency_scaling_32pe_125mhz]
foreach required [list $mac $bank $xdc] {
    if {![file isfile $required]} {
        error "Missing 32-PE implementation input: $required"
    }
}
file delete -force $build_dir
file delete -force $report_dir
file mkdir $build_dir
file mkdir $report_dir

create_project -in_memory -part xc7z020clg400-1
read_verilog -sv $mac
read_verilog $bank
read_xdc $xdc
synth_design -top pe_hybrid_mac_bank_32 -part xc7z020clg400-1 \
    -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force [file join $build_dir post_synth.dcp]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $build_dir post_route.dcp]

report_utilization -hierarchical -file [file join $report_dir utilization_hierarchical.rpt]
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
set internal_hold_path [get_timing_paths -delay_type min -from [all_registers] -to [all_registers] -max_paths 1 -nworst 1 -quiet]
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
regexp {There are ([0-9]+) input ports with no input delay} $check_text unused no_input_delay
regexp {There are ([0-9]+) ports with no output delay} $check_text unused no_output_delay
set boundary_hold_closed "NO"
if {$whs ne "NA" && $whs >= 0.0} {
    set boundary_hold_closed "YES"
}

set metrics [open [file join $report_dir metrics.txt] w]
puts $metrics "evidence=Vivado_2018.3_OOC_place_and_route"
puts $metrics "scope=feasibility_only_32_lane_hybrid_mac_bank"
puts $metrics "production_16pe_datapath_modified=NO"
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
puts $metrics "ooc_boundary_hold_closed=$boundary_hold_closed"
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
if {$dsp_count != 32 || $ramb18_count != 0 || $ramb36_count != 0} {
    puts stderr "RESOURCE ERROR: DSP=$dsp_count RAMB18=$ramb18_count RAMB36=$ramb36_count"
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
    error "32-lane 125 MHz feasibility checkpoint failed"
}
if {$whs < 0.0} {
    puts "LATENCY_32PE_OOC_BOUNDARY_HOLD_OPEN whs_ns=$whs"
}
puts "LATENCY_32PE_125MHZ_CORE_FEASIBILITY_PASS wns_ns=$wns internal_whs_ns=$internal_whs lut=$lut_count ff=$ff_count dsp=$dsp_count"
close_project
exit
