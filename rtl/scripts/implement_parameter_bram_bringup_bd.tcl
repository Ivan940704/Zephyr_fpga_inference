# Complete PYNQ-Z1 parameter-BRAM block-design implementation flow.
#
# Usage:
#   vivado -mode batch -source implement_parameter_bram_bringup_bd.tcl \
#          -tclargs <staged-rtl-root> <design-baseline-commit>
#
# The project must first be recreated by create_parameter_bram_bringup_bd.tcl.
# This flow explicitly stops at route_design.  It never invokes
# write_bitstream, write_hw_platform, or export_hardware.

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

set part_name xc7z020clg400-1
set period_ns 10.000
set project_dir [file join [file dirname $rtl_root] zpb_bd]
set project_file [file join $project_dir zpb.xpr]
set report_dir [file join $rtl_root reports parameter_bram_implementation]
set checkpoint_dir [file join [file dirname $rtl_root] zpb_implementation_checkpoints]
file mkdir $report_dir
file mkdir $checkpoint_dir

if {![file exists $project_file]} {
    error "Missing recreated block-design project: $project_file"
}
set report_failures [list]

proc run_required_report {label command_words} {
    global report_failures
    if {[catch {uplevel #0 $command_words} reason]} {
        lappend report_failures "$label: $reason"
        puts stderr "PARAMETER_BRAM_REPORT_ERROR label=$label reason=$reason"
    } else {
        puts "PARAMETER_BRAM_REPORT_PASS label=$label"
    }
}

proc worst_slack {delay_type} {
    set paths [get_timing_paths -quiet -delay_type $delay_type -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} {
        return NA
    }
    return [get_property SLACK [lindex $paths 0]]
}

proc failing_timing_metrics {delay_type} {
    set paths [get_timing_paths -quiet -delay_type $delay_type -max_paths 10000 \
        -nworst 1 -slack_lesser_than 0.0]
    set total 0.0
    foreach path $paths {
        set total [expr {$total + double([get_property SLACK $path])}]
    }
    return [list [llength $paths] $total]
}

proc primitive_count {primitive_cells expression} {
    return [llength [filter $primitive_cells $expression]]
}

proc write_scope_metrics {channel label name_pattern} {
    set cells [get_cells -quiet -hierarchical -filter \
        "IS_PRIMITIVE && NAME =~ $name_pattern"]
    puts $channel "${label}_primitive_total=[llength $cells]"
    puts $channel "${label}_lut=[primitive_count $cells {REF_NAME =~ LUT*}]"
    puts $channel "${label}_ff=[primitive_count $cells {REF_NAME =~ FD*}]"
    puts $channel "${label}_ramb36=[primitive_count $cells {REF_NAME == RAMB36E1}]"
    puts $channel "${label}_ramb18=[primitive_count $cells {REF_NAME == RAMB18E1}]"
    puts $channel "${label}_dsp=[primitive_count $cells {REF_NAME =~ DSP48*}]"
}

set flow_ok 0
if {[catch {
    open_project $project_file
    if {[get_property PART [current_project]] ne $part_name} {
        error "Project part mismatch: [get_property PART [current_project]]"
    }
    set_property top zpb_wrapper [get_filesets sources_1]
    update_compile_order -fileset sources_1

    set synth_status_before [get_property STATUS [get_runs synth_1]]
    if {![string match "*Not started*" $synth_status_before]} {
        error "Expected a clean synthesis run, got: $synth_status_before"
    }
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    set synth_status [get_property STATUS [get_runs synth_1]]
    if {![string match "*Complete*" $synth_status]} {
        error "Synthesis did not complete: $synth_status"
    }

    open_run synth_1
    write_checkpoint -force [file join $checkpoint_dir zpb_post_synth.dcp]
    run_required_report post_synth_utilization [list report_utilization \
        -hierarchical -file [file join $report_dir utilization_post_synth.rpt]]
    run_required_report post_synth_timing [list report_timing_summary \
        -delay_type min_max -max_paths 3 -report_unconstrained \
        -file [file join $report_dir timing_summary_post_synth.rpt]]
    close_design

    set impl_status_before [get_property STATUS [get_runs impl_1]]
    if {![string match "*Not started*" $impl_status_before]} {
        error "Expected a clean implementation run, got: $impl_status_before"
    }
    # This is the terminal implementation action for the checkpoint.
    launch_runs impl_1 -to_step route_design -jobs 4
    wait_on_run impl_1
    set impl_status [get_property STATUS [get_runs impl_1]]
    if {![string match "*route_design Complete*" $impl_status]} {
        error "Implementation did not complete route_design: $impl_status"
    }

    open_run impl_1
    write_checkpoint -force [file join $checkpoint_dir zpb_post_route.dcp]

    run_required_report post_route_utilization [list report_utilization \
        -hierarchical -file [file join $report_dir utilization_post_route.rpt]]
    run_required_report post_route_timing_summary [list report_timing_summary \
        -delay_type min_max -max_paths 3 -report_unconstrained \
        -file [file join $report_dir timing_summary_post_route.rpt]]
    run_required_report post_route_setup_paths [list report_timing \
        -delay_type max -max_paths 3 -sort_by group \
        -file [file join $report_dir worst_setup_paths_post_route.rpt]]
    run_required_report post_route_hold_paths [list report_timing \
        -delay_type min -max_paths 3 -sort_by group \
        -file [file join $report_dir worst_hold_paths_post_route.rpt]]
    run_required_report post_route_check_timing [list check_timing -verbose \
        -file [file join $report_dir check_timing_post_route.rpt]]
    run_required_report post_route_clocks [list report_clocks \
        -file [file join $report_dir clocks_post_route.rpt]]
    run_required_report post_route_clock_utilization [list report_clock_utilization \
        -file [file join $report_dir clock_utilization_post_route.rpt]]
    run_required_report post_route_clock_interaction [list report_clock_interaction \
        -delay_type min_max \
        -file [file join $report_dir clock_interaction_post_route.rpt]]
    run_required_report post_route_bus_skew [list report_bus_skew \
        -file [file join $report_dir bus_skew_post_route.rpt]]
    run_required_report post_route_cdc [list report_cdc -details \
        -file [file join $report_dir cdc_post_route.rpt]]
    run_required_report post_route_route_status [list report_route_status \
        -file [file join $report_dir route_status_post_route.rpt]]
    run_required_report post_route_congestion [list report_design_analysis \
        -congestion -file [file join $report_dir congestion_post_route.rpt]]
    run_required_report post_route_drc [list report_drc \
        -file [file join $report_dir drc_post_route.rpt]]
    run_required_report post_route_methodology [list report_methodology \
        -file [file join $report_dir methodology_post_route.rpt]]
    run_required_report post_route_high_fanout [list report_high_fanout_nets \
        -timing -file [file join $report_dir high_fanout_post_route.rpt]]
    set constraint_report [open [file join $report_dir constraint_inventory.txt] w]
    puts $constraint_report "current_clocks=[join [get_clocks -quiet] ,]"
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
    set primitive_cells [get_cells -quiet -hierarchical -filter {IS_PRIMITIVE}]
    set raw_cache_brams [filter $primitive_cells \
        {REF_NAME == RAMB36E1 && NAME =~ *zpb_i/mem/inst/service/raw_cache/bram_reg*}]
    set preserved_raw_cache_brams 0
    set power_opted_raw_cache_brams 0
    foreach raw_cache_bram $raw_cache_brams {
        set dont_touch_value [get_property DONT_TOUCH $raw_cache_bram]
        if {$dont_touch_value eq "1" || [string equal -nocase $dont_touch_value "true"]} {
            incr preserved_raw_cache_brams
        }
        if {[get_property POWER_OPTED_CE $raw_cache_bram] ne ""} {
            incr power_opted_raw_cache_brams
        }
    }

    set metrics [open [file join $report_dir metrics_post_route.txt] w]
    puts $metrics "evidence=full_block_design_post_route"
    puts $metrics "vivado_version=[version -short]"
    puts $metrics "design_baseline_commit=$design_commit"
    puts $metrics "part=$part_name"
    puts $metrics "board_part=[get_property BOARD_PART [current_project]]"
    puts $metrics "top=zpb_wrapper"
    puts $metrics "target_period_ns=$period_ns"
    puts $metrics "synthesis_status=$synth_status"
    puts $metrics "implementation_status=$impl_status"
    puts $metrics "setup_wns_ns=$setup_slack"
    puts $metrics "setup_failing_endpoints=[lindex $setup_fail 0]"
    puts $metrics "setup_tns_ns=[lindex $setup_fail 1]"
    puts $metrics "hold_whs_ns=$hold_slack"
    puts $metrics "hold_failing_endpoints=[lindex $hold_fail 0]"
    puts $metrics "hold_ths_ns=[lindex $hold_fail 1]"
    puts $metrics "lut_primitives=[primitive_count $primitive_cells {REF_NAME =~ LUT*}]"
    puts $metrics "ff_primitives=[primitive_count $primitive_cells {REF_NAME =~ FD*}]"
    puts $metrics "ramb36_primitives=[primitive_count $primitive_cells {REF_NAME == RAMB36E1}]"
    puts $metrics "ramb18_primitives=[primitive_count $primitive_cells {REF_NAME == RAMB18E1}]"
    puts $metrics "dsp48_primitives=[primitive_count $primitive_cells {REF_NAME =~ DSP48*}]"
    puts $metrics "raw_cache_ramb36=[llength $raw_cache_brams]"
    puts $metrics "raw_cache_dont_touch=$preserved_raw_cache_brams"
    puts $metrics "raw_cache_power_opted_ce=$power_opted_raw_cache_brams"
    puts $metrics "raw_cache_coolgate_nets=[llength [get_nets -quiet -hierarchical -filter {NAME =~ *zpb_i/mem/inst/service/raw_cache*cooolgate*}]]"
    write_scope_metrics $metrics memory_scope "*zpb_i/mem/*"
    write_scope_metrics $metrics memory_service_scope "*zpb_i/mem/inst/service/*"
    write_scope_metrics $metrics axil_wrapper_scope "*zpb_i/mem/inst/control/*"
    write_scope_metrics $metrics ila_scope "*zpb_i/ila/*"
    write_scope_metrics $metrics debug_hub_scope "*dbg_hub*"
    write_scope_metrics $metrics control_interconnect_scope "*zpb_i/ctl_ic/*"
    write_scope_metrics $metrics hp_interconnect_scope "*zpb_i/hp_ic/*"
    puts $metrics "required_report_failures=[llength $report_failures]"
    foreach failure $report_failures {
        puts $metrics "report_failure=$failure"
    }
    puts $metrics "post_synth_checkpoint=[file join $checkpoint_dir zpb_post_synth.dcp]"
    puts $metrics "post_route_checkpoint=[file join $checkpoint_dir zpb_post_route.dcp]"
    puts $metrics "implementation_terminal_step=route_design"
    puts $metrics "write_bitstream_invoked=NO"
    puts $metrics "hwh_requested=NO"
    puts $metrics "board_connected=NO"
    close $metrics

    set flow_ok [expr {[llength $report_failures] == 0}]
    close_project
} reason failure_options]} {
    puts stderr "PARAMETER_BRAM_IMPLEMENTATION_FATAL $reason"
    if {[dict exists $failure_options -errorinfo]} {
        puts stderr "PARAMETER_BRAM_IMPLEMENTATION_ERRORINFO [dict get $failure_options -errorinfo]"
    }
    set failure_report [open [file join $report_dir flow_failure.txt] w]
    puts $failure_report "evidence=full_block_design_implementation_attempt"
    puts $failure_report "design_baseline_commit=$design_commit"
    puts $failure_report "part=$part_name"
    puts $failure_report "failure=$reason"
    puts $failure_report "write_bitstream_invoked=NO"
    puts $failure_report "board_connected=NO"
    close $failure_report
    catch {close_project}
    exit 1
}

if {!$flow_ok} {
    puts stderr "PARAMETER_BRAM_IMPLEMENTATION_REPORTS_INCOMPLETE"
    exit 2
}
puts "PARAMETER_BRAM_IMPLEMENTATION_ROUTE_COMPLETE"
puts "PARAMETER_BRAM_IMPLEMENTATION_BITSTREAM_NOT_RUN"
exit 0
