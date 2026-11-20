# Vivado 2018.3/XSim batch runner for tb_pe_local_requant_bank_4lane.
# Optional first tclarg: absolute path to rtl/pe_array.

if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set pe_root [file normalize [file join $script_dir ../..]]
}

set lane_file   [file join $pe_root rtl arithmetic pe_requant_lane.sv]
set bank_file   [file join $pe_root rtl arithmetic pe_local_requant_bank_4lane.sv]
set tb_file     [file join $pe_root tb unit tb_pe_local_requant_bank_4lane.sv]
set vector_file [file join $pe_root tb vectors pe_local_requant_bank_4lane_vectors.txt]

# Windows XSim cannot execute generated .bat files from a UNC working
# directory.  Keep generated simulation files in the native TEMP directory
# when Vivado is launched from Windows against a WSL-hosted source tree.
if {$tcl_platform(platform) eq "windows"} {
    set build_dir [file normalize [file join $::env(TEMP) zephyr_fpga_xsim pe_local_requant_bank_4lane]]
} else {
    set build_dir [file join $pe_root build xsim pe_local_requant_bank_4lane]
}

foreach required [list $lane_file $bank_file $tb_file $vector_file] {
    if {![file exists $required]} {
        error "Missing required file: $required"
    }
}

file delete -force $build_dir
file mkdir $build_dir
set local_vector_file [file join $build_dir pe_local_requant_bank_4lane_vectors.txt]
file copy -force $vector_file $local_vector_file

create_project pe_local_requant_bank_4lane_xsim $build_dir \
    -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse [list $lane_file $bank_file]
add_files -fileset sim_1 -norecurse $tb_file
set_property file_type SystemVerilog \
    [get_files [list $lane_file $bank_file $tb_file]]
set_property top tb_pe_local_requant_bank_4lane [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set plusarg [format {-testplusarg VECTORS=%s} [file normalize $local_vector_file]]
set_property -name xsim.simulate.xsim.more_options -value $plusarg \
    -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation
run all
set pass_value [get_value /tb_pe_local_requant_bank_4lane/test_passed]
if {$pass_value ne "1"} {
    error "tb_pe_local_requant_bank_4lane did not assert test_passed"
}
close_sim
close_project
