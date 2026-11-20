if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set pe_root [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
}

set rtl_file    [file join $pe_root rtl pe pe_hybrid_mac.sv]
set tb_file     [file join $pe_root tb unit tb_pe_hybrid_mac.sv]
set vector_file [file join $pe_root tb vectors pe_hybrid_mac_vectors.txt]

if {$tcl_platform(platform) eq "windows"} {
    set work_dir [file normalize [file join $::env(TEMP) zephyr_fpga_xsim pe_hybrid_mac]]
} else {
    set work_dir [file join $pe_root build xsim pe_hybrid_mac]
}

foreach required [list $rtl_file $tb_file $vector_file] {
    if {![file exists $required]} {
        error "Missing required file: $required"
    }
}

file delete -force $work_dir
file mkdir $work_dir
set local_vector_file [file join $work_dir pe_hybrid_mac_vectors.txt]
file copy -force $vector_file $local_vector_file

create_project pe_hybrid_mac_sim $work_dir -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse $rtl_file
add_files -fileset sim_1 -norecurse $tb_file
set_property file_type SystemVerilog [get_files [list $rtl_file $tb_file]]
set_property top tb_pe_hybrid_mac [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set plusarg [format {-testplusarg VECTORS=%s} [file normalize $local_vector_file]]
set_property -name xsim.simulate.xsim.more_options -value $plusarg \
    -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
run all
set pass_value [get_value /tb_pe_hybrid_mac/test_passed]
if {$pass_value ne "1"} {
    error "tb_pe_hybrid_mac did not assert test_passed"
}
close_sim
close_project
