# Vivado 2018.3/XSim batch runner for tb_pe_requant_lane.
# Optional first tclarg: absolute path to rtl/pe_array.

if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set pe_root [file normalize [file join $script_dir ../..]]
}

set rtl_file    [file join $pe_root rtl arithmetic pe_requant_lane.sv]
set tb_file     [file join $pe_root tb unit tb_pe_requant_lane.sv]
set vector_file [file join $pe_root tb vectors pe_requant_lane_vectors.txt]
set build_dir   [file join $pe_root build xsim pe_requant_lane]

foreach required [list $rtl_file $tb_file $vector_file] {
    if {![file exists $required]} {
        error "Missing required file: $required"
    }
}

file delete -force $build_dir
file mkdir $build_dir

create_project pe_requant_lane_xsim $build_dir -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
add_files -norecurse $rtl_file
add_files -fileset sim_1 -norecurse $tb_file
set_property file_type SystemVerilog [get_files [list $rtl_file $tb_file]]
set_property top tb_pe_requant_lane [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set plusarg [format {-testplusarg VECTORS=%s} [file normalize $vector_file]]
set_property -name xsim.simulate.xsim.more_options -value $plusarg \
    -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation
run all
close_sim
close_project
