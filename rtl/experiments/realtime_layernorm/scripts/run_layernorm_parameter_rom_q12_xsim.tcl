if {$argc >= 1} {
    set repo_root [file normalize [lindex $argv 0]]
} else {
    error "repo root argument is required"
}
set experiment [file join $repo_root rtl experiments realtime_layernorm]
set rtl_file [file join $experiment layernorm_parameter_rom_q12.v]
set tb [file join $experiment tb tb_layernorm_parameter_rom_q12.v]
set vectors [file join $experiment data layernorm_parameter_rom_vectors.txt]
set include_dir [file join $experiment data]
foreach required [list $rtl_file $tb $vectors \
    [file join $include_dir layernorm_parameter_rom_q12_init.vh]] {
    if {![file isfile $required]} {
        error "Missing LayerNorm parameter ROM simulation input: $required"
    }
}
if {$tcl_platform(platform) eq "windows"} {
    set work_dir [file normalize [file join $::env(TEMP) zephyr_layernorm_rom_xsim_[pid]]]
} else {
    set work_dir [file join $repo_root rtl build realtime_layernorm_rom_xsim]
}
file delete -force $work_dir
file mkdir $work_dir
create_project layernorm_rom_sim $work_dir -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse $rtl_file
add_files -fileset sim_1 -norecurse $tb
set_property include_dirs $include_dir [get_filesets sources_1]
set_property include_dirs $include_dir [get_filesets sim_1]
set_property top tb_layernorm_parameter_rom_q12 [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set plusarg [format {-testplusarg VECTOR_PATH=%s} [file normalize $vectors]]
set_property -name xsim.simulate.xsim.more_options -value $plusarg \
    -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
set pass_value [get_value /tb_layernorm_parameter_rom_q12/test_passed]
if {$pass_value ne "1"} {
    error "LayerNorm parameter ROM test did not assert test_passed"
}
puts "LAYERNORM_PARAMETER_ROM_XSIM_GATE_PASS entries=362"
close_sim
close_project
