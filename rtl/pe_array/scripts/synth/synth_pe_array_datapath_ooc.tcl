# Vivado 2018.3 connected PE Array datapath OOC synthesis/resource gate.
#
# Usage:
#   vivado -mode batch -source synth_pe_array_datapath_ooc.tcl \
#       -tclargs /absolute/path/to/rtl/pe_array

if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set pe_root [file normalize \
        [file join [file dirname [file normalize [info script]]] ../..]]
}

set baseline_rtl [file join $pe_root baseline v1 rtl]
set wrapper_rtl [file join $pe_root rtl top pe_array_datapath.v]
set xdc_file [file join $pe_root constraints pe_array_datapath_200mhz.xdc]
set build_dir [file join $pe_root build synth pe_array_datapath]
set report_dir [file join $pe_root reports pe_array_datapath]

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
                              $verilog_2001_sources \
                              [list $xdc_file]] {
    if {![file isfile $required_file]} {
        error "Missing PE Array datapath checkpoint input: $required_file"
    }
}

file delete -force $build_dir
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
    [file join $build_dir pe_array_datapath_post_synth.dcp]
report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical_post_synth.rpt]
report_utilization \
    -file [file join $report_dir utilization_post_synth.rpt]
report_timing_summary -delay_type max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_synth.rpt]
report_timing -delay_type max -max_paths 20 -nworst 1 -sort_by group \
    -file [file join $report_dir timing_paths_post_synth.rpt]
check_timing -verbose \
    -file [file join $report_dir check_timing_post_synth.rpt]
report_clock_utilization \
    -file [file join $report_dir clock_utilization_post_synth.rpt]

set timing_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 -quiet]
set wns "NA"
set data_path_delay "NA"
set timing_path_count [llength $timing_path]
if {$timing_path_count > 0} {
    set wns [get_property SLACK $timing_path]
    set data_path_delay [get_property DATAPATH_DELAY $timing_path]
}

set utilization_text [report_utilization -return_string]
set lut_count "NA"
if {![regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
      $utilization_text unused lut_count]} {
    puts stderr "RESOURCE ERROR: could not parse physical Slice LUT utilization"
}

set logical_lut_count [llength [get_cells -hierarchical -quiet \
    -filter {PRIMITIVE_GROUP == LUT}]]
set ff_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ FD*}]]
set dsp_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ DSP48*}]]
set ramb18_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB18E1}]]
set ramb36_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB36E1}]]
set lutram_count [llength [get_cells -hierarchical -quiet -filter \
    {REF_NAME =~ RAM32* || REF_NAME =~ RAM64* || REF_NAME =~ RAM128* || REF_NAME =~ RAM256* || REF_NAME =~ RAM512*}]]
set multiplier_macro_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ MULT*}]]
set clock_count [llength [get_clocks -quiet clk]]

set resource_cells [open \
    [file join $report_dir resource_cells_post_synth.txt] w]
foreach primitive_class [list DSP48E1 RAMB18E1 RAMB36E1] {
    puts $resource_cells "$primitive_class:"
    foreach cell [lsort [get_cells -hierarchical -quiet \
            -filter "REF_NAME == $primitive_class"]] {
        puts $resource_cells "  $cell"
    }
}
puts $resource_cells "LUTRAM:"
foreach cell [lsort [get_cells -hierarchical -quiet -filter \
        {REF_NAME =~ RAM32* || REF_NAME =~ RAM64* || REF_NAME =~ RAM128* || REF_NAME =~ RAM256* || REF_NAME =~ RAM512*}]] {
    puts $resource_cells "  $cell ([get_property REF_NAME $cell])"
}
puts $resource_cells "MULT_MACRO:"
foreach cell [lsort [get_cells -hierarchical -quiet \
        -filter {REF_NAME =~ MULT*}]] {
    puts $resource_cells "  $cell ([get_property REF_NAME $cell])"
}
close $resource_cells

set metrics [open [file join $report_dir metrics_post_synth.txt] w]
puts $metrics "evidence=Vivado_2018.3_post_synthesis_OOC"
puts $metrics "part=xc7z020clg400-1"
puts $metrics "target_period_ns=5.000"
puts $metrics "wns_ns=$wns"
puts $metrics "worst_data_path_delay_ns=$data_path_delay"
puts $metrics "timing_path_count=$timing_path_count"
puts $metrics "clock_count=$clock_count"
puts $metrics "lut=$lut_count"
puts $metrics "logical_lut_primitives=$logical_lut_count"
puts $metrics "ff_primitives=$ff_count"
puts $metrics "dsp48_primitives=$dsp_count"
puts $metrics "ramb18e1_primitives=$ramb18_count"
puts $metrics "ramb36e1_primitives=$ramb36_count"
puts $metrics "lutram_primitives=$lutram_count"
puts $metrics "multiplier_macros=$multiplier_macro_count"
puts $metrics "expected_hybrid_pe_instances=16"
puts $metrics "expected_local_requant_banks=1"
puts $metrics "expected_requant_lanes_total=5"
puts $metrics "expected_shared_requant_engines=1"
close $metrics

set failed 0
if {$timing_path_count == 0} {
    puts stderr "TIMING ERROR: no constrained post-synthesis maximum-delay path found"
    set failed 1
} elseif {$wns < 0.0} {
    puts stderr "TIMING ERROR: post-synthesis OOC failed 5.000 ns target, WNS=$wns"
    set failed 1
}
if {$clock_count != 1} {
    puts stderr "TIMING ERROR: expected one clk timing object, got $clock_count"
    set failed 1
}
if {$lut_count eq "NA"} {
    set failed 1
}
if {$dsp_count != 36} {
    puts stderr "RESOURCE ERROR: expected 36 DSP48 primitives, got $dsp_count"
    set failed 1
}
if {$ramb18_count != 2 || $ramb36_count != 0} {
    puts stderr \
        "RESOURCE ERROR: expected 2 RAMB18E1 and 0 RAMB36E1, got $ramb18_count/$ramb36_count"
    set failed 1
}
if {$lutram_count != 0} {
    puts stderr "RESOURCE ERROR: expected zero LUTRAM primitives, got $lutram_count"
    set failed 1
}
if {$multiplier_macro_count != 0} {
    puts stderr \
        "RESOURCE ERROR: expected zero post-synthesis MULT macros, got $multiplier_macro_count"
    set failed 1
}

if {$failed} {
    error "PE Array datapath OOC timing/structural/resource checkpoint failed"
}
puts "PE_ARRAY_DATAPATH_OOC_PASS wns_ns=$wns lut=$lut_count ff=$ff_count dsp=$dsp_count ramb18=$ramb18_count ramb36=$ramb36_count lutram=$lutram_count mult_macro=$multiplier_macro_count"
close_project
exit
