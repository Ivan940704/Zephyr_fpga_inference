set script_dir [file dirname [string map {\\ /} [info script]]]
set repo_root [file join $script_dir .. .. .. .. ..]
set v2_root [file join $repo_root rtl pe_array production_v2]
set mac [file join $repo_root rtl pe_array baseline v1 rtl pe pe_hybrid_mac.sv]
set array [file join $v2_root rtl pe pe_hybrid_mac_array_32.v]
set tb [file join $v2_root tb unit tb_pe_hybrid_mac_array_32.v]
set report_dir [file join $repo_root rtl reports production_v2_pe_hybrid_mac_array_32]

foreach required [list $mac $array $tb] {
    if {![file isfile $required]} {
        error "Missing Phase 5A simulation input: $required"
    }
}

if {$tcl_platform(platform) eq "windows"} {
    # Vivado 2018.3/XSim can corrupt redirected Documents/AppData paths on
    # this host.  Use a short user-profile build path; reviewed sources and
    # reports remain under repo_root.
    set work_dir [file join $::env(USERPROFILE) zephyr_phase5a_xsim_[pid]]
} else {
    set work_dir [file join $repo_root rtl build production_v2_pe_hybrid_mac_array_32_xsim]
}
file delete -force $work_dir
file mkdir $work_dir
file mkdir $report_dir

create_project phase5a_xsim $work_dir -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse [list $mac $array]
add_files -fileset sim_1 -norecurse $tb
set_property file_type SystemVerilog [get_files $mac]
set_property file_type Verilog [get_files [list $array $tb]]
set_property top tb_pe_hybrid_mac_array_32 [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all

set pass_value [get_value /tb_pe_hybrid_mac_array_32/test_passed]
set failure_value [get_value /tb_pe_hybrid_mac_array_32/failures]
set cycle_value [get_value -radix unsigned /tb_pe_hybrid_mac_array_32/test_cycles]
set command_value [get_value -radix unsigned /tb_pe_hybrid_mac_array_32/accepted_commands]
set check_value [get_value -radix unsigned /tb_pe_hybrid_mac_array_32/checked_results]

set metrics [open [file join $report_dir xsim_metrics.txt] w]
fconfigure $metrics -translation lf
puts $metrics "evidence=Vivado_2018.3_XSim"
puts $metrics "top=tb_pe_hybrid_mac_array_32"
puts $metrics "lanes=32"
puts $metrics "test_passed=$pass_value"
puts $metrics "failures=$failure_value"
puts $metrics "cycles=$cycle_value"
puts $metrics "accepted_commands=$command_value"
puts $metrics "checked_lane_results=$check_value"
puts $metrics "command_to_accumulate_latency_cycles=1"
puts $metrics "initiation_interval_cycles=1"
close $metrics

if {$pass_value ne "1" || $failure_value ne "0"} {
    error "Phase 5A 32-lane production-array XSim failed"
}
puts "PHASE5A_XSIM_PASS lanes=32 cycles=$cycle_value commands=$command_value checks=$check_value latency_cycles=1 ii=1"
close_sim
close_project
exit 0
