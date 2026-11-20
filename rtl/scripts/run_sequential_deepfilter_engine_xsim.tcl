# Vivado 2018.3/XSim self-checking regression for the sequential DeepFilter
# engine. Argument: <repo_root>
if {$argc < 1} {
    error "Usage: run_sequential_deepfilter_engine_xsim.tcl <repo_root>"
}
set repo_root [lindex $argv 0]
set rtl_root [file join $repo_root rtl]
set work_dir [file join $rtl_root build xsim sequential_deepfilter_engine_[pid]]
set sources [list \
    [file join $rtl_root leaf deepfilter_complex_mac.v] \
    [file join $rtl_root integration sequential_deepfilter_engine.v]]
set tb [file join $rtl_root tb tb_sequential_deepfilter_engine.sv]

foreach required [concat $sources [list $tb]] {
    if {![file isfile $required]} {
        error "Missing sequential DeepFilter XSim input: $required"
    }
}

file delete -force $work_dir
file mkdir $work_dir
create_project sequential_deepfilter_engine_sim $work_dir \
    -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse $sources
add_files -fileset sim_1 -norecurse $tb
set_property file_type Verilog [get_files $sources]
set_property file_type SystemVerilog [get_files $tb]
set_property top tb_sequential_deepfilter_engine [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation
run all
set checks [get_value /tb_sequential_deepfilter_engine/checks]
if {$checks ne "3862"} {
    error "Sequential DeepFilter checks=$checks expected=3862"
}
puts "SEQUENTIAL_DEEPFILTER_ENGINE_XSIM_PASS"
close_sim
close_project
