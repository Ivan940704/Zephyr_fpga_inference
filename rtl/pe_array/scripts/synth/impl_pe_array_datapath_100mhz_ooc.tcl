# Vivado 2018.3 connected PE Array datapath 100 MHz OOC implementation.
# This validation-only checkpoint performs synthesis, placement, and routing;
# it does not generate a bitstream.

if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set pe_root [file normalize \
        [file join [file dirname [file normalize [info script]]] ../..]]
}

set baseline_rtl [file join $pe_root baseline v1 rtl]
set wrapper_rtl [file join $pe_root rtl top pe_array_datapath.v]
set xdc_file [file join $pe_root constraints pe_array_datapath_100mhz.xdc]
set build_dir [file join $pe_root build impl pe_array_datapath_100mhz]
set report_dir [file join $pe_root reports pe_array_datapath_100mhz]

set verilog_2001_sources [list \
    [file join $baseline_rtl nonlinear pe_sigmoid_lut_255.v] \
    [file join $baseline_rtl postprocess pe_gate_postprocess.v] \
    [file join $baseline_rtl pe pe_membrane_sequencer.v] \
    [file join $baseline_rtl stream pe_output_serializer.v] \
    [file join $baseline_rtl stream pe_shared_requant_engine.v] \
    [file join $baseline_rtl index pe_spike_decision.v] \
    [file join $baseline_rtl index pe_active_index_writer.v] \
    [file join $baseline_rtl pe pe_cdf_sequencer.v] \
    $wrapper_rtl]
set historical_systemverilog_sources [list \
    [file join $baseline_rtl arithmetic pe_requant_lane.sv] \
    [file join $baseline_rtl arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $baseline_rtl pe pe_hybrid_mac.sv]]

foreach required_file [concat $historical_systemverilog_sources \
                              $verilog_2001_sources [list $xdc_file]] {
    if {![file isfile $required_file]} {
        error "Missing PE Array datapath 100 MHz input: $required_file"
    }
}

file delete -force $build_dir
file delete -force $report_dir
file mkdir $build_dir
file mkdir $report_dir

create_project -in_memory -part xc7z020clg400-1
foreach source_file $historical_systemverilog_sources {
    read_verilog -sv $source_file
}
foreach source_file $verilog_2001_sources {
    read_verilog $source_file
}
read_xdc $xdc_file

synth_design -top pe_array_datapath -part xc7z020clg400-1 \
    -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force \
    [file join $build_dir pe_array_datapath_100mhz_post_synth.dcp]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force \
    [file join $build_dir pe_array_datapath_100mhz_post_route.dcp]

report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical_post_route.rpt]
report_utilization \
    -file [file join $report_dir utilization_post_route.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -report_unconstrained \
    -file [file join $report_dir timing_summary_post_route.rpt]
report_timing -delay_type max -max_paths 20 -nworst 1 -sort_by group \
    -file [file join $report_dir timing_paths_post_route.rpt]
report_timing -delay_type min -max_paths 20 -nworst 1 -sort_by group \
    -file [file join $report_dir timing_hold_paths_post_route.rpt]
set timing_check_path [file join $report_dir check_timing_post_route.rpt]
check_timing -verbose -file $timing_check_path
set timing_check_file [open $timing_check_path r]
set timing_check [read $timing_check_file]
close $timing_check_file
report_route_status \
    -file [file join $report_dir route_status_post_route.rpt]
report_clock_utilization \
    -file [file join $report_dir clock_utilization_post_route.rpt]

set timing_path [get_timing_paths -delay_type max -max_paths 1 \
    -nworst 1 -quiet]
set hold_path [get_timing_paths -delay_type min -max_paths 1 \
    -nworst 1 -quiet]
set timing_path_count [llength $timing_path]
set hold_path_count [llength $hold_path]
set wns "NA"
set whs "NA"
set data_path_delay "NA"
set startpoint "NA"
set endpoint "NA"
if {$timing_path_count > 0} {
    set wns [get_property SLACK $timing_path]
    set data_path_delay [get_property DATAPATH_DELAY $timing_path]
    set startpoint [get_property STARTPOINT_PIN $timing_path]
    set endpoint [get_property ENDPOINT_PIN $timing_path]
}
if {$hold_path_count > 0} {
    set whs [get_property SLACK $hold_path]
}

set route_status_file [open \
    [file join $report_dir route_status_post_route.rpt] r]
set route_status [read $route_status_file]
close $route_status_file
set route_error_nets "NA"
regexp {# of nets with routing errors\.*\s*:\s*([0-9]+)\s*:} \
    $route_status unused route_error_nets

set clock_objects [get_clocks -quiet clk]
set clock_count [llength $clock_objects]
set actual_period "NA"
if {$clock_count == 1} {
    set actual_period [get_property PERIOD [lindex $clock_objects 0]]
}

set utilization_text [report_utilization -return_string]
set lut_count "NA"
if {![regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
      $utilization_text unused lut_count]} {
    puts stderr "RESOURCE ERROR: could not parse Slice LUT utilization"
}
set ff_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ FD*}]]
set dsp_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ DSP48*}]]
set ramb18_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB18E1}]]
set ramb36_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB36E1}]]
set lutram_cells [get_cells -hierarchical -quiet -filter \
    {REF_NAME =~ RAM32* || REF_NAME =~ RAM64* || \
     REF_NAME =~ RAM128* || REF_NAME =~ RAM256* || \
     REF_NAME =~ RAM512* || REF_NAME =~ RAMD32* || \
     REF_NAME =~ RAMS32* || REF_NAME =~ RAMD64* || \
     REF_NAME =~ RAMS64*}]
set lutram_count [llength $lutram_cells]
set multiplier_macro_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ MULT*}]]

set unexpected_dsp_count 0
foreach dsp_cell [get_cells -hierarchical -quiet -filter \
        {REF_NAME =~ DSP48*}] {
    set cell_name [get_property NAME $dsp_cell]
    if {![string match "gen_hybrid_pe*" $cell_name]
        && ![string match "u_local_requant_bank/*" $cell_name]
        && ![string match "u_shared_requant_engine/*" $cell_name]} {
        incr unexpected_dsp_count
    }
}
set unexpected_bram_count 0
foreach bram_cell [get_cells -hierarchical -quiet -filter \
        {REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1}] {
    if {![string match "u_sigmoid/*" [get_property NAME $bram_cell]]} {
        incr unexpected_bram_count
    }
}

set metrics [open [file join $report_dir metrics_post_route.txt] w]
puts $metrics "evidence=Vivado_2018.3_OOC_place_and_route"
puts $metrics "part=xc7z020clg400-1"
puts $metrics "target_frequency_mhz=100"
puts $metrics "target_period_ns=10.000"
puts $metrics "actual_clock_period_ns=$actual_period"
puts $metrics "implementation_run=OOC_PLACE_AND_ROUTE"
puts $metrics "bitstream=NOT_GENERATED"
puts $metrics "wns_ns=$wns"
puts $metrics "whs_ns=$whs"
puts $metrics "worst_data_path_delay_ns=$data_path_delay"
puts $metrics "critical_startpoint=$startpoint"
puts $metrics "critical_endpoint=$endpoint"
puts $metrics "timing_path_count=$timing_path_count"
puts $metrics "hold_path_count=$hold_path_count"
puts $metrics "route_error_nets=$route_error_nets"
puts $metrics "clock_count=$clock_count"
puts $metrics "lut=$lut_count"
puts $metrics "ff_primitives=$ff_count"
puts $metrics "dsp48_primitives=$dsp_count"
puts $metrics "ramb18e1_primitives=$ramb18_count"
puts $metrics "ramb36e1_primitives=$ramb36_count"
puts $metrics "lutram_primitives=$lutram_count"
puts $metrics "multiplier_macros=$multiplier_macro_count"
puts $metrics "unexpected_wrapper_dsp=$unexpected_dsp_count"
puts $metrics "unexpected_wrapper_bram=$unexpected_bram_count"
close $metrics

set failed 0
if {$timing_path_count == 0 || $wns eq "NA" || $wns < 0.0} {
    puts stderr "TIMING ERROR: 100 MHz post-route WNS=$wns"
    set failed 1
}
if {$hold_path_count == 0 || $whs eq "NA" || $whs < 0.0} {
    puts stderr "TIMING ERROR: 100 MHz post-route WHS=$whs"
    set failed 1
}
if {$route_error_nets eq "NA" || $route_error_nets != 0} {
    puts stderr "ROUTE ERROR: routed-net error count=$route_error_nets"
    set failed 1
}
if {$clock_count != 1 || $actual_period eq "NA"
    || [expr {abs($actual_period - 10.000)}] > 0.001} {
    puts stderr "CLOCK ERROR: count=$clock_count period=$actual_period"
    set failed 1
}
if {[regexp {There are [1-9][0-9]*} $timing_check]} {
    puts stderr "TIMING COVERAGE ERROR: check_timing reported nonzero issues"
    set failed 1
}
if {$lut_count eq "NA" || $dsp_count != 36
    || $ramb18_count != 2 || $ramb36_count != 0
    || $lutram_count != 0 || $multiplier_macro_count != 0
    || $unexpected_dsp_count != 0 || $unexpected_bram_count != 0} {
    puts stderr "RESOURCE ERROR: LUT=$lut_count DSP=$dsp_count RAMB18=$ramb18_count RAMB36=$ramb36_count LUTRAM=$lutram_count MULT=$multiplier_macro_count unexpected_DSP/BRAM=$unexpected_dsp_count/$unexpected_bram_count"
    set failed 1
}

if {$failed} {
    error "PE Array datapath 100 MHz OOC implementation checkpoint failed"
}
puts "PE_ARRAY_DATAPATH_100MHZ_IMPL_PASS wns_ns=$wns lut=$lut_count ff=$ff_count dsp=$dsp_count ramb18=$ramb18_count ramb36=$ramb36_count lutram=$lutram_count mult_macro=$multiplier_macro_count"
close_project
exit
