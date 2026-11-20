if {$argc >= 1} {
    set repo_root [file normalize [lindex $argv 0]]
} else {
    error "repo root argument is required"
}
set experiment [file join $repo_root rtl experiments realtime_layernorm]
set engine [file join $experiment layernorm_engine_q12.v]
set tb [file join $experiment tb tb_layernorm_engine_q12.v]
set vectors [file join $experiment tb layernorm_q12_vectors.txt]
foreach required [list $engine $tb $vectors] {
    if {![file isfile $required]} {
        error "Missing LayerNorm simulation input: $required"
    }
}
if {$tcl_platform(platform) eq "windows"} {
    set work_dir [file normalize [file join $::env(TEMP) zephyr_layernorm_q12_xsim_[pid]]]
} else {
    set work_dir [file join $repo_root rtl build realtime_layernorm_q12_xsim]
}
file delete -force $work_dir
file mkdir $work_dir
create_project layernorm_q12_sim $work_dir -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse $engine
add_files -fileset sim_1 -norecurse $tb
set_property file_type Verilog [get_files [list $engine $tb]]
set_property top tb_layernorm_engine_q12 [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set plusarg [format {-testplusarg VECTOR_PATH=%s} [file normalize $vectors]]
set_property -name xsim.simulate.xsim.more_options -value $plusarg \
    -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
set pass_value [get_value /tb_layernorm_engine_q12/test_passed]
if {$pass_value ne "1"} {
    error "LayerNorm Q12 test did not assert test_passed"
}
set vector_count_value [get_value /tb_layernorm_engine_q12/vector_count]
puts "LAYER_NORM_Q12_XSIM_GATE_PASS vectors=$vector_count_value"
close_sim
close_project
