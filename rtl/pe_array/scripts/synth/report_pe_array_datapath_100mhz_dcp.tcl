# Report-only extraction from the already-routed 100 MHz connected OOC DCP.
# This script does not optimize, place, route, or modify the checkpoint.

if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    error "Usage: report_pe_array_datapath_100mhz_dcp.tcl <pe_root>"
}

set dcp_file [file join $pe_root build impl pe_array_datapath_100mhz \
    pe_array_datapath_100mhz_post_route.dcp]
set report_dir [file join $pe_root reports pe_array_datapath_100mhz]
if {![file isfile $dcp_file]} {
    error "Missing routed checkpoint: $dcp_file"
}
file mkdir $report_dir

open_checkpoint $dcp_file

set route_status_path [file join $report_dir route_status_post_route.rpt]
set check_timing_path [file join $report_dir check_timing_post_route.rpt]
report_route_status -file $route_status_path
check_timing -verbose -file $check_timing_path
report_timing -delay_type min -max_paths 20 -nworst 1 -sort_by group \
    -file [file join $report_dir timing_hold_paths_post_route.rpt]

set registers [all_registers]
report_timing -delay_type max -from $registers -to $registers \
    -max_paths 20 -nworst 1 -sort_by group \
    -file [file join $report_dir timing_internal_setup_post_route.rpt]
report_timing -delay_type min -from $registers -to $registers \
    -max_paths 20 -nworst 1 -sort_by group \
    -file [file join $report_dir timing_internal_hold_post_route.rpt]

proc emit_path {channel prefix path_collection} {
    if {[llength $path_collection] == 0} {
        puts $channel "${prefix}_slack_ns=NA"
        puts $channel "${prefix}_data_path_delay_ns=NA"
        puts $channel "${prefix}_startpoint=NA"
        puts $channel "${prefix}_endpoint=NA"
    } else {
        set path [lindex $path_collection 0]
        puts $channel "${prefix}_slack_ns=[get_property SLACK $path]"
        puts $channel "${prefix}_data_path_delay_ns=[get_property DATAPATH_DELAY $path]"
        puts $channel "${prefix}_startpoint=[get_property STARTPOINT_PIN $path]"
        puts $channel "${prefix}_endpoint=[get_property ENDPOINT_PIN $path]"
    }
}

set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 -quiet]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1 -quiet]
set internal_setup_path [get_timing_paths -delay_type max -from $registers \
    -to $registers -max_paths 1 -nworst 1 -quiet]
set internal_hold_path [get_timing_paths -delay_type min -from $registers \
    -to $registers -max_paths 1 -nworst 1 -quiet]

set dsp_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ DSP48*}]]
set ramb18_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB18E1}]]
set ramb36_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB36E1}]]
set lutram_count [llength [get_cells -hierarchical -quiet -filter \
    {REF_NAME =~ RAM32* || REF_NAME =~ RAM64* || \
     REF_NAME =~ RAM128* || REF_NAME =~ RAM256* || \
     REF_NAME =~ RAM512* || REF_NAME =~ RAMD32* || \
     REF_NAME =~ RAMS32* || REF_NAME =~ RAMD64* || \
     REF_NAME =~ RAMS64*}]]
set multiplier_macro_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ MULT*}]]
set ff_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ FD*}]]
set utilization_text [report_utilization -return_string]
set lut_count "NA"
regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
    $utilization_text unused lut_count

set route_status_file [open $route_status_path r]
set route_status [read $route_status_file]
close $route_status_file
set timing_check_file [open $check_timing_path r]
set timing_check [read $timing_check_file]
close $timing_check_file
set fully_routed_nets "NA"
set route_error_nets "NA"
regexp {# of fully routed nets\.*\s*:\s*([0-9]+)\s*:} \
    $route_status unused fully_routed_nets
regexp {# of nets with routing errors\.*\s*:\s*([0-9]+)\s*:} \
    $route_status unused route_error_nets

set metrics_path [file join $report_dir metrics_post_route.txt]
set metrics [open $metrics_path w]
puts $metrics "evidence=Vivado_2018.3_existing_OOC_post_route_DCP"
puts $metrics "part=xc7z020clg400-1"
puts $metrics "target_frequency_mhz=100"
puts $metrics "target_period_ns=10.000"
puts $metrics "implementation_run=OOC_PLACE_AND_ROUTE"
puts $metrics "bitstream=NOT_GENERATED"
emit_path $metrics setup $setup_path
emit_path $metrics hold $hold_path
emit_path $metrics internal_setup $internal_setup_path
emit_path $metrics internal_hold $internal_hold_path
puts $metrics "lut=$lut_count"
puts $metrics "ff_primitives=$ff_count"
puts $metrics "dsp48_primitives=$dsp_count"
puts $metrics "ramb18e1_primitives=$ramb18_count"
puts $metrics "ramb36e1_primitives=$ramb36_count"
puts $metrics "lutram_primitives=$lutram_count"
puts $metrics "multiplier_macros=$multiplier_macro_count"
puts $metrics "fully_routed_nets=$fully_routed_nets"
puts $metrics "route_error_nets=$route_error_nets"
puts $metrics "timing_coverage_nonzero_issue=[regexp {There are [1-9][0-9]*} $timing_check]"
puts $metrics "timing_constraints_met=[expr {\
    [get_property SLACK [lindex $setup_path 0]] >= 0.0 && \
    [get_property SLACK [lindex $hold_path 0]] >= 0.0}]"
close $metrics

puts "PE_ARRAY_DATAPATH_100MHZ_REPORT_ONLY_COMPLETE"
close_project
exit
