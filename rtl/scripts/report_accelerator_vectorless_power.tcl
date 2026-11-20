# Produce a Vivado vectorless estimate from a routed accelerator checkpoint.
# This is tool-estimate evidence only; it must never be labelled as a physical
# board power measurement.

if {$argc != 3} {
    puts stderr "Usage: report_accelerator_vectorless_power.tcl <route-dcp> <report-dir> <hardware-commit>"
    exit 64
}

set route_checkpoint [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
set hardware_commit [lindex $argv 2]
set expected_part xc7z020clg400-1

file mkdir $report_dir
set flow_ok 0
if {[catch {
    if {![file isfile $route_checkpoint] || [file size $route_checkpoint] == 0} {
        error "Routed checkpoint is missing or empty: $route_checkpoint"
    }
    if {![regexp {^[0-9a-f]{40}$} $hardware_commit]} {
        error "Hardware commit must be a full 40-character lowercase Git hash"
    }

    open_checkpoint $route_checkpoint
    if {[get_property PART [current_design]] ne $expected_part} {
        error "Checkpoint part mismatch: [get_property PART [current_design]]"
    }
    set top_instances [get_cells -quiet zephyr_full_i]
    if {[llength $top_instances] != 1 ||
        [get_property REF_NAME [lindex $top_instances 0]] ne "zephyr_full"} {
        error "Checkpoint does not contain the expected zephyr_full_wrapper structure"
    }
    set target_clock [get_clocks -quiet clk_fpga_0]
    if {[llength $target_clock] != 1} {
        error "Expected exactly one clk_fpga_0, found [llength $target_clock]"
    }

    set report_path [file join $report_dir vectorless_power_post_route.rpt]
    report_power -file $report_path
    if {![file isfile $report_path] || [file size $report_path] == 0} {
        error "Vivado power report is missing or empty"
    }

    set metadata_path [file join $report_dir vectorless_power_metadata.txt]
    set metadata [open $metadata_path w]
    fconfigure $metadata -translation lf
    puts $metadata "schema=zephyr.accelerator.vectorless-power.v1"
    puts $metadata "evidence=Vivado_2018.3_post_route_vectorless_estimate"
    puts $metadata "hardware_source_commit=$hardware_commit"
    puts $metadata "vivado_version=[version -short]"
    puts $metadata "part=$expected_part"
    puts $metadata "clock=clk_fpga_0"
    puts $metadata "clock_period_ns=[get_property PERIOD $target_clock]"
    puts $metadata "activity_input=Vivado_vectorless_defaults"
    puts $metadata "saif_or_vcd_applied=NO"
    puts $metadata "physical_board_measurement=NO"
    puts $metadata "external_meter_trace=NONE"
    puts $metadata "report_power_completed=YES"
    puts $metadata "completed_utc=[clock format [clock seconds] -gmt true -format {%Y-%m-%dT%H:%M:%SZ}]"
    close $metadata

    set flow_ok 1
    close_design
} reason failure_options]} {
    puts stderr "ACCELERATOR_VECTORLESS_POWER_FATAL $reason"
    if {[dict exists $failure_options -errorinfo]} {
        puts stderr "ACCELERATOR_VECTORLESS_POWER_ERRORINFO [dict get $failure_options -errorinfo]"
    }
    catch {close_design}
    exit 1
}

if {!$flow_ok} {
    exit 2
}
puts "ACCELERATOR_VECTORLESS_POWER_PASS"
exit 0
