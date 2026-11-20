# Vivado 2018.3 OOC implementation for the image-v5 32-row memory service.
# Arguments: <rtl_root> ?period_ns? ?report_tag?

if {$argc < 1} {
    error "Usage: synth_memory_service_v5_ooc.tcl <rtl_root> ?period_ns? ?report_tag?"
}
puts "MEMORY_SERVICE_V5_OOC_ARGS argc=$argc argv=$argv pwd=[pwd]"

set rtl_root [file normalize [lindex $argv 0]]
set part_name xc7z020clg400-1
set period_ns [expr {$argc >= 2 ? [lindex $argv 1] : 10.000}]
set report_tag [expr {$argc >= 3 ? [lindex $argv 2] : "100mhz"}]
set report_dir [file join $rtl_root reports memory_service_v5 $report_tag]
set build_dir [file join $rtl_root build implement memory_service_v5 $report_tag]
file delete -force $report_dir $build_dir
file mkdir $report_dir
file mkdir $build_dir

set rtl_files [list \
    [file join $rtl_root memory memory_wide256.v] \
    [file join $rtl_root memory model_memory_v5_table.v] \
    [file join $rtl_root memory memory_service_v5.v]]
foreach required $rtl_files {
    if {![file exists $required]} {
        error "Missing required file: $required"
    }
}

create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
set_property include_dirs [list $rtl_root] [current_fileset]
foreach rtl_file $rtl_files {
    read_verilog -sv $rtl_file
}
set xdc_file [file join $build_dir memory_service_v5_clock.xdc]
set xdc_handle [open $xdc_file w]
fconfigure $xdc_handle -translation lf
puts $xdc_handle "create_clock -name clk -period $period_ns \[get_ports clk\]"
puts $xdc_handle "set_property HD.CLK_SRC BUFGCTRL_X0Y0 \[get_ports clk\]"
close $xdc_handle
read_xdc $xdc_file
synth_design -top memory_service_v5 -part $part_name -mode out_of_context \
    -flatten_hierarchy rebuilt
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force [file join $build_dir memory_service_v5_post_route.dcp]
report_utilization -hierarchical \
    -file [file join $report_dir utilization_post_route.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary_post_route.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group \
    -file [file join $report_dir timing_paths_post_route.rpt]
report_route_status -file [file join $report_dir route_status_post_route.rpt]
report_drc -file [file join $report_dir drc_post_route.rpt]
check_timing -verbose -file [file join $report_dir check_timing_post_route.rpt]

set lut_count [llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]
set ff_count [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]
set ramb36_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB36E1}]]
set ramb18_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB18E1}]]
set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]]

set setup_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
set wns_ns [expr {[llength $setup_paths] ? [get_property SLACK $setup_paths] : "NA"}]
set whs_ns [expr {[llength $hold_paths] ? [get_property SLACK $hold_paths] : "NA"}]
set route_errors [get_property ROUTE_STATUS [current_design]]
set timing_met [expr {$wns_ns ne "NA" && $whs_ns ne "NA" && $wns_ns >= 0.0 && $whs_ns >= 0.0}]

set metrics [open [file join $report_dir metrics_post_route.txt] w]
puts $metrics "top=memory_service_v5"
puts $metrics "part=$part_name"
puts $metrics "target_period_ns=$period_ns"
puts $metrics "wns_ns=$wns_ns"
puts $metrics "whs_ns=$whs_ns"
puts $metrics "timing_met=$timing_met"
puts $metrics "route_status=$route_errors"
puts $metrics "lut_primitives=$lut_count"
puts $metrics "ff_primitives=$ff_count"
puts $metrics "ramb36_primitives=$ramb36_count"
puts $metrics "ramb18_primitives=$ramb18_count"
puts $metrics "dsp48_primitives=$dsp_count"
close $metrics

puts "MEMORY_SERVICE_V5_OOC tag=$report_tag wns_ns=$wns_ns whs_ns=$whs_ns"
puts "MEMORY_SERVICE_V5_OOC lut=$lut_count ff=$ff_count ramb36=$ramb36_count ramb18=$ramb18_count dsp=$dsp_count"
if {!$timing_met} {
    puts stderr "MEMORY_SERVICE_V5_OOC_TIMING_FAIL"
    exit 2
}
if {$ramb36_count != 64} {
    puts stderr "MEMORY_SERVICE_V5_OOC_RAM_FAIL expected=64 actual=$ramb36_count"
    exit 3
}
puts "MEMORY_SERVICE_V5_OOC_PASS"
exit 0
