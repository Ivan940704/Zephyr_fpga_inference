# Vivado 2018.3/XSim batch runner for tb_pe_gate_postprocess.
if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set pe_root [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
}

set rtl_file    [file join $pe_root rtl postprocess pe_gate_postprocess.v]
set tb_file     [file join $pe_root tb unit tb_pe_gate_postprocess.v]
set vector_file [file join $pe_root tb vectors pe_gate_postprocess_vectors.hex]
set count_file  [file join $pe_root tb vectors pe_gate_postprocess_vectors.count]

if {$tcl_platform(platform) eq "windows"} {
    set work_dir [file normalize [file join $::env(TEMP) zephyr_fpga_xsim pe_gate_postprocess]]
} else {
    set work_dir [file join $pe_root build xsim pe_gate_postprocess]
}

foreach required [list $rtl_file $tb_file $vector_file $count_file] {
    if {![file exists $required]} {
        error "Missing required file: $required"
    }
}

set count_handle [open $count_file r]
set vector_count [string trim [read $count_handle]]
close $count_handle

file delete -force $work_dir
file mkdir $work_dir
set local_vector_file [file join $work_dir pe_gate_postprocess_vectors.hex]
file copy -force $vector_file $local_vector_file

create_project pe_gate_postprocess_sim $work_dir -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse $rtl_file
add_files -fileset sim_1 -norecurse $tb_file
set_property file_type Verilog [get_files [list $rtl_file $tb_file]]
set_property top tb_pe_gate_postprocess [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set plusargs [format {-testplusarg VECTORS=%s -testplusarg COUNT=%s} \
    [file normalize $local_vector_file] $vector_count]
set_property -name xsim.simulate.xsim.more_options -value $plusargs \
    -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
set pass_value [get_value /tb_pe_gate_postprocess/test_passed]
if {$pass_value ne "1"} {
    error "tb_pe_gate_postprocess did not assert test_passed"
}
close_sim
close_project
