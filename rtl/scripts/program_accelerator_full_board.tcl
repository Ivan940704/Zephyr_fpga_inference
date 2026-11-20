# Program one explicitly named PYNQ-Z1 JTAG target and verify configuration
# status.  The script never selects the first available target implicitly.

if {$argc != 3} {
    puts stderr "Usage: program_accelerator_full_board.tcl <bitstream> <report> <exact-jtag-target>"
    exit 64
}

set bitstream [file normalize [lindex $argv 0]]
set report_path [file normalize [lindex $argv 1]]
set expected_target [lindex $argv 2]
set expected_part xc7z020
file mkdir [file dirname $report_path]

set hw_open 0
set target_open 0
set report [open $report_path w]
fconfigure $report -translation lf
puts $report "schema=zephyr.accelerator.full.program.v1"
puts $report "expected_jtag_target=$expected_target"
puts $report "expected_part=$expected_part"
puts $report "bitstream=$bitstream"

if {[catch {
    if {![file isfile $bitstream] || [file size $bitstream] == 0} {
        error "Bitstream is missing or empty: $bitstream"
    }
    puts $report "bitstream_bytes=[file size $bitstream]"

    open_hw
    set hw_open 1
    connect_hw_server
    set targets [get_hw_targets -quiet]
    set matching_targets [list]
    foreach target $targets {
        if {[get_property NAME $target] eq $expected_target} {
            lappend matching_targets $target
        }
    }
    if {[llength $matching_targets] != 1} {
        error "Expected one exact JTAG target '$expected_target', found [llength $matching_targets] among [llength $targets] total"
    }
    current_hw_target [lindex $matching_targets 0]
    open_hw_target
    set target_open 1

    set matching_devices [list]
    foreach device [get_hw_devices -quiet] {
        if {[get_property PART $device] eq $expected_part} {
            lappend matching_devices $device
        }
    }
    if {[llength $matching_devices] != 1} {
        error "Expected one $expected_part device, found [llength $matching_devices]"
    }
    set fpga [lindex $matching_devices 0]
    set fpga_name [get_property NAME $fpga]
    puts $report "observed_jtag_target=[get_property NAME [current_hw_target]]"
    puts $report "observed_device=$fpga_name"
    puts $report "observed_part=[get_property PART $fpga]"
    puts $report "done_internal_before=[get_property REGISTER.CONFIG_STATUS.BIT13_DONE_INTERNAL_SIGNAL_STATUS $fpga]"
    puts $report "done_pin_before=[get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $fpga]"

    set_property PROGRAM.FILE $bitstream $fpga
    program_hw_devices $fpga
    refresh_hw_device $fpga

    set done_internal [get_property REGISTER.CONFIG_STATUS.BIT13_DONE_INTERNAL_SIGNAL_STATUS $fpga]
    set done_pin [get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $fpga]
    set ir_done [get_property REGISTER.IR.BIT5_DONE $fpga]
    set crc_error [get_property REGISTER.CONFIG_STATUS.BIT00_CRC_ERROR $fpga]
    set idcode_error [get_property REGISTER.CONFIG_STATUS.BIT15_IDCODE_ERROR $fpga]
    set security_error [get_property REGISTER.CONFIG_STATUS.BIT16_SECURITY_ERROR $fpga]
    if {$done_internal ne "1" || $done_pin ne "1" || $ir_done ne "1"} {
        error "FPGA DONE verification failed: internal=$done_internal pin=$done_pin ir=$ir_done"
    }
    if {$crc_error ne "0" || $idcode_error ne "0" || $security_error ne "0"} {
        error "FPGA status error: crc=$crc_error idcode=$idcode_error security=$security_error"
    }

    puts $report "done_internal_after=$done_internal"
    puts $report "done_pin_after=$done_pin"
    puts $report "ir_done_after=$ir_done"
    puts $report "crc_error_after=$crc_error"
    puts $report "idcode_error_after=$idcode_error"
    puts $report "security_error_after=$security_error"
    puts $report "program_completed_utc=[clock format [clock seconds] -gmt true -format {%Y-%m-%dT%H:%M:%SZ}]"
    puts $report "program_hw_devices_completed=YES"
    puts $report "configuration_status_verified=YES"
} reason failure_options]} {
    puts $report "program_hw_devices_completed=NO"
    puts $report "configuration_status_verified=NO"
    puts $report "failure=$reason"
    close $report
    if {$target_open} {catch {close_hw_target}}
    if {$hw_open} {
        catch {disconnect_hw_server}
        catch {close_hw}
    }
    puts stderr "ACCELERATOR_FULL_PROGRAM_FATAL $reason"
    if {[dict exists $failure_options -errorinfo]} {
        puts stderr "ACCELERATOR_FULL_PROGRAM_ERRORINFO [dict get $failure_options -errorinfo]"
    }
    exit 1
}

close $report
if {$target_open} {close_hw_target}
if {$hw_open} {
    disconnect_hw_server
    close_hw
}
puts "ACCELERATOR_FULL_PROGRAM_PASS"
exit 0

