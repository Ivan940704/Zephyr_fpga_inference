# Rebuild and validate the minimal PYNQ-Z1 parameter-BRAM block design.
#
# Usage:
#   vivado -mode batch -source create_parameter_bram_bringup_bd.tcl \
#          -tclargs <staged-rtl-root>
#
# This script deliberately performs no implementation, place/route, explicit
# hardware-handoff export, or bitstream generation.  Required IP/BD synthesis
# products are generated on demand by the separate project synthesis run.

if {$argc >= 1} {
    set rtl_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set rtl_root [file normalize [file join $script_dir ..]]
}

set part_name xc7z020clg400-1
set project_dir [file join [file dirname $rtl_root] zpb_bd]
set report_dir [file join $rtl_root reports parameter_bram_bringup bd]
set project_name zpb
set design_name zpb
file delete -force $project_dir
file mkdir $project_dir
file mkdir $report_dir

set rtl_files [list \
    [file join $rtl_root memory memory.v] \
    [file join $rtl_root memory model_memory_v3_table.v] \
    [file join $rtl_root memory memory_service.v] \
    [file join $rtl_root memory memory_service_axil.v] \
    [file join $rtl_root memory parameter_bram_bringup_top.v]]
set global_header [file join $rtl_root memory model_memory_v3_map.vh]
foreach required [concat $rtl_files [list $global_header]] {
    if {![file exists $required]} {
        error "Missing required RTL file: $required"
    }
}

set board_preset_available 0
set board_preset_applied 0
set selected_board_part NONE
set validation_pass 0

if {[catch {
    create_project -force $project_name $project_dir -part $part_name
    set_property target_language Verilog [current_project]

    set board_matches [concat \
        [get_board_parts -quiet *pynq*z1*] \
        [get_board_parts -quiet *PYNQ*Z1*]]
    set board_matches [lsort -unique $board_matches]
    if {[llength $board_matches] > 0} {
        set board_preset_available 1
        set selected_board_part [lindex $board_matches end]
        set_property board_part $selected_board_part [current_project]
        puts "PARAMETER_BRAM_BD_BOARD_PART $selected_board_part"
    } else {
        puts "PARAMETER_BRAM_BD_BOARD_PRESET_MISSING fallback_part=$part_name"
    }

    add_files -norecurse [concat $rtl_files [list $global_header]]
    # Vivado 2018.3 module references reject a SystemVerilog-typed top file.
    # These .v sources use synthesizable Verilog-2001 syntax, so retain the
    # legacy-compatible file type in the BD project.
    set_property file_type Verilog [get_files $rtl_files]
    set_property is_global_include true [get_files $global_header]
    set_property include_dirs [list $rtl_root] [current_fileset]
    update_compile_order -fileset sources_1
    create_bd_design $design_name

    set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:* ps7]
    if {$board_preset_available} {
        puts "PARAMETER_BRAM_DQS_STAGE apply_board_preset_begin"
        apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
            -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
            $ps
        puts "PARAMETER_BRAM_DQS_STAGE apply_board_preset_end"
        set board_preset_applied 1
    } else {
        make_bd_intf_pins_external [get_bd_intf_pins $ps/DDR]
        make_bd_intf_pins_external [get_bd_intf_pins $ps/FIXED_IO]
    }
    puts "PARAMETER_BRAM_BD_PS_PRESET_COMPLETE"
    puts "PARAMETER_BRAM_DQS_STAGE explicit_ps_configuration_begin"
    set_property -dict [list \
        CONFIG.PCW_USE_M_AXI_GP0 {1} \
        CONFIG.PCW_USE_S_AXI_HP0 {1} \
        CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
        CONFIG.PCW_EN_CLK0_PORT {1} \
        CONFIG.PCW_EN_RST0_PORT {1} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000}] $ps
    # PCW_*_FREQMHZ are propagate-only fields in PS7.  Release the PYNQ preset's
    # USER-strength 10 MHz placeholder so FCLK0 connection propagation owns
    # these derived values.
    set_property CONFIG.PCW_M_AXI_GP0_FREQMHZ.VALUE_SRC {PROPAGATED} $ps
    set_property CONFIG.PCW_S_AXI_HP0_FREQMHZ.VALUE_SRC {PROPAGATED} $ps
    puts "PARAMETER_BRAM_DQS_STAGE explicit_ps_configuration_end"
    puts "PARAMETER_BRAM_BD_PS_CONFIG_COMPLETE"

    set reset_block [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:proc_sys_reset:* rst]
    set control_ic [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_interconnect:* ctl_ic]
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $control_ic
    set hp_ic [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_interconnect:* hp_ic]
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $hp_ic
    set bringup [create_bd_cell -type module \
        -reference parameter_bram_bringup_top mem]

    connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] \
        [get_bd_intf_pins $control_ic/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins $control_ic/M00_AXI] \
        [get_bd_intf_pins $bringup/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins $bringup/M_AXI] \
        [get_bd_intf_pins $hp_ic/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins $hp_ic/M00_AXI] \
        [get_bd_intf_pins $ps/S_AXI_HP0]

    set fclk [get_bd_pins $ps/FCLK_CLK0]
    set resetn [get_bd_pins $reset_block/peripheral_aresetn]
    connect_bd_net $fclk \
        [get_bd_pins $ps/M_AXI_GP0_ACLK] \
        [get_bd_pins $ps/S_AXI_HP0_ACLK] \
        [get_bd_pins $reset_block/slowest_sync_clk] \
        [get_bd_pins $bringup/aclk] \
        [get_bd_pins $control_ic/ACLK] \
        [get_bd_pins $control_ic/S00_ACLK] \
        [get_bd_pins $control_ic/M00_ACLK] \
        [get_bd_pins $hp_ic/ACLK] \
        [get_bd_pins $hp_ic/S00_ACLK] \
        [get_bd_pins $hp_ic/M00_ACLK]
    # FREQ_HZ is inferred from the RTL interface metadata and is read-only on
    # a Vivado 2018.3 module-reference clock pin.  Only propagate the domain
    # name here; validate_bd_design checks the connected PS AXI frequencies.
    set_property CONFIG.CLK_DOMAIN [get_property CONFIG.CLK_DOMAIN $fclk] \
        [get_bd_pins $bringup/aclk]
    connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] \
        [get_bd_pins $reset_block/ext_reset_in]
    connect_bd_net $resetn \
        [get_bd_pins $bringup/aresetn] \
        [get_bd_pins $control_ic/ARESETN] \
        [get_bd_pins $control_ic/S00_ARESETN] \
        [get_bd_pins $control_ic/M00_ARESETN] \
        [get_bd_pins $hp_ic/ARESETN] \
        [get_bd_pins $hp_ic/S00_ARESETN] \
        [get_bd_pins $hp_ic/M00_ARESETN]

    # Five grouped probes keep ILA depth/resource bounded while retaining AR/R,
    # state/error and all four diagnostics counters.
    set ila_defs [get_ipdefs -all xilinx.com:ip:ila:*]
    if {[llength $ila_defs] == 0} {
        error "Vivado ILA IP definition is unavailable"
    }
    set ila [create_bd_cell -type ip -vlnv [lindex $ila_defs end] ila]
    set_property -dict [list \
        CONFIG.C_MONITOR_TYPE {Native} \
        CONFIG.C_NUM_OF_PROBES {5} \
        CONFIG.C_DATA_DEPTH {1024} \
        CONFIG.C_PROBE0_WIDTH {32} \
        CONFIG.C_PROBE1_WIDTH {64} \
        CONFIG.C_PROBE2_WIDTH {128} \
        CONFIG.C_PROBE3_WIDTH {42} \
        CONFIG.C_PROBE4_WIDTH {69}] $ila
    connect_bd_net $fclk [get_bd_pins $ila/clk]
    connect_bd_net [get_bd_pins $bringup/dbg_status] [get_bd_pins $ila/probe0]
    connect_bd_net [get_bd_pins $bringup/dbg_error] [get_bd_pins $ila/probe1]
    connect_bd_net [get_bd_pins $bringup/dbg_counters] [get_bd_pins $ila/probe2]
    connect_bd_net [get_bd_pins $bringup/dbg_axi_ar] [get_bd_pins $ila/probe3]
    connect_bd_net [get_bd_pins $bringup/dbg_axi_r] [get_bd_pins $ila/probe4]

    # Pin the software aperture first, then let Vivado map the remaining HP0
    # DDR segment.  Vivado 2018.3 assign_bd_address has no -force option.
    set control_seg [lindex [get_bd_addr_segs -quiet -of_objects \
        [get_bd_intf_pins $bringup/S_AXI]] 0]
    if {$control_seg eq ""} {
        error "No AXI-Lite address segment was inferred for parameter_bram/S_AXI"
    }
    assign_bd_address -offset 0x43C00000 -range 0x00001000 \
        -target_address_space [get_bd_addr_spaces $ps/Data] $control_seg
    assign_bd_address

    regenerate_bd_layout
    puts "PARAMETER_BRAM_DQS_STAGE validate_bd_design_begin"
    validate_bd_design
    puts "PARAMETER_BRAM_DQS_STAGE validate_bd_design_end"
    set gp0_mhz [get_property CONFIG.PCW_M_AXI_GP0_FREQMHZ $ps]
    set hp0_mhz [get_property CONFIG.PCW_S_AXI_HP0_FREQMHZ $ps]
    if {(abs(double($gp0_mhz) - 100.0) > 0.001) ||
        (abs(double($hp0_mhz) - 100.0) > 0.001)} {
        error "AXI clock propagation mismatch: GP0=$gp0_mhz MHz HP0=$hp0_mhz MHz"
    }
    save_bd_design
    set validation_pass 1

    set bd_file [get_files ${design_name}.bd]
    # Vivado 2018.3 exports hw_handoff/*.hwh even for an explicit
    # `generate_target synthesis`.  Do not request any target here; project
    # synthesis owns all output-product generation and the outer runner audits
    # this version-specific automatic side product separately.
    set wrapper_files [make_wrapper -files $bd_file -top]
    add_files -norecurse $wrapper_files
    update_compile_order -fileset sources_1

    set report [open [file join $report_dir bd_validation.txt] w]
    puts $report "evidence=vivado_bd_validation"
    puts $report "vivado_version=[version -short]"
    puts $report "part=$part_name"
    puts $report "board_preset_available=$board_preset_available"
    puts $report "board_preset_applied=$board_preset_applied"
    puts $report "board_part=$selected_board_part"
    if {[info exists ::env(XILINX_VIVADO)]} {
        puts $report "vivado_install_root=$::env(XILINX_VIVADO)"
        puts $report "board_preset_file=[file normalize [file join $::env(XILINX_VIVADO) data boards board_files PYNQ-Z1 1.0 preset.xml]]"
    } else {
        puts $report "vivado_install_root=UNKNOWN"
        puts $report "board_preset_file=UNKNOWN"
    }
    if {$board_preset_available} {
        puts $report "fallback_gap=NONE"
    } else {
        puts $report "fallback_gap=PYNQ-Z1 board preset unavailable; XC7Z020 part/default PS7 configuration used"
    }
    puts $report "fclk0_mhz=100"
    puts $report "m_axi_gp0_aclk_mhz=$gp0_mhz"
    puts $report "s_axi_hp0_aclk_mhz=$hp0_mhz"
    puts $report "ps7_ddr_frequency_mhz=[get_property CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ $ps]"
    foreach lane {0 1 2 3} {
        puts $report "ps7_ddr_dqs_to_clk_delay_${lane}=[get_property CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_${lane} $ps]"
        puts $report "ps7_package_ddr_dqs_to_clk_delay_${lane}=[get_property CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_${lane} $ps]"
        puts $report "ps7_ddr_board_delay_${lane}=[get_property CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY${lane} $ps]"
    }
    puts $report "control_address=0x43C00000"
    puts $report "control_range_bytes=4096"
    puts $report "control_path=PS7_M_AXI_GP0->AXI_Interconnect->parameter_bram_S_AXI"
    puts $report "parameter_path=parameter_bram_M_AXI->AXI_Interconnect->PS7_S_AXI_HP0"
    puts $report "ila_probe_count=5"
    puts $report "ila_depth=1024"
    puts $report "validate_bd_design=PASS"
    puts $report "bd_output_product=deferred_to_project_synthesis"
    puts $report "implementation_run=NOT_RUN"
    puts $report "bitstream=NOT_GENERATED"
    puts $report "hwh_requested=NO"
    close $report
} reason failure_options]} {
    puts stderr "PARAMETER_BRAM_BD_FATAL $reason"
    if {[dict exists $failure_options -errorinfo]} {
        puts stderr "PARAMETER_BRAM_BD_ERRORINFO [dict get $failure_options -errorinfo]"
    }
    set report [open [file join $report_dir bd_validation.txt] w]
    puts $report "evidence=vivado_bd_validation"
    puts $report "part=$part_name"
    puts $report "board_preset_available=$board_preset_available"
    puts $report "board_preset_applied=$board_preset_applied"
    puts $report "board_part=$selected_board_part"
    puts $report "validate_bd_design=FAIL"
    puts $report "failure=$reason"
    puts $report "implementation_run=NOT_RUN"
    puts $report "bitstream=NOT_GENERATED"
    close $report
    catch {close_project}
    exit 1
}

close_project
puts "PARAMETER_BRAM_BD_VALIDATE_PASS"
puts "PARAMETER_BRAM_BD_IMPLEMENTATION_NOT_RUN"
exit 0
