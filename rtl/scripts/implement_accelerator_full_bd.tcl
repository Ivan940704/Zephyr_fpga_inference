# Route-only implementation flow for the complete PYNQ-Z1 accelerator BD.
#
# Usage:
#   vivado -mode batch -source implement_accelerator_full_bd.tcl \
#          -tclargs <staged-rtl-root> <design-baseline-commit>
#
# The validated project and post-synthesis checkpoint must first be recreated
# by create_accelerator_full_bd.tcl and synth_accelerator_full_bd.tcl.  This
# flow stops after routed-design physical optimization, emits Gate-C evidence,
# and never invokes write_bitstream, write_hw_platform, or export_hardware.

if {$argc >= 1} {
    set rtl_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set rtl_root [file normalize [file join $script_dir ..]]
}
if {$argc >= 2} {
    set design_commit [lindex $argv 1]
} else {
    set design_commit UNKNOWN
}
if {$argc >= 3 && [lindex $argv 2] ne "-"} {
    set incremental_reference [file normalize [lindex $argv 2]]
} else {
    set incremental_reference ""
}
if {$argc >= 4} {
    set output_suffix [lindex $argv 3]
} else {
    set output_suffix ""
}

set part_name xc7z020clg400-1
set period_ns 10.000
set setup_margin_target_ns 0.250
set setup_default_uncertainty_ns 0.154
set setup_implementation_uncertainty_ns \
    [expr {$setup_default_uncertainty_ns + $setup_margin_target_ns}]
set hold_guardband_ns 0.050
set project_dir [file join [file dirname $rtl_root] zephyr_full_bd]
set synth_checkpoint [file join $project_dir checkpoints zephyr_full_post_synth.dcp]
set report_name accelerator_full_bd_implementation
set checkpoint_name zephyr_full_post_route
if {$output_suffix ne ""} {
    append report_name "_" $output_suffix
    append checkpoint_name "_" $output_suffix
}
set report_dir [file join $rtl_root reports $report_name]
set checkpoint_dir [file join [file dirname $rtl_root] zephyr_full_implementation_checkpoints]
file mkdir $report_dir
file mkdir $checkpoint_dir

if {![file isfile $synth_checkpoint]} {
    error "Missing full-design post-synthesis checkpoint: $synth_checkpoint"
}

set report_failures [list]

proc run_required_report {label command_words} {
    global report_failures
    if {[catch {uplevel #0 $command_words} reason]} {
        lappend report_failures "$label: $reason"
        puts stderr "ACCELERATOR_FULL_REPORT_ERROR label=$label reason=$reason"
    } else {
        puts "ACCELERATOR_FULL_REPORT_PASS label=$label"
    }
}

proc read_text_file {path} {
    if {![file isfile $path]} {
        return ""
    }
    set channel [open $path r]
    set payload [read $channel]
    close $channel
    return $payload
}

proc worst_slack {delay_type} {
    set paths [get_timing_paths -quiet -delay_type $delay_type -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} {
        return NA
    }
    return [get_property SLACK [lindex $paths 0]]
}

proc failing_timing_metrics {delay_type} {
    set paths [get_timing_paths -quiet -delay_type $delay_type -max_paths 100000 \
        -nworst 1 -slack_lesser_than 0.0]
    set total 0.0
    foreach path $paths {
        set total [expr {$total + double([get_property SLACK $path])}]
    }
    return [list [llength $paths] $total]
}

proc violation_severity_counts {violations} {
    set errors 0
    set critical_warnings 0
    set warnings 0
    foreach violation $violations {
        set severity [get_property SEVERITY $violation]
        if {[string equal -nocase $severity "Error"]} {
            incr errors
        } elseif {[string equal -nocase $severity "Critical Warning"]} {
            incr critical_warnings
        } elseif {[string equal -nocase $severity "Warning"]} {
            incr warnings
        }
    }
    return [list $errors $critical_warnings $warnings]
}

set flow_ok 0
if {[catch {
    open_checkpoint $synth_checkpoint
    if {[get_property PART [current_design]] ne $part_name} {
        error "Checkpoint part mismatch: [get_property PART [current_design]]"
    }

    # Require 50 ps beyond the device hold requirement.  The previous routed
    # result met hold by only 14 ps because a short AXI-DMA path saw 261 ps of
    # clock skew.  Applying the guardband before placement/routing makes the
    # short-path requirement visible to the implementation algorithms instead
    # of relying on a best-effort repair after routing.
    set target_clock [get_clocks -quiet clk_fpga_0]
    if {[llength $target_clock] != 1} {
        error "Expected exactly one clk_fpga_0 clock, found [llength $target_clock]"
    }
    # Make the preferred 250 ps setup margin visible to placement/routing.
    # Vivado's calculated setup uncertainty is 154 ps for this PS7 clock; an
    # explicit 404 ps implementation uncertainty therefore asks the tools to
    # close 250 ps beyond the ordinary timing requirement.  The standard
    # 154 ps value is restored before checkpoint/report generation.
    set_clock_uncertainty -setup $setup_implementation_uncertainty_ns \
        $target_clock
    set_clock_uncertainty -hold $hold_guardband_ns $target_clock

    # Match the timing-directed sequence that closed the accelerator-only OOC
    # top, while retaining the real PS7/AXI/DMA placement context.
    opt_design
    if {$incremental_reference ne ""} {
        if {![file isfile $incremental_reference]} {
            error "Missing incremental routed checkpoint: $incremental_reference"
        }
        read_checkpoint -incremental $incremental_reference
    }
    if {$incremental_reference ne ""} {
        # High-reuse incremental closure is intended for very small ECO-like
        # RTL changes. Quick placement legalizes only the changed logic and
        # avoids Default's timing-improvement pass, which discarded thousands
        # of otherwise reusable placements in this congestion-limited design.
        place_design -directive Quick
    } else {
        place_design -directive Explore
        phys_opt_design -directive AggressiveExplore
    }
    route_design -directive Explore

    # Vivado 2018.3 automatically selects post-route mode when every net is
    # routed; the newer "-post_route" switch is not available in this release.
    # A routed-design pass is required here because the first Explore route can
    # leave a few tens of picoseconds of setup deficit in the complete PS/AXI
    # placement context even when the pre-route estimate is positive.
    set route_setup_slack [worst_slack max]
    set route_hold_slack [worst_slack min]
    puts "ACCELERATOR_FULL_ROUTE_BEFORE_PHYSOPT wns=$route_setup_slack whs=$route_hold_slack"
    phys_opt_design -directive AggressiveExplore

    set setup_guardbanded_slack [worst_slack max]
    set_clock_uncertainty -setup $setup_default_uncertainty_ns $target_clock

    set route_checkpoint [file join $checkpoint_dir ${checkpoint_name}.dcp]
    write_checkpoint -force $route_checkpoint

    set utilization_hierarchical_path [file join $report_dir utilization_hierarchical_post_route.rpt]
    set utilization_path [file join $report_dir utilization_post_route.rpt]
    set timing_summary_path [file join $report_dir timing_summary_post_route.rpt]
    set setup_paths_path [file join $report_dir timing_paths_setup_post_route.rpt]
    set hold_paths_path [file join $report_dir timing_paths_hold_post_route.rpt]
    set check_timing_path [file join $report_dir check_timing_post_route.rpt]
    set clocks_path [file join $report_dir clocks_post_route.rpt]
    set clock_utilization_path [file join $report_dir clock_utilization_post_route.rpt]
    set clock_interaction_path [file join $report_dir clock_interaction_post_route.rpt]
    set bus_skew_path [file join $report_dir bus_skew_post_route.rpt]
    set cdc_path [file join $report_dir cdc_post_route.rpt]
    set route_status_path [file join $report_dir route_status_post_route.rpt]
    set congestion_path [file join $report_dir congestion_post_route.rpt]
    set drc_path [file join $report_dir drc_post_route.rpt]
    set methodology_path [file join $report_dir methodology_post_route.rpt]
    set high_fanout_path [file join $report_dir high_fanout_post_route.rpt]

    run_required_report post_route_utilization_hierarchical [list report_utilization \
        -hierarchical -file $utilization_hierarchical_path]
    run_required_report post_route_utilization [list report_utilization \
        -file $utilization_path]
    run_required_report post_route_timing_summary [list report_timing_summary \
        -delay_type min_max -max_paths 20 -report_unconstrained \
        -file $timing_summary_path]
    run_required_report post_route_setup_paths [list report_timing \
        -delay_type max -max_paths 20 -sort_by group -file $setup_paths_path]
    run_required_report post_route_hold_paths [list report_timing \
        -delay_type min -max_paths 20 -sort_by group -file $hold_paths_path]
    run_required_report post_route_check_timing [list check_timing -verbose \
        -file $check_timing_path]
    run_required_report post_route_clocks [list report_clocks -file $clocks_path]
    run_required_report post_route_clock_utilization [list report_clock_utilization \
        -file $clock_utilization_path]
    run_required_report post_route_clock_interaction [list report_clock_interaction \
        -delay_type min_max -file $clock_interaction_path]
    run_required_report post_route_bus_skew [list report_bus_skew -file $bus_skew_path]
    run_required_report post_route_cdc [list report_cdc -details -file $cdc_path]
    run_required_report post_route_route_status [list report_route_status \
        -file $route_status_path]
    run_required_report post_route_congestion [list report_design_analysis \
        -congestion -file $congestion_path]
    run_required_report post_route_drc [list report_drc -file $drc_path]
    run_required_report post_route_methodology [list report_methodology \
        -file $methodology_path]
    run_required_report post_route_high_fanout [list report_high_fanout_nets \
        -timing -file $high_fanout_path]

    set constraint_report [open [file join $report_dir constraint_inventory.txt] w]
    fconfigure $constraint_report -translation lf
    puts $constraint_report "current_clocks=[join [get_clocks -quiet] ,]"
    puts $constraint_report "setup_margin_target_ns=$setup_margin_target_ns"
    puts $constraint_report "setup_default_uncertainty_ns=$setup_default_uncertainty_ns"
    puts $constraint_report "setup_implementation_uncertainty_ns=$setup_implementation_uncertainty_ns"
    puts $constraint_report "setup_guardband_command=set_clock_uncertainty -setup $setup_implementation_uncertainty_ns clk_fpga_0"
    puts $constraint_report "setup_report_command=set_clock_uncertainty -setup $setup_default_uncertainty_ns clk_fpga_0"
    puts $constraint_report "hold_guardband_ns=$hold_guardband_ns"
    puts $constraint_report "hold_guardband_command=set_clock_uncertainty -hold $hold_guardband_ns clk_fpga_0"
    foreach clock [get_clocks -quiet] {
        puts $constraint_report "clock=[get_property NAME $clock] period_ns=[get_property PERIOD $clock] waveform=[get_property WAVEFORM $clock]"
    }
    foreach xdc [get_files -quiet -all -filter {FILE_TYPE == XDC}] {
        puts $constraint_report "xdc=[get_property NAME $xdc] used_in=[get_property USED_IN $xdc]"
    }
    close $constraint_report

    set setup_slack [worst_slack max]
    set hold_slack [worst_slack min]
    set setup_fail [failing_timing_metrics max]
    set hold_fail [failing_timing_metrics min]
    set setup_met [expr {$setup_slack ne "NA" && double($setup_slack) >= 0.0 && [lindex $setup_fail 0] == 0}]
    set setup_engineering_margin_met [expr {
        $setup_met && $setup_guardbanded_slack ne "NA" &&
        double($setup_guardbanded_slack) >= 0.0 &&
        double($setup_slack) >= double($setup_margin_target_ns)
    }]
    set hold_met [expr {$hold_slack ne "NA" && double($hold_slack) >= 0.0 && [lindex $hold_fail 0] == 0}]

    # Also record the physical hold slack without the deliberate guardband.
    # The final routed checkpoint and reports retain the 50 ps constraint.
    set_clock_uncertainty -hold 0.000 $target_clock
    set hold_raw_slack [worst_slack min]
    set_clock_uncertainty -hold $hold_guardband_ns $target_clock
    set hold_guardband_met [expr {
        $hold_met && $hold_raw_slack ne "NA" &&
        double($hold_raw_slack) >= double($hold_guardband_ns)
    }]

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
    set bram_equiv [expr {$ramb36_count + ($ramb18_count / 2.0)}]
    set resource_limit_percent 90.0
    set resources_below_limit [expr {$slice_luts ne "NA" &&
        $slice_registers ne "NA" && $slice_luts < 47880 &&
        $slice_registers < 95760 && $bram_equiv < 126.0 && $dsp_count < 198}]

    set route_status_text [read_text_file $route_status_path]
    set timing_check_text [read_text_file $check_timing_path]
    set cdc_text [read_text_file $cdc_path]
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
        {There are 0 combinational latch loops in the design through latch input} \
        $timing_check_text]
    set cdc_safe [regexp {All paths are Safely Timed\.} $cdc_text]

    set drc_counts [violation_severity_counts [get_drc_violations -quiet]]
    set drc_error_count [lindex $drc_counts 0]
    set drc_critical_count [lindex $drc_counts 1]
    set drc_warning_count [lindex $drc_counts 2]
    set methodology_error_count NA
    set methodology_critical_count NA
    set methodology_warning_count NA
    if {[llength [info commands get_methodology_violations]] > 0} {
        set methodology_counts [violation_severity_counts \
            [get_methodology_violations -quiet]]
        set methodology_error_count [lindex $methodology_counts 0]
        set methodology_critical_count [lindex $methodology_counts 1]
        set methodology_warning_count [lindex $methodology_counts 2]
    }
    set blocking_drc_zero [expr {$drc_error_count == 0 && $drc_critical_count == 0}]

    # The release safety gate follows the project contract: non-negative
    # setup/hold timing, complete coverage, clean routing/DRC, and resource
    # headroom.  The extra 250 ps setup target and 50 ps raw-hold target remain
    # reported as engineering-margin indicators, but a miss on an optional
    # margin alone must not relabel a timing-clean routed design as unsafe.
    set full_gate_pass [expr {
        [llength $report_failures] == 0 &&
        $setup_met && $hold_met && $resources_below_limit &&
        $route_error_free && $no_unconstrained_internal &&
        $no_clockless_registers && $no_timing_loops && $no_latch_loops &&
        $cdc_safe && $blocking_drc_zero
    }]

    set metrics [open [file join $report_dir metrics_post_route.txt] w]
    fconfigure $metrics -translation lf
    puts $metrics "evidence=full_block_design_post_route"
    puts $metrics "vivado_version=[version -short]"
    puts $metrics "design_baseline_commit=$design_commit"
    puts $metrics "part=$part_name"
    puts $metrics "top=zephyr_full_wrapper"
    puts $metrics "target_period_ns=$period_ns"
    puts $metrics "setup_margin_target_ns=$setup_margin_target_ns"
    puts $metrics "setup_default_uncertainty_ns=$setup_default_uncertainty_ns"
    puts $metrics "setup_implementation_uncertainty_ns=$setup_implementation_uncertainty_ns"
    puts $metrics "hold_guardband_ns=$hold_guardband_ns"
    if {$incremental_reference ne ""} {
        puts $metrics "implementation_sequence=opt_design,read_checkpoint_incremental,place_design_Quick,route_design_Explore,phys_opt_design_post_route_AggressiveExplore"
    } else {
        puts $metrics "implementation_sequence=opt_design,place_design_Explore,phys_opt_design_AggressiveExplore,route_design_Explore,phys_opt_design_post_route_AggressiveExplore"
    }
    puts $metrics "incremental_reference=$incremental_reference"
    puts $metrics "route_setup_wns_before_post_route_physopt_ns=$route_setup_slack"
    puts $metrics "route_hold_whs_guardbanded_before_post_route_physopt_ns=$route_hold_slack"
    puts $metrics "setup_wns_ns=$setup_slack"
    puts $metrics "setup_guardbanded_wns_ns=$setup_guardbanded_slack"
    puts $metrics "setup_failing_endpoints=[lindex $setup_fail 0]"
    puts $metrics "setup_tns_ns=[lindex $setup_fail 1]"
    puts $metrics "timing_met=$setup_met"
    puts $metrics "setup_engineering_margin_met=$setup_engineering_margin_met"
    puts $metrics "hold_whs_ns=$hold_slack"
    puts $metrics "hold_failing_endpoints=[lindex $hold_fail 0]"
    puts $metrics "hold_ths_ns=[lindex $hold_fail 1]"
    puts $metrics "hold_met=$hold_met"
    puts $metrics "hold_raw_physical_margin_ns=$hold_raw_slack"
    puts $metrics "hold_guardband_met=$hold_guardband_met"
    puts $metrics "slice_luts=$slice_luts"
    puts $metrics "slice_registers=$slice_registers"
    puts $metrics "ramb36_primitives=$ramb36_count"
    puts $metrics "ramb18_primitives=$ramb18_count"
    puts $metrics "bram36_equivalent=$bram_equiv"
    puts $metrics "dsp48_primitives=$dsp_count"
    puts $metrics "resource_limit_percent=$resource_limit_percent"
    puts $metrics "resources_below_limit=$resources_below_limit"
    puts $metrics "routing_errors_zero=$route_error_free"
    puts $metrics "unconstrained_internal_endpoints_zero=$no_unconstrained_internal"
    puts $metrics "clockless_registers_zero=$no_clockless_registers"
    puts $metrics "combinational_loops_zero=$no_timing_loops"
    puts $metrics "latch_loops_zero=$no_latch_loops"
    puts $metrics "cdc_all_paths_safely_timed=$cdc_safe"
    puts $metrics "drc_errors=$drc_error_count"
    puts $metrics "drc_critical_warnings=$drc_critical_count"
    puts $metrics "drc_warnings=$drc_warning_count"
    puts $metrics "blocking_drc_zero=$blocking_drc_zero"
    puts $metrics "methodology_errors=$methodology_error_count"
    puts $metrics "methodology_critical_warnings=$methodology_critical_count"
    puts $metrics "methodology_warnings=$methodology_warning_count"
    puts $metrics "required_report_failures=[llength $report_failures]"
    foreach failure $report_failures {
        puts $metrics "report_failure=$failure"
    }
    puts $metrics "post_synth_checkpoint=$synth_checkpoint"
    puts $metrics "post_route_checkpoint=$route_checkpoint"
    puts $metrics "implementation_terminal_step=post_route_phys_opt_design"
    puts $metrics "full_gate_pass=$full_gate_pass"
    puts $metrics "write_bitstream_invoked=NO"
    puts $metrics "hwh_requested=NO"
    puts $metrics "board_connected=NO"
    close $metrics

    set flow_ok $full_gate_pass
    puts "ACCELERATOR_FULL_POST_ROUTE wns=$setup_slack whs=$hold_slack LUT=$slice_luts FF=$slice_registers RAMB36=$ramb36_count RAMB18=$ramb18_count DSP=$dsp_count"
    close_design
} reason failure_options]} {
    puts stderr "ACCELERATOR_FULL_IMPLEMENTATION_FATAL $reason"
    if {[dict exists $failure_options -errorinfo]} {
        puts stderr "ACCELERATOR_FULL_IMPLEMENTATION_ERRORINFO [dict get $failure_options -errorinfo]"
    }
    set failure_report [open [file join $report_dir flow_failure.txt] w]
    fconfigure $failure_report -translation lf
    puts $failure_report "evidence=full_block_design_implementation_attempt"
    puts $failure_report "design_baseline_commit=$design_commit"
    puts $failure_report "part=$part_name"
    puts $failure_report "failure=$reason"
    puts $failure_report "write_bitstream_invoked=NO"
    puts $failure_report "hwh_requested=NO"
    puts $failure_report "board_connected=NO"
    close $failure_report
    catch {close_design}
    exit 1
}

puts "ACCELERATOR_FULL_IMPLEMENTATION_ROUTE_COMPLETE"
if {!$flow_ok} {
    puts stderr "ACCELERATOR_FULL_IMPLEMENTATION_GATE_FAIL"
    exit 2
}
puts "ACCELERATOR_FULL_IMPLEMENTATION_ROUTE_PASS"
puts "ACCELERATOR_FULL_IMPLEMENTATION_BITSTREAM_NOT_RUN"
exit 0
