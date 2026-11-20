# Vivado 2018.3 synthesized and routed OOC gate for the connected
# sequential-v4 PE/memory subsystem.

if {$argc < 1} {
    error "Usage: synth_sequential_v4_pe_memory_subsystem_ooc.tcl <rtl_root>"
}
set rtl_root [file normalize [lindex $argv 0]]
set pe_root [file join $rtl_root pe_array baseline v1 rtl]
set part_name xc7z020clg400-1
set period_ns 10.000
set report_dir [file join $rtl_root reports sequential_v4_pe_memory_subsystem]
set build_dir [file join $rtl_root build synth sequential_v4_pe_memory_subsystem]
file mkdir $report_dir
file mkdir $build_dir

set sv_sources [list \
    [file join $pe_root arithmetic pe_requant_lane.sv] \
    [file join $pe_root arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $pe_root pe pe_hybrid_mac.sv]]
set v_sources [list \
    [file join $rtl_root memory memory.v] \
    [file join $rtl_root memory model_memory_v4_table.v] \
    [file join $rtl_root memory memory_service.v] \
    [file join $rtl_root memory sequential_recurrent_context_store.v] \
    [file join $rtl_root memory sequential_pe_job_controller.v] \
    [file join $pe_root nonlinear pe_sigmoid_lut_255.v] \
    [file join $pe_root postprocess pe_gate_postprocess.v] \
    [file join $pe_root pe pe_membrane_sequencer.v] \
    [file join $pe_root stream pe_output_serializer.v] \
    [file join $pe_root stream pe_shared_requant_engine.v] \
    [file join $pe_root index pe_spike_decision.v] \
    [file join $pe_root index pe_active_index_writer.v] \
    [file join $pe_root pe pe_cdf_sequencer.v] \
    [file join $pe_root top pe_array_datapath.v] \
    [file join $rtl_root memory sequential_v4_pe_memory_subsystem.v]]
set xdc_file [file join $rtl_root memory \
    sequential_v4_pe_memory_subsystem_100mhz.xdc]
foreach required [concat $sv_sources $v_sources [list $xdc_file]] {
    if {![file isfile $required]} { error "Missing OOC input: $required" }
}

create_project -in_memory -part $part_name
foreach source $sv_sources { read_verilog -sv $source }
foreach source $v_sources { read_verilog $source }
read_xdc $xdc_file
synth_design -top sequential_v4_pe_memory_subsystem -part $part_name \
    -mode out_of_context -flatten_hierarchy rebuilt

write_checkpoint -force [file join $build_dir subsystem_post_synth.dcp]
report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical_post_synth.rpt]
report_utilization \
    -file [file join $report_dir utilization_post_synth.rpt]
report_timing_summary -delay_type max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_synth.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_post_synth.rpt]
check_timing -verbose \
    -file [file join $report_dir check_timing_post_synth.rpt]

set timing_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 -quiet]
set wns_ns NA
set data_path_delay_ns NA
set timing_met 0
if {[llength $timing_path] > 0} {
    set wns_ns [get_property SLACK $timing_path]
    set data_path_delay_ns [get_property DATAPATH_DELAY $timing_path]
    set timing_met [expr {$wns_ns >= 0.0 ? 1 : 0}]
}

set utilization_text [report_utilization -return_string]
set slice_luts NA
set slice_registers NA
regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
    $utilization_text unused slice_luts
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
    $utilization_text unused slice_registers
set ramb36_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB36E1}]]
set ramb18_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB18E1}]]
set dsp_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ DSP48*}]]
set lutram_count [llength [get_cells -hierarchical -quiet -filter \
    {REF_NAME =~ RAM32* || REF_NAME =~ RAM64* || REF_NAME =~ RAM128* || REF_NAME =~ RAM256* || REF_NAME =~ RAM512*}]]
set srl_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ SRL*}]]

set lut_under_80 [expr {$slice_luts ne "NA" && $slice_luts < 42560}]
set ff_under_80 [expr {$slice_registers ne "NA" && $slice_registers < 85120}]
set bram_equiv [expr {$ramb36_count + ($ramb18_count / 2.0)}]
set bram_under_80 [expr {$bram_equiv < 112.0}]
set dsp_under_80 [expr {$dsp_count < 176}]

set metrics [open [file join $report_dir metrics_post_synth.txt] w]
puts $metrics "top=sequential_v4_pe_memory_subsystem"
puts $metrics "part=$part_name"
puts $metrics "target_period_ns=$period_ns"
puts $metrics "wns_ns=$wns_ns"
puts $metrics "data_path_delay_ns=$data_path_delay_ns"
puts $metrics "timing_met=$timing_met"
puts $metrics "slice_luts=$slice_luts"
puts $metrics "slice_registers=$slice_registers"
puts $metrics "ramb36_primitives=$ramb36_count"
puts $metrics "ramb18_primitives=$ramb18_count"
puts $metrics "dsp48_primitives=$dsp_count"
puts $metrics "lutram_primitives=$lutram_count"
puts $metrics "srl_primitives=$srl_count"
puts $metrics "resources_below_80_percent=[expr {$lut_under_80 && $ff_under_80 && $bram_under_80 && $dsp_under_80}]"
close $metrics

puts "SEQUENTIAL_V4_SUBSYSTEM_POST_SYNTH wns=$wns_ns LUT=$slice_luts FF=$slice_registers RAMB36=$ramb36_count RAMB18=$ramb18_count DSP=$dsp_count"

# The integrated design's post-synthesis timing is an unplaced estimate.  Run
# the actual OOC implementation because the acceptance contract explicitly
# requires routed/OOC evidence at 100 MHz.
opt_design
place_design -directive Explore
phys_opt_design
route_design -directive Explore

write_checkpoint -force [file join $build_dir subsystem_post_route.dcp]
report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical_post_route.rpt]
report_utilization \
    -file [file join $report_dir utilization_post_route.rpt]
report_route_status \
    -file [file join $report_dir route_status_post_route.rpt]
report_timing_summary -delay_type max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_route.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_post_route.rpt]
check_timing -verbose \
    -file [file join $report_dir check_timing_post_route.rpt]

set route_utilization_text [report_utilization -return_string]
set route_slice_luts NA
set route_slice_registers NA
regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
    $route_utilization_text unused route_slice_luts
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
    $route_utilization_text unused route_slice_registers
set route_ramb36_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB36E1}]]
set route_ramb18_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB18E1}]]
set route_dsp_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ DSP48*}]]
set route_lutram_count [llength [get_cells -hierarchical -quiet -filter \
    {REF_NAME =~ RAM32* || REF_NAME =~ RAM64* || REF_NAME =~ RAM128* || REF_NAME =~ RAM256* || REF_NAME =~ RAM512*}]]
set route_srl_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ SRL*}]]

set route_lut_under_80 [expr {$route_slice_luts ne "NA" &&
                              $route_slice_luts < 42560}]
set route_ff_under_80 [expr {$route_slice_registers ne "NA" &&
                             $route_slice_registers < 85120}]
set route_bram_equiv [expr {$route_ramb36_count +
                            ($route_ramb18_count / 2.0)}]
set route_bram_under_80 [expr {$route_bram_equiv < 112.0}]
set route_dsp_under_80 [expr {$route_dsp_count < 176}]

set route_status_text [report_route_status -return_string]
set timing_check_text [check_timing -return_string]
set route_error_free [regexp \
    {# of nets with routing errors\.*\s*:\s*0\s*:} $route_status_text]
set no_unconstrained_internal [regexp \
    {There are 0 pins that are not constrained for maximum delay\.} \
    $timing_check_text]
set no_clockless_registers [regexp \
    {There are 0 register/latch pins with no clock\.} $timing_check_text]
set no_timing_loops [regexp \
    {There are 0 combinational loops in the design\.} $timing_check_text]
set no_latch_loops [regexp \
    {There are 0 combinational latch loops in the design} $timing_check_text]

set route_timing_path [get_timing_paths -delay_type max -max_paths 1 \
    -nworst 1 -quiet]
set route_wns_ns NA
set route_data_path_delay_ns NA
set route_timing_met 0
if {[llength $route_timing_path] > 0} {
    set route_wns_ns [get_property SLACK $route_timing_path]
    set route_data_path_delay_ns \
        [get_property DATAPATH_DELAY $route_timing_path]
    set route_timing_met [expr {$route_wns_ns >= 0.0 ? 1 : 0}]
}

set route_metrics [open \
    [file join $report_dir metrics_post_route.txt] w]
puts $route_metrics "top=sequential_v4_pe_memory_subsystem"
puts $route_metrics "part=$part_name"
puts $route_metrics "target_period_ns=$period_ns"
puts $route_metrics "wns_ns=$route_wns_ns"
puts $route_metrics "data_path_delay_ns=$route_data_path_delay_ns"
puts $route_metrics "timing_met=$route_timing_met"
puts $route_metrics "slice_luts=$route_slice_luts"
puts $route_metrics "slice_registers=$route_slice_registers"
puts $route_metrics "ramb36_primitives=$route_ramb36_count"
puts $route_metrics "ramb18_primitives=$route_ramb18_count"
puts $route_metrics "dsp48_primitives=$route_dsp_count"
puts $route_metrics "lutram_primitives=$route_lutram_count"
puts $route_metrics "srl_primitives=$route_srl_count"
puts $route_metrics "resources_below_80_percent=[expr {$route_lut_under_80 && $route_ff_under_80 && $route_bram_under_80 && $route_dsp_under_80}]"
puts $route_metrics "routing_errors_zero=$route_error_free"
puts $route_metrics "unconstrained_internal_endpoints_zero=$no_unconstrained_internal"
puts $route_metrics "clockless_registers_zero=$no_clockless_registers"
puts $route_metrics "combinational_loops_zero=$no_timing_loops"
puts $route_metrics "latch_loops_zero=$no_latch_loops"
close $route_metrics

puts "SEQUENTIAL_V4_SUBSYSTEM_POST_ROUTE wns=$route_wns_ns LUT=$route_slice_luts FF=$route_slice_registers RAMB36=$route_ramb36_count RAMB18=$route_ramb18_count DSP=$route_dsp_count"
if {!$route_timing_met || !$route_lut_under_80 || !$route_ff_under_80 ||
    !$route_bram_under_80 || !$route_dsp_under_80 ||
    !$route_error_free || !$no_unconstrained_internal ||
    !$no_clockless_registers || !$no_timing_loops || !$no_latch_loops} {
    puts stderr "SEQUENTIAL_V4_SUBSYSTEM_OOC_GATE_FAIL"
    exit 2
}
if {$route_ramb36_count != 68 || $route_ramb18_count != 2 ||
    $route_dsp_count != 37 || $route_lutram_count != 0} {
    puts stderr "SEQUENTIAL_V4_SUBSYSTEM_OOC_ARCHITECTURE_FAIL"
    exit 3
}
puts "SEQUENTIAL_V4_SUBSYSTEM_OOC_PASS"
exit 0
