# Vivado/XSim behavioral test runner for Vivado 2018.3 or newer.
set script_dir [file dirname [file normalize [info script]]]
set rtl_root [file normalize [file join $script_dir ..]]
set leaf_files [lsort [glob [file join $rtl_root leaf *.v]]]
set sparse_files [lsort [glob -nocomplain [file join $rtl_root sparse *.v]]]
set gsu_files [lsort [glob -nocomplain [file join $rtl_root gsu *.v]]]
set linear_files [lsort [glob -nocomplain [file join $rtl_root linear *.v]]]
set fullband_files [lsort [glob -nocomplain [file join $rtl_root fullband *.v]]]
set axi_files [lsort [glob -nocomplain [file join $rtl_root axi *.v]]]
set profiling_files [lsort [glob -nocomplain [file join $rtl_root profiling *.v]]]
set memory_files [lsort [glob -nocomplain [file join $rtl_root memory *.v]]]
set control_files [lsort [glob -nocomplain [file join $rtl_root control *.v]]]
set design_files [concat $leaf_files $sparse_files $gsu_files $linear_files \
                         $fullband_files $axi_files $profiling_files \
                         $memory_files $control_files]
set testbenches [lsort [glob [file join $rtl_root tb tb_*.v]]]
set work_root [file join $rtl_root build xsim]
file mkdir $work_root

set failed 0
set passed 0
foreach tb_file $testbenches {
    set tb_name [file rootname [file tail $tb_file]]
    set project_dir [file join $work_root $tb_name]
    puts "=== XSIM $tb_name ==="
    if {[catch {
        create_project -force $tb_name $project_dir -part xc7z020clg400-1
        add_files -norecurse $design_files
        if {[llength $memory_files] > 0} {
            set_property file_type SystemVerilog [get_files $memory_files]
        }
        add_files -fileset sim_1 -norecurse $tb_file
        set_property file_type SystemVerilog [get_files $tb_file]
        set_property top $tb_name [get_filesets sim_1]
        set_property target_language Verilog [current_project]
        if {$tb_name eq "tb_parameter_bram_bringup"} {
            set_property xsim.simulate.runtime 20ms [get_filesets sim_1]
        } elseif {$tb_name eq "tb_parameter_source_directory"} {
            set_property xsim.simulate.runtime 20ms [get_filesets sim_1]
        } elseif {$tb_name eq "tb_matrix0_raw_accumulator_scratch"} {
            set_property xsim.simulate.runtime 1ms [get_filesets sim_1]
        } elseif {$tb_name eq "tb_parameter_weight_bank"} {
            set_property xsim.simulate.runtime 100us [get_filesets sim_1]
        } elseif {$tb_name eq "tb_memory" || $tb_name eq "tb_fsm"} {
            set_property xsim.simulate.runtime 10us [get_filesets sim_1]
        } else {
            set_property xsim.simulate.runtime 1000ns [get_filesets sim_1]
        }
        launch_simulation -simset sim_1 -mode behavioral
        close_sim

        set sim_log [file join $project_dir "$tb_name.sim" sim_1 behav xsim simulate.log]
        if {![file exists $sim_log]} {
            error "Simulation log was not generated: $sim_log"
        }
        set log_handle [open $sim_log r]
        set log_text [read $log_handle]
        close $log_handle
        if {[string first "PASS $tb_name" $log_text] < 0} {
            error "Self-checking PASS marker was not found in $sim_log"
        }
    } reason]} {
        puts "XSIM_ERROR $tb_name: $reason"
        set failed 1
        catch {close_sim}
    } else {
        incr passed
        puts "XSIM_PASS $tb_name"
    }
    catch {close_project}
}

puts "XSIM_SUMMARY passed=$passed total=[llength $testbenches]"
if {$failed} {
    puts "XSIM_ALL_TESTS_FAILED"
    exit 1
}
puts "XSIM_ALL_TESTS_COMPLETED"
exit 0
