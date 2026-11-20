if {$argc >= 1} {
    set repo_root [file normalize [lindex $argv 0]]
} else {
    error "repo root argument is required"
}
set experiment [file join $repo_root rtl experiments realtime_layernorm]
set include_dir [file join $experiment data]
set engine [file join $experiment layernorm_engine_q12.v]
set parameter_rom [file join $experiment layernorm_parameter_rom_q12.v]
set coordinator [file join $experiment realtime_layernorm_coordinator.v]
set tb [file join $experiment tb tb_realtime_layernorm_coordinator.v]
set vectors [file join $experiment tb realtime_layernorm_coordinator_vectors.txt]
foreach required [list $engine $parameter_rom $coordinator $tb $vectors \
    [file join $include_dir layernorm_parameter_rom_q12_init.vh] \
    [file join $include_dir projection_dequant_q12_init.vh] \
    [file join $include_dir subband_source_index_init.vh]] {
    if {![file isfile $required]} {
        error "Missing real-time coordinator simulation input: $required"
    }
}
if {$tcl_platform(platform) eq "windows"} {
    set work_dir [file normalize [file join $::env(TEMP) zephyr_realtime_coordinator_xsim_[pid]]]
} else {
    set work_dir [file join $repo_root rtl build realtime_coordinator_xsim]
}
file delete -force $work_dir
file mkdir $work_dir
create_project realtime_coordinator_sim $work_dir -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse [list $engine $parameter_rom $coordinator]
add_files -fileset sim_1 -norecurse $tb
set_property include_dirs $include_dir [get_filesets sources_1]
set_property include_dirs $include_dir [get_filesets sim_1]
set_property top tb_realtime_layernorm_coordinator [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set plusarg [format {-testplusarg VECTOR_PATH=%s} [file normalize $vectors]]
set_property -name xsim.simulate.xsim.more_options -value $plusarg \
    -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
set pass_value [get_value /tb_realtime_layernorm_coordinator/test_passed]
if {$pass_value ne "1"} {
    error "Real-time LayerNorm coordinator did not assert test_passed"
}
puts "REALTIME_COORDINATOR_XSIM_GATE_PASS frames=3"
close_sim
close_project
