# Generate the Stage-2-only parameter-BRAM hardware handoff from a freshly
# routed PYNQ-Z1 project.  The project is created and routed by the existing
# create/implementation Tcl pair before this script is invoked.

if {$argc >= 1} {
    set rtl_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set rtl_root [file normalize [file join $script_dir ..]]
}
if {$argc >= 2} {
    set artifact_dir [file normalize [lindex $argv 1]]
} else {
    set artifact_dir [file normalize [file join [file dirname $rtl_root] artifacts]]
}
if {$argc >= 3} {
    set design_commit [lindex $argv 2]
} else {
    set design_commit UNKNOWN
}

set part_name xc7z020clg400-1
set expected_board_part www.digilentinc.com:pynq-z1:part0:1.0
set project_dir [file join [file dirname $rtl_root] zpb_bd]
set project_file [file join $project_dir zpb.xpr]
set report_dir [file join $rtl_root reports parameter_bram_board_stage2]
set artifact_basename parameter_bram_stage2
file mkdir $artifact_dir
file mkdir $report_dir

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

proc count_blocking_drc {} {
    set count 0
    foreach violation [get_drc_violations -quiet] {
        set severity [get_property SEVERITY $violation]
        if {$severity eq "Error" || $severity eq "Critical Warning"} {
            incr count
        }
    }
    return $count
}

set flow_ok 0
if {[catch {
    if {![file exists $project_file]} {
        error "Missing recreated block-design project: $project_file"
    }
    open_project $project_file
    if {[get_property PART [current_project]] ne $part_name} {
        error "Project part mismatch: [get_property PART [current_project]]"
    }
    if {[get_property BOARD_PART [current_project]] ne $expected_board_part} {
        error "PYNQ-Z1 board part mismatch: [get_property BOARD_PART [current_project]]"
    }
    set impl_status [get_property STATUS [get_runs impl_1]]
    if {![string match "*route_design Complete*" $impl_status]} {
        error "Implementation is not at route_design Complete: $impl_status"
    }

    open_run impl_1
    set setup_slack [worst_slack max]
    set hold_slack [worst_slack min]
    set setup_fail [failing_timing_metrics max]
    set hold_fail [failing_timing_metrics min]

    report_timing_summary -delay_type min_max -max_paths 10 \
        -report_unconstrained \
        -file [file join $report_dir timing_summary_post_route.rpt]
    check_timing -verbose -file [file join $report_dir check_timing_post_route.rpt]
    report_route_status -file [file join $report_dir route_status_post_route.rpt]
    report_drc -file [file join $report_dir drc_post_route.rpt]
    report_methodology -file [file join $report_dir methodology_post_route.rpt]
    report_utilization -hierarchical \
        -file [file join $report_dir utilization_post_route.rpt]

    set blocking_drc [count_blocking_drc]
    set unrouted_nets [llength [get_nets -quiet -hierarchical \
        -filter {ROUTE_STATUS == UNROUTED}]]
    if {$setup_slack eq "NA" || double($setup_slack) < 0.0 || \
        [lindex $setup_fail 0] != 0} {
        error "Post-route setup gate failed: WNS=$setup_slack failures=[lindex $setup_fail 0]"
    }
    if {$hold_slack eq "NA" || double($hold_slack) < 0.0 || \
        [lindex $hold_fail 0] != 0} {
        error "Post-route hold gate failed: WHS=$hold_slack failures=[lindex $hold_fail 0]"
    }
    if {$blocking_drc != 0} {
        error "Post-route DRC has $blocking_drc blocking violations"
    }
    if {$unrouted_nets != 0} {
        error "Post-route design has $unrouted_nets unrouted nets"
    }

    set bit_path [file join $artifact_dir ${artifact_basename}.bit]
    set hwh_path [file join $artifact_dir ${artifact_basename}.hwh]
    set ltx_path [file join $artifact_dir ${artifact_basename}.ltx]
    write_bitstream -force $bit_path
    write_debug_probes -force $ltx_path

    set generated_hwh [file join $project_dir zpb.srcs sources_1 bd zpb \
        hw_handoff zpb.hwh]
    if {![file exists $generated_hwh]} {
        error "Matching Vivado hw_handoff is missing: $generated_hwh"
    }
    file copy -force $generated_hwh $hwh_path
    foreach required [list $bit_path $hwh_path $ltx_path] {
        if {![file exists $required] || [file size $required] == 0} {
            error "Generated artifact is missing or empty: $required"
        }
    }

    set metadata [open [file join $report_dir build_metadata.txt] w]
    puts $metadata "schema=zephyr.parameter_bram.stage2.build.v1"
    puts $metadata "hardware_source_commit=$design_commit"
    puts $metadata "vivado_version=[version -short]"
    puts $metadata "vivado_version_full=[version]"
    puts $metadata "part=$part_name"
    puts $metadata "board_part=[get_property BOARD_PART [current_project]]"
    puts $metadata "top=zpb_wrapper"
    puts $metadata "fclk0_mhz=100"
    puts $metadata "implementation_status=$impl_status"
    puts $metadata "setup_wns_ns=$setup_slack"
    puts $metadata "setup_tns_ns=[lindex $setup_fail 1]"
    puts $metadata "setup_failing_endpoints=[lindex $setup_fail 0]"
    puts $metadata "hold_whs_ns=$hold_slack"
    puts $metadata "hold_ths_ns=[lindex $hold_fail 1]"
    puts $metadata "hold_failing_endpoints=[lindex $hold_fail 0]"
    puts $metadata "blocking_drc_violations=$blocking_drc"
    puts $metadata "unrouted_nets=$unrouted_nets"
    puts $metadata "artifact_basename=$artifact_basename"
    puts $metadata "bitstream_bytes=[file size $bit_path]"
    puts $metadata "hwh_bytes=[file size $hwh_path]"
    puts $metadata "ltx_bytes=[file size $ltx_path]"
    puts $metadata "build_completed_utc=[clock format [clock seconds] -gmt true -format {%Y-%m-%dT%H:%M:%SZ}]"
    puts $metadata "write_bitstream_completed=YES"
    puts $metadata "hwh_copied_from_same_project=YES"
    puts $metadata "write_debug_probes_completed=YES"
    puts $metadata "board_connected=NO"
    close $metadata

    set flow_ok 1
    close_project
} reason failure_options]} {
    puts stderr "PARAMETER_BRAM_BITSTREAM_FATAL $reason"
    if {[dict exists $failure_options -errorinfo]} {
        puts stderr "PARAMETER_BRAM_BITSTREAM_ERRORINFO [dict get $failure_options -errorinfo]"
    }
    set failure_report [open [file join $report_dir bitstream_failure.txt] w]
    puts $failure_report "hardware_source_commit=$design_commit"
    puts $failure_report "failure=$reason"
    puts $failure_report "board_connected=NO"
    close $failure_report
    catch {close_project}
    exit 1
}

if {!$flow_ok} {
    exit 2
}
puts "PARAMETER_BRAM_STAGE2_BITSTREAM_COMPLETE"
puts "PARAMETER_BRAM_STAGE2_BOARD_NOT_CONNECTED"
exit 0
