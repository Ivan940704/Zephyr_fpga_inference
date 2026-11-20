if {$argc >= 3} {
    set repo_root [file normalize [lindex $argv 0]]
    set target_period [lindex $argv 1]
    set target_label [lindex $argv 2]
} else {
    error "repo root, target period, and target label arguments are required"
}
set experiment [file join $repo_root rtl experiments realtime_layernorm]
set include_dir [file join $experiment data]
set engine [file join $experiment layernorm_engine_q12.v]
set parameter_rom [file join $experiment layernorm_parameter_rom_q12.v]
set coordinator [file join $experiment realtime_layernorm_coordinator.v]
set report_dir [file join $repo_root rtl reports realtime_layernorm_coordinator_$target_label]
foreach required [list $engine $parameter_rom $coordinator \
    [file join $include_dir layernorm_parameter_rom_q12_init.vh] \
    [file join $include_dir projection_dequant_q12_init.vh] \
    [file join $include_dir subband_source_index_init.vh]] {
    if {![file isfile $required]} {
        error "Missing real-time coordinator implementation input: $required"
    }
}
file delete -force $report_dir
file mkdir $report_dir

set build_dir [file join $repo_root rtl build realtime_layernorm_coordinator_$target_label]
file delete -force $build_dir
file mkdir $build_dir
set xdc [file join $build_dir realtime_layernorm_coordinator_$target_label.xdc]
set xdc_handle [open $xdc w]
puts $xdc_handle "create_clock -name clk -period $target_period \[get_ports clk\]"
puts $xdc_handle "set_property HD.CLK_SRC BUFGCTRL_X0Y0 \[get_ports clk\]"
puts $xdc_handle {set_input_delay 0.250 -clock clk [get_ports -filter {DIRECTION == IN && NAME != clk}]}
puts $xdc_handle {set_output_delay 0.250 -clock clk [all_outputs]}
puts $xdc_handle {set_clock_uncertainty 0.250 [get_clocks clk]}
close $xdc_handle

create_project -in_memory -part xc7z020clg400-1
set_property include_dirs $include_dir [current_fileset]
read_verilog $engine
read_verilog $parameter_rom
read_verilog $coordinator
read_xdc $xdc
synth_design -top realtime_layernorm_coordinator -part xc7z020clg400-1 \
    -mode out_of_context -flatten_hierarchy rebuilt
opt_design
place_design
phys_opt_design
route_design

report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
set check_path [file join $report_dir check_timing.rpt]
check_timing -verbose -file $check_path
set check_handle [open $check_path r]
set check_text [read $check_handle]
close $check_handle

set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 -quiet]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1 -quiet]
set internal_hold_path [get_timing_paths -delay_type min -from [all_registers] \
    -to [all_registers] -max_paths 1 -nworst 1 -quiet]
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
set internal_whs [get_property SLACK $internal_hold_path]
set data_path_delay [get_property DATAPATH_DELAY $setup_path]
set startpoint [get_property STARTPOINT_PIN $setup_path]
set endpoint [get_property ENDPOINT_PIN $setup_path]
set route_text [report_route_status -return_string]
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
set no_input_delay "NA"
set no_output_delay "NA"
regexp {There are ([0-9]+) input ports with no input delay} \
    $check_text unused no_input_delay
regexp {There are ([0-9]+) ports with no output delay} \
    $check_text unused no_output_delay

set metrics [open [file join $report_dir metrics.txt] w]
puts $metrics "evidence=Vivado_2018.3_OOC_place_and_route"
puts $metrics "scope=connected_layernorm_coordinator_not_full_accelerator"
puts $metrics "target_label=$target_label"
puts $metrics "target_period_ns=$target_period"
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

if {$wns < 0.0 || $internal_whs < 0.0 || $route_error_nets ne "0" ||
    $no_input_delay ne "0" || $no_output_delay ne "0"} {
    error "Real-time LayerNorm coordinator $target_label OOC checkpoint failed"
}
puts "REALTIME_COORDINATOR_OOC_PASS label=$target_label wns_ns=$wns internal_whs_ns=$internal_whs lut=$lut_count ff=$ff_count dsp=$dsp_count bram18=$ramb18_count bram36=$ramb36_count"
close_project
exit
