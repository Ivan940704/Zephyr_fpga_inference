# Generate the complete accelerator BIT/HWH pair from an already signed-off
# routed checkpoint.  This is deliberately a separate fail-closed step from
# implementation: every release timing/route/DRC gate is recomputed before
# write_bitstream is allowed to run.

if {$argc != 5} {
    puts stderr "Usage: write_accelerator_full_artifacts.tcl <route-dcp> <same-project-hwh> <artifact-dir> <report-dir> <hardware-commit>"
    exit 64
}

set route_checkpoint [file normalize [lindex $argv 0]]
set source_hwh [file normalize [lindex $argv 1]]
set artifact_dir [file normalize [lindex $argv 2]]
set report_dir [file normalize [lindex $argv 3]]
set hardware_commit [lindex $argv 4]

set expected_part xc7z020clg400-1
set expected_top zephyr_full_wrapper
set setup_default_uncertainty_ns 0.154
set setup_margin_target_ns 0.250
set setup_release_uncertainty_ns \
    [expr {$setup_default_uncertainty_ns + $setup_margin_target_ns}]
set hold_guardband_ns 0.050
set resource_limit_percent 90.0
set artifact_basename zephyr_full

file mkdir $artifact_dir
file mkdir $report_dir

proc worst_slack {delay_type} {
    set paths [get_timing_paths -quiet -delay_type $delay_type -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} {
        return NA
    }
    return [get_property SLACK [lindex $paths 0]]
}

proc failing_endpoint_count {delay_type} {
    return [llength [get_timing_paths -quiet -delay_type $delay_type \
        -max_paths 100000 -nworst 1 -slack_lesser_than 0.0]]
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
    foreach required [list $route_checkpoint $source_hwh] {
        if {![file isfile $required] || [file size $required] == 0} {
            error "Required implementation input is missing or empty: $required"
        }
    }

    open_checkpoint $route_checkpoint
    if {[get_property PART [current_design]] ne $expected_part} {
        error "Checkpoint part mismatch: [get_property PART [current_design]]"
    }
    # open_checkpoint names the in-memory design after the DCP filename, not
    # the synthesized top.  Bind the wrapper structurally to its sole BD
    # instance instead of trusting that mutable in-memory design name.
    set top_instances [get_cells -quiet zephyr_full_i]
    if {[llength $top_instances] != 1 ||
        [get_property REF_NAME [lindex $top_instances 0]] ne "zephyr_full"} {
        error "Checkpoint does not contain the expected $expected_top/zephyr_full_i structure"
    }
    set target_clock [get_clocks -quiet clk_fpga_0]
    if {[llength $target_clock] != 1} {
        error "Expected exactly one clk_fpga_0, found [llength $target_clock]"
    }

    # The saved DCP retains ordinary setup uncertainty and the deliberate
    # 50 ps hold guardband.  Measure both release and raw physical margins.
    set setup_wns [worst_slack max]
    set setup_failures [failing_endpoint_count max]
    set hold_guardbanded_whs [worst_slack min]
    set hold_failures [failing_endpoint_count min]

    set_clock_uncertainty -setup $setup_release_uncertainty_ns $target_clock
    set setup_guardbanded_wns [worst_slack max]
    set_clock_uncertainty -setup $setup_default_uncertainty_ns $target_clock

    set_clock_uncertainty -hold 0.000 $target_clock
    set hold_raw_whs [worst_slack min]
    set_clock_uncertainty -hold $hold_guardband_ns $target_clock

    report_timing_summary -delay_type min_max -max_paths 20 \
        -report_unconstrained \
        -file [file join $report_dir timing_summary_artifact_gate.rpt]
    report_route_status -file [file join $report_dir route_status_artifact_gate.rpt]
    report_drc -file [file join $report_dir drc_artifact_gate.rpt]
    report_utilization -file [file join $report_dir utilization_artifact_gate.rpt]

    set unrouted_nets [llength [get_nets -quiet -hierarchical \
        -filter {ROUTE_STATUS == UNROUTED}]]
    set partially_routed_nets [llength [get_nets -quiet -hierarchical \
        -filter {ROUTE_STATUS == PARTIALLY_ROUTED}]]
    set drc_counts [violation_severity_counts [get_drc_violations -quiet]]
    set drc_errors [lindex $drc_counts 0]
    set drc_critical_warnings [lindex $drc_counts 1]
    set drc_warnings [lindex $drc_counts 2]
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
    set resources_below_limit [expr {$slice_luts ne "NA" &&
        $slice_registers ne "NA" && $slice_luts < 47880 &&
        $slice_registers < 95760 && $bram_equiv < 126.0 && $dsp_count < 198}]

    if {$setup_wns eq "NA" || double($setup_wns) < 0.0 ||
        $setup_failures != 0} {
        error "Setup release gate failed: WNS=$setup_wns failures=$setup_failures"
    }
    if {$hold_guardbanded_whs eq "NA" ||
        double($hold_guardbanded_whs) < 0.0 || $hold_failures != 0} {
        error "Hold guardband gate failed: WHS=$hold_guardbanded_whs failures=$hold_failures"
    }
    if {$hold_raw_whs eq "NA" || double($hold_raw_whs) < $hold_guardband_ns} {
        error "Raw hold margin gate failed: WHS=$hold_raw_whs"
    }
    if {$unrouted_nets != 0 || $partially_routed_nets != 0} {
        error "Route gate failed: unrouted=$unrouted_nets partial=$partially_routed_nets"
    }
    if {$drc_errors != 0 || $drc_critical_warnings != 0} {
        error "Blocking DRC gate failed: errors=$drc_errors critical=$drc_critical_warnings"
    }
    if {!$resources_below_limit} {
        error "Resource gate failed at ${resource_limit_percent} percent: LUT=$slice_luts FF=$slice_registers BRAM36eq=$bram_equiv DSP=$dsp_count"
    }

    set bit_path [file join $artifact_dir ${artifact_basename}.bit]
    set hwh_path [file join $artifact_dir ${artifact_basename}.hwh]
    write_bitstream -force $bit_path
    file copy -force $source_hwh $hwh_path
    foreach artifact [list $bit_path $hwh_path] {
        if {![file isfile $artifact] || [file size $artifact] == 0} {
            error "Generated artifact is missing or empty: $artifact"
        }
    }

    set metadata_path [file join $report_dir build_metadata.txt]
    set metadata [open $metadata_path w]
    fconfigure $metadata -translation lf
    puts $metadata "schema=zephyr.accelerator.full.build.v1"
    puts $metadata "hardware_source_commit=$hardware_commit"
    puts $metadata "vivado_version=[version -short]"
    puts $metadata "part=$expected_part"
    puts $metadata "top=$expected_top"
    puts $metadata "fclk0_mhz=100"
    puts $metadata "route_checkpoint=$route_checkpoint"
    puts $metadata "same_project_hwh_source=$source_hwh"
    puts $metadata "setup_wns_ns=$setup_wns"
    puts $metadata "setup_margin_target_ns=$setup_margin_target_ns"
    puts $metadata "setup_guardbanded_wns_ns=$setup_guardbanded_wns"
    puts $metadata "setup_failing_endpoints=$setup_failures"
    puts $metadata "hold_guardbanded_whs_ns=$hold_guardbanded_whs"
    puts $metadata "hold_guardband_ns=$hold_guardband_ns"
    puts $metadata "hold_raw_physical_margin_ns=$hold_raw_whs"
    puts $metadata "hold_failing_endpoints=$hold_failures"
    puts $metadata "unrouted_nets=$unrouted_nets"
    puts $metadata "partially_routed_nets=$partially_routed_nets"
    puts $metadata "drc_errors=$drc_errors"
    puts $metadata "drc_critical_warnings=$drc_critical_warnings"
    puts $metadata "drc_warnings=$drc_warnings"
    puts $metadata "resource_limit_percent=$resource_limit_percent"
    puts $metadata "slice_luts=$slice_luts"
    puts $metadata "slice_registers=$slice_registers"
    puts $metadata "ramb36_primitives=$ramb36_count"
    puts $metadata "ramb18_primitives=$ramb18_count"
    puts $metadata "bram36_equivalent=$bram_equiv"
    puts $metadata "dsp48_primitives=$dsp_count"
    puts $metadata "resources_below_limit=$resources_below_limit"
    puts $metadata "bitstream_bytes=[file size $bit_path]"
    puts $metadata "hwh_bytes=[file size $hwh_path]"
    puts $metadata "build_completed_utc=[clock format [clock seconds] -gmt true -format {%Y-%m-%dT%H:%M:%SZ}]"
    puts $metadata "write_bitstream_completed=YES"
    puts $metadata "hwh_copied_from_same_project=YES"
    puts $metadata "board_connected_during_build=NO"
    close $metadata

    set flow_ok 1
    close_design
} reason failure_options]} {
    puts stderr "ACCELERATOR_FULL_ARTIFACT_FATAL $reason"
    if {[dict exists $failure_options -errorinfo]} {
        puts stderr "ACCELERATOR_FULL_ARTIFACT_ERRORINFO [dict get $failure_options -errorinfo]"
    }
    catch {close_design}
    exit 1
}

if {!$flow_ok} {
    exit 2
}
puts "ACCELERATOR_FULL_ARTIFACT_GATE_PASS"
puts "ACCELERATOR_FULL_BITSTREAM_COMPLETE"
exit 0
