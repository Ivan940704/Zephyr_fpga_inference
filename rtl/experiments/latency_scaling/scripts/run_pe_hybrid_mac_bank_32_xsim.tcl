if {$argc >= 1} {
    set repo_root [file normalize [lindex $argv 0]]
} else {
    error "repo root argument is required"
}
set mac [file join $repo_root rtl pe_array baseline v1 rtl pe pe_hybrid_mac.sv]
set bank [file join $repo_root rtl experiments latency_scaling pe_hybrid_mac_bank_32.v]
set tb [file join $repo_root rtl experiments latency_scaling tb tb_pe_hybrid_mac_bank_32.sv]
foreach required [list $mac $bank $tb] {
    if {![file isfile $required]} {
        error "Missing 32-PE simulation input: $required"
    }
}
if {$tcl_platform(platform) eq "windows"} {
    set work_dir [file normalize [file join $::env(TEMP) zephyr_latency_32pe_xsim_[pid]]]
} else {
    set work_dir [file join $repo_root rtl build latency_32pe_xsim]
}
file delete -force $work_dir
file mkdir $work_dir
create_project latency_32pe_sim $work_dir -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse [list $mac $bank]
add_files -fileset sim_1 -norecurse $tb
set_property file_type SystemVerilog [get_files [list $mac $tb]]
set_property file_type Verilog [get_files $bank]
set_property top tb_pe_hybrid_mac_bank_32 [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
set pass_value [get_value /tb_pe_hybrid_mac_bank_32/test_passed]
if {$pass_value ne "1"} {
    error "32-lane arithmetic bank test did not assert test_passed"
}
puts "LATENCY_32PE_XSIM_PASS lanes=32 checked_results=64"
close_sim
close_project
