# Fresh Vivado 2018.3 OOC implementation screen for the complete custom-RTL
# image-v5 / PL-LayerNorm / 32-lane accelerator top.  This is not a substitute
# for the routed PS7/AXI/DMA block-design gate.
# Arguments: <repo_root> ?period_ns? ?report_tag?
if {$argc < 1} {
    error "Usage: run_accelerator_top_v5_ooc.tcl <repo_root> ?period_ns? ?report_tag?"
}
set repo_root [file normalize [lindex $argv 0]]
set rtl_root [file join $repo_root rtl]
set period_ns [expr {$argc >= 2 ? [lindex $argv 1] : 10.000}]
set report_tag [expr {$argc >= 3 ? [lindex $argv 2] : "100mhz"}]
set part_name xc7z020clg400-1
set baseline [file join $rtl_root pe_array baseline v1 rtl]
set v2 [file join $rtl_root pe_array production_v2]
set layernorm [file join $rtl_root experiments realtime_layernorm]
set report_dir [file join $rtl_root reports accelerator_top_v5 $report_tag]
set build_dir [file join $rtl_root build implement accelerator_top_v5 $report_tag]

set sv_sources [list \
    [file join $rtl_root memory sparse_stage_map_v5.sv] \
    [file join $rtl_root memory sparse_union_planner_v5.sv] \
    [file join $baseline arithmetic pe_requant_lane.sv] \
    [file join $baseline arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $baseline pe pe_hybrid_mac.sv]]
set verilog_sources [list \
    [file join $rtl_root memory memory_wide256.v] \
    [file join $rtl_root memory model_memory_v5_table.v] \
    [file join $rtl_root memory memory_service_v5.v] \
    [file join $rtl_root memory sequential_recurrent_context_store_v5.v] \
    [file join $rtl_root memory sequential_pe_job_controller_v5.v] \
    [file join $baseline nonlinear pe_sigmoid_lut_255.v] \
    [file join $baseline postprocess pe_gate_postprocess.v] \
    [file join $baseline stream pe_shared_requant_engine.v] \
    [file join $baseline index pe_spike_decision.v] \
    [file join $baseline index pe_active_index_writer.v] \
    [file join $baseline pe pe_cdf_sequencer.v] \
    [file join $v2 rtl pe pe_hybrid_mac_array_32.v] \
    [file join $v2 rtl pe pe_membrane_sequencer_32.v] \
    [file join $v2 rtl stream pe_output_serializer_32.v] \
    [file join $v2 rtl top pe_array_datapath_v5_32.v] \
    [file join $rtl_root memory sequential_v5_pe_memory_subsystem.v] \
    [file join $rtl_root memory layernorm_mailbox.v] \
    [file join $rtl_root control fsm.v] \
    [file join $rtl_root integration layernorm_mailbox_fsm_adapter.v] \
    [file join $rtl_root integration sequential_feature_dispatcher.v] \
    [file join $rtl_root integration sequential_df_coefficient_store.v] \
    [file join $rtl_root integration hybrid_pe_deepfilter_controller.v] \
    [file join $layernorm layernorm_engine_q12.v] \
    [file join $layernorm layernorm_parameter_rom_q12.v] \
    [file join $layernorm realtime_layernorm_coordinator.v] \
    [file join $rtl_root top accelerator_top.v]]
set headers [glob -nocomplain [file join $layernorm data *.vh]]
foreach required [concat $sv_sources $verilog_sources $headers] {
    if {![file isfile $required]} {
        error "Missing accelerator-top-v5 OOC input: $required"
    }
}

file delete -force $report_dir $build_dir
file mkdir $report_dir
file mkdir $build_dir
create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
set_property include_dirs [list $rtl_root [file join $layernorm data]] [current_fileset]
foreach source $sv_sources { read_verilog -sv $source }
foreach source $verilog_sources { read_verilog $source }

set xdc_file [file join $build_dir accelerator_top_v5_clock.xdc]
set xdc [open $xdc_file w]
fconfigure $xdc -translation lf
puts $xdc "create_clock -name clk -period $period_ns \[get_ports clk\]"
puts $xdc "set_property HD.CLK_SRC BUFGCTRL_X0Y0 \[get_ports clk\]"
puts $xdc "set_input_delay 0.250 -clock clk \[get_ports -filter {DIRECTION == IN && NAME != clk}\]"
puts $xdc "set_output_delay 0.250 -clock clk \[all_outputs\]"
puts $xdc "set_clock_uncertainty 0.250 \[get_clocks clk\]"
close $xdc
read_xdc $xdc_file

synth_design -top accelerator_top -part $part_name -mode out_of_context \
    -flatten_hierarchy rebuilt
opt_design
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
write_checkpoint -force [file join $build_dir post_route.dcp]

report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical_post_route.rpt]
report_utilization -file [file join $report_dir utilization_post_route.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_route.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_post_route.rpt]
report_timing -delay_type min -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_hold_paths_post_route.rpt]
report_route_status -file [file join $report_dir route_status_post_route.rpt]
report_drc -file [file join $report_dir drc_post_route.rpt]
check_timing -verbose -file [file join $report_dir check_timing_post_route.rpt]

set utilization_text [report_utilization -return_string]
set lut_count NA
set ff_count NA
regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} $utilization_text unused lut_count
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} $utilization_text unused ff_count
set dsp_count [llength [get_cells -hierarchical -quiet -filter {REF_NAME =~ DSP48*}]]
set ramb18_count [llength [get_cells -hierarchical -quiet -filter {REF_NAME == RAMB18E1}]]
set ramb36_count [llength [get_cells -hierarchical -quiet -filter {REF_NAME == RAMB36E1}]]
set hybrid_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == pe_hybrid_mac || REF_NAME =~ pe_hybrid_mac__*}]]
set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 -quiet]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1 -quiet]
set internal_hold_path [get_timing_paths -delay_type min -from [all_registers] \
    -to [all_registers] -max_paths 1 -nworst 1 -quiet]
set wns_ns [expr {[llength $setup_path] ? [get_property SLACK $setup_path] : "NA"}]
set whs_ns [expr {[llength $hold_path] ? [get_property SLACK $hold_path] : "NA"}]
set internal_whs_ns [expr {[llength $internal_hold_path] \
    ? [get_property SLACK $internal_hold_path] : "NA"}]
set route_errors [llength [get_nets -hierarchical -quiet \
    -filter {ROUTE_STATUS == CONFLICTS || ROUTE_STATUS == UNROUTED}]]
set drc_errors [llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]
set check_text [check_timing -return_string]
set unconstrained_zero [regexp \
    {There are 0 pins that are not constrained for maximum delay\.} $check_text]
set clockless_zero [regexp \
    {There are 0 register/latch pins with no clock\.} $check_text]
set loops_zero [regexp \
    {There are 0 combinational loops in the design\.} $check_text]
set latch_loops_zero [regexp \
    {There are 0 combinational latch loops in the design} $check_text]

set setup_met [expr {$wns_ns ne "NA" && $wns_ns >= 0.0}]
set internal_hold_met [expr {$internal_whs_ns ne "NA" && $internal_whs_ns >= 0.0}]
set resources_met [expr {$lut_count ne "NA" && $ff_count ne "NA" \
    && $lut_count < 42560 && $ff_count < 85120 && $dsp_count < 176 \
    && ($ramb36_count + $ramb18_count / 2.0) < 112.0}]
set hierarchy_met [expr {$hybrid_count == 32}]

set metrics [open [file join $report_dir metrics_post_route.txt] w]
fconfigure $metrics -translation lf
puts $metrics "evidence=fresh_accelerator_top_ooc_post_route"
puts $metrics "scope=image_v5_pl_layernorm_32_lane_custom_rtl_top"
puts $metrics "part=$part_name"
puts $metrics "target_period_ns=$period_ns"
puts $metrics "wns_ns=$wns_ns"
puts $metrics "all_path_whs_ns=$whs_ns"
puts $metrics "internal_register_to_register_whs_ns=$internal_whs_ns"
puts $metrics "routing_error_nets=$route_errors"
puts $metrics "drc_errors=$drc_errors"
puts $metrics "unconstrained_internal_endpoints_zero=$unconstrained_zero"
puts $metrics "clockless_registers_zero=$clockless_zero"
puts $metrics "combinational_loops_zero=$loops_zero"
puts $metrics "latch_loops_zero=$latch_loops_zero"
puts $metrics "slice_luts=$lut_count"
puts $metrics "slice_registers=$ff_count"
puts $metrics "dsp48_primitives=$dsp_count"
puts $metrics "ramb18_primitives=$ramb18_count"
puts $metrics "ramb36_primitives=$ramb36_count"
puts $metrics "hybrid_mac_instances=$hybrid_count"
puts $metrics "full_block_design=NOT_RUN_THIS_GATE"
puts $metrics "bitstream=NOT_GENERATED_OOC_ONLY"
close $metrics

puts "ACCELERATOR_TOP_V5_OOC_RESULT tag=$report_tag wns=$wns_ns internal_whs=$internal_whs_ns all_path_whs=$whs_ns LUT=$lut_count FF=$ff_count DSP=$dsp_count RAMB36=$ramb36_count RAMB18=$ramb18_count hybrid=$hybrid_count"
close_project
if {!$setup_met || !$internal_hold_met || $route_errors != 0 \
    || $drc_errors != 0 || !$resources_met || !$hierarchy_met \
    || !$unconstrained_zero || !$clockless_zero || !$loops_zero \
    || !$latch_loops_zero} {
    puts stderr "ACCELERATOR_TOP_V5_OOC_GATE_FAIL tag=$report_tag"
    exit 2
}
puts "ACCELERATOR_TOP_V5_OOC_GATE_PASS tag=$report_tag"
exit 0
