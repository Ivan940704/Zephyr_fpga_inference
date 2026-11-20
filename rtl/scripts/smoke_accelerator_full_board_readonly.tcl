# Read the accelerator identity and passive status registers through the Zynq
# debug access port.  This script deliberately performs no MMIO writes.

if {$argc < 1 || $argc > 2} {
    error "usage: smoke_accelerator_full_board_readonly.tcl <output_report> ?hw_server_url?"
}

set output_report [file normalize [lindex $argv 0]]
set hw_server_url [expr {$argc == 2 ? [lindex $argv 1] : "tcp:127.0.0.1:3121"}]

connect -url $hw_server_url

targets -set -filter {name == "APU"}

proc read_word {address} {
    return [mrd -force -value $address]
}

set control_base 0x43C00000
set image_version [read_word [expr {$control_base + 0x0A4}]]
set packet_bytes_0 [read_word [expr {$control_base + 0x038}]]
set packet_bytes_1 [read_word [expr {$control_base + 0x03C}]]
set status [read_word [expr {$control_base + 0x014}]]
set execution [read_word [expr {$control_base + 0x018}]]
set frame_id [read_word [expr {$control_base + 0x01C}]]
set state_cycles [read_word [expr {$control_base + 0x020}]]
set irq_status [read_word [expr {$control_base + 0x028}]]
set first_fault [read_word [expr {$control_base + 0x02C}]]
set first_fault_detail [read_word [expr {$control_base + 0x030}]]
set first_fault_frame [read_word [expr {$control_base + 0x034}]]
set control_error [read_word [expr {$control_base + 0x0A0}]]
set reset_status [read_word [expr {$control_base + 0x0A8}]]

set io_dma_base 0x40400000
set spectrum_dma_base 0x40410000
set io_dma_mm2s_control [read_word [expr {$io_dma_base + 0x000}]]
set io_dma_mm2s_status [read_word [expr {$io_dma_base + 0x004}]]
set io_dma_s2mm_control [read_word [expr {$io_dma_base + 0x030}]]
set io_dma_s2mm_status [read_word [expr {$io_dma_base + 0x034}]]
set spectrum_dma_mm2s_control [read_word [expr {$spectrum_dma_base + 0x000}]]
set spectrum_dma_mm2s_status [read_word [expr {$spectrum_dma_base + 0x004}]]

set expected_image_version 0x00050003
set expected_packet_bytes_0 0x02000200
set expected_packet_bytes_1 0x00000800
set identity_verified [expr {
    $image_version == $expected_image_version &&
    $packet_bytes_0 == $expected_packet_bytes_0 &&
    $packet_bytes_1 == $expected_packet_bytes_1
}]

file mkdir [file dirname $output_report]
set report [open $output_report w]
puts $report "schema=zephyr.accelerator.full.mmio.readonly.v2"
puts $report "transport=XSCT_JTAG_DAP"
puts $report [format "control_base=0x%08X" $control_base]
puts $report "target=APU/AHB-AP0"
puts $report [format "image_version=0x%08X" $image_version]
puts $report [format "packet_bytes_0=0x%08X" $packet_bytes_0]
puts $report [format "packet_bytes_1=0x%08X" $packet_bytes_1]
puts $report [format "status=0x%08X" $status]
puts $report [format "execution=0x%08X" $execution]
puts $report [format "frame_id=0x%08X" $frame_id]
puts $report [format "state_cycles=0x%08X" $state_cycles]
puts $report [format "irq_status=0x%08X" $irq_status]
puts $report [format "first_fault=0x%08X" $first_fault]
puts $report [format "first_fault_detail=0x%08X" $first_fault_detail]
puts $report [format "first_fault_frame=0x%08X" $first_fault_frame]
puts $report [format "control_error=0x%08X" $control_error]
puts $report [format "reset_status=0x%08X" $reset_status]
puts $report [format "io_dma_mm2s_control=0x%08X" $io_dma_mm2s_control]
puts $report [format "io_dma_mm2s_status=0x%08X" $io_dma_mm2s_status]
puts $report [format "io_dma_s2mm_control=0x%08X" $io_dma_s2mm_control]
puts $report [format "io_dma_s2mm_status=0x%08X" $io_dma_s2mm_status]
puts $report [format "spectrum_dma_mm2s_control=0x%08X" $spectrum_dma_mm2s_control]
puts $report [format "spectrum_dma_mm2s_status=0x%08X" $spectrum_dma_mm2s_status]
puts $report "identity_verified=[expr {$identity_verified ? "YES" : "NO"}]"
puts $report "mmio_writes=0"
puts $report "completed_utc=[clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]"
close $report

disconnect
if {!$identity_verified} {
    error "accelerator identity mismatch; see $output_report"
}
puts "ACCELERATOR_FULL_READONLY_SMOKE_PASS report=$output_report"
exit
