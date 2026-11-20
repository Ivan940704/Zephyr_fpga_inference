# Rebuild and validate the PYNQ-Z1 image-v5 32-PE accelerator block design.
#
# Usage:
#   vivado -mode batch -source create_accelerator_full_bd.tcl \
#          -tclargs <staged-rtl-root>
#
# This script intentionally stops after block-design validation and wrapper
# creation.  It does not launch synthesis/implementation or write a bitstream.

if {$argc >= 1} {
    set rtl_root [file normalize [lindex $argv 0]]
} else {
    set script_dir [file dirname [file normalize [info script]]]
    set rtl_root [file normalize [file join $script_dir ..]]
}

set repo_root [file normalize [file join $rtl_root ..]]
set pe_root [file join $rtl_root pe_array baseline v1 rtl]
set pe_v2_root [file join $rtl_root pe_array production_v2 rtl]
set part_name xc7z020clg400-1
set project_name zephyr_full
set design_name zephyr_full
set project_dir [file join [file dirname $rtl_root] zephyr_full_bd]
set report_dir [file join $rtl_root reports accelerator_full_bd_preimplementation]

file delete -force $project_dir
file mkdir $project_dir
file mkdir $report_dir

set sv_sources [list \
    [file join $rtl_root memory sparse_stage_map_v5.sv] \
    [file join $rtl_root memory sparse_union_planner_v5.sv] \
    [file join $pe_root arithmetic pe_requant_lane.sv] \
    [file join $pe_root arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $pe_root pe pe_hybrid_mac.sv]]
set v_sources [list \
    [file join $rtl_root memory memory_wide256.v] \
    [file join $rtl_root memory model_memory_v5_table.v] \
    [file join $rtl_root memory memory_service_v5.v] \
    [file join $rtl_root memory sequential_recurrent_context_store_v5.v] \
    [file join $rtl_root memory sequential_pe_job_controller_v5.v] \
    [file join $pe_root nonlinear pe_sigmoid_lut_255.v] \
    [file join $pe_root postprocess pe_gate_postprocess.v] \
    [file join $pe_root stream pe_shared_requant_engine.v] \
    [file join $pe_root index pe_spike_decision.v] \
    [file join $pe_root index pe_active_index_writer.v] \
    [file join $pe_root pe pe_cdf_sequencer.v] \
    [file join $pe_v2_root pe pe_hybrid_mac_array_32.v] \
    [file join $pe_v2_root pe pe_membrane_sequencer_32.v] \
    [file join $pe_v2_root stream pe_output_serializer_32.v] \
    [file join $pe_v2_root top pe_array_datapath_v5_32.v] \
    [file join $rtl_root memory sequential_v5_pe_memory_subsystem.v] \
    [file join $rtl_root memory layernorm_mailbox.v] \
    [file join $rtl_root control fsm.v] \
    [file join $rtl_root integration layernorm_mailbox_fsm_adapter.v] \
    [file join $rtl_root integration sequential_feature_dispatcher.v] \
    [file join $rtl_root integration sequential_df_coefficient_store.v] \
    [file join $rtl_root integration hybrid_pe_deepfilter_controller.v] \
    [file join $rtl_root experiments realtime_layernorm layernorm_engine_q12.v] \
    [file join $rtl_root experiments realtime_layernorm layernorm_parameter_rom_q12.v] \
    [file join $rtl_root experiments realtime_layernorm realtime_layernorm_coordinator.v] \
    [file join $rtl_root top accelerator_top.v] \
    [file join $rtl_root axi accelerator_control_axil.v] \
    [file join $rtl_root profiling accelerator_profiling_counters.v] \
    [file join $rtl_root top accelerator_system_top.v]]
set macro_headers [list \
    [file join $rtl_root memory model_memory_v5_map.vh]]
set data_headers [list \
    [file join $rtl_root experiments realtime_layernorm data layernorm_parameter_rom_q12_init.vh] \
    [file join $rtl_root experiments realtime_layernorm data projection_dequant_q12_init.vh] \
    [file join $rtl_root experiments realtime_layernorm data subband_source_index_init.vh]]
set headers [concat $macro_headers $data_headers]

foreach required [concat $sv_sources $v_sources $headers] {
    if {![file exists $required]} {
        error "Missing full-design source: $required"
    }
}

set board_preset_available 0
set board_preset_applied 0
set selected_board_part NONE
set validation_pass 0

if {[catch {
    create_project -force $project_name $project_dir -part $part_name
    set_property target_language Verilog [current_project]
    # Keep Vivado's module-reference parser at the RTL include root.  Vivado
    # 2018.3 does not consistently apply fileset include_dirs during the first
    # module-reference inference pass.
    cd $rtl_root

    set board_matches [concat \
        [get_board_parts -quiet *pynq*z1*] \
        [get_board_parts -quiet *PYNQ*Z1*]]
    set board_matches [lsort -unique $board_matches]
    if {[llength $board_matches] > 0} {
        set board_preset_available 1
        set selected_board_part [lindex $board_matches end]
        set_property board_part $selected_board_part [current_project]
        puts "ACCELERATOR_FULL_BD_BOARD_PART $selected_board_part"
    } else {
        puts "ACCELERATOR_FULL_BD_BOARD_PRESET_MISSING fallback_part=$part_name"
    }

    # The generated ROM .vh files contain procedural initialization statements
    # and must be consumed only through their owning modules' `include
    # directives.  The memory-map header is macro-only; mark just that header
    # global so Vivado 2018.3's open_run/module-reference parser retains the
    # image-v5 definitions after synthesis.
    add_files -norecurse [concat $sv_sources $v_sources $headers]
    set_property file_type SystemVerilog [get_files $sv_sources]
    set_property file_type Verilog [get_files $v_sources]
    set_property file_type {Verilog Header} [get_files $headers]
    set_property is_global_include true [get_files $macro_headers]
    set_property include_dirs [list $rtl_root \
        [file join $rtl_root experiments realtime_layernorm data]] [current_fileset]
    update_compile_order -fileset sources_1
    create_bd_design $design_name

    set ps [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:processing_system7:* ps7]
    if {$board_preset_available} {
        puts "ACCELERATOR_FULL_DQS_STAGE apply_board_preset_begin"
        apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
            -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
            $ps
        puts "ACCELERATOR_FULL_DQS_STAGE apply_board_preset_end"
        set board_preset_applied 1
    } else {
        make_bd_intf_pins_external [get_bd_intf_pins $ps/DDR]
        make_bd_intf_pins_external [get_bd_intf_pins $ps/FIXED_IO]
    }

    set_property -dict [list \
        CONFIG.PCW_USE_M_AXI_GP0 {1} \
        CONFIG.PCW_USE_S_AXI_HP0 {1} \
        CONFIG.PCW_USE_S_AXI_HP1 {1} \
        CONFIG.PCW_USE_S_AXI_HP2 {1} \
        CONFIG.PCW_USE_S_AXI_HP3 {1} \
        CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
        CONFIG.PCW_S_AXI_HP1_DATA_WIDTH {64} \
        CONFIG.PCW_S_AXI_HP2_DATA_WIDTH {64} \
        CONFIG.PCW_S_AXI_HP3_DATA_WIDTH {64} \
        CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
        CONFIG.PCW_IRQ_F2P_INTR {1} \
        CONFIG.PCW_EN_CLK0_PORT {1} \
        CONFIG.PCW_EN_RST0_PORT {1} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000}] $ps
    foreach freq_property {
        CONFIG.PCW_M_AXI_GP0_FREQMHZ.VALUE_SRC
        CONFIG.PCW_S_AXI_HP0_FREQMHZ.VALUE_SRC
        CONFIG.PCW_S_AXI_HP1_FREQMHZ.VALUE_SRC
        CONFIG.PCW_S_AXI_HP2_FREQMHZ.VALUE_SRC
        CONFIG.PCW_S_AXI_HP3_FREQMHZ.VALUE_SRC
    } {
        catch {set_property $freq_property {PROPAGATED} $ps}
    }

    set reset_block [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:proc_sys_reset:* rst]
    set data_reset_block [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:proc_sys_reset:* data_rst]
    set control_ic [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_interconnect:* control_ic]
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {4}] $control_ic

    foreach hp_index {0 1 2 3} {
        set hp_ic($hp_index) [create_bd_cell -type ip \
            -vlnv xilinx.com:ip:axi_interconnect:* hp${hp_index}_ic]
        set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] \
            $hp_ic($hp_index)
    }

    set mailbox_bram [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_bram_ctrl:* mailbox_bram]
    set_property -dict [list \
        CONFIG.DATA_WIDTH {32} \
        CONFIG.SINGLE_PORT_BRAM {1} \
        CONFIG.READ_LATENCY {1}] $mailbox_bram

    set io_dma [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_dma:* io_dma]
    set_property -dict [list \
        CONFIG.c_include_sg {0} \
        CONFIG.c_include_mm2s {1} \
        CONFIG.c_include_s2mm {1} \
        CONFIG.c_include_mm2s_dre {0} \
        CONFIG.c_include_s2mm_dre {0} \
        CONFIG.c_m_axi_mm2s_data_width {64} \
        CONFIG.c_m_axis_mm2s_tdata_width {64} \
        CONFIG.c_mm2s_burst_size {16} \
        CONFIG.c_m_axi_s2mm_data_width {64} \
        CONFIG.c_s2mm_burst_size {16}] $io_dma

    set spectrum_dma [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_dma:* spectrum_dma]
    set_property -dict [list \
        CONFIG.c_include_sg {0} \
        CONFIG.c_include_mm2s {1} \
        CONFIG.c_include_s2mm {0} \
        CONFIG.c_include_mm2s_dre {0} \
        CONFIG.c_m_axi_mm2s_data_width {64} \
        CONFIG.c_m_axis_mm2s_tdata_width {64} \
        CONFIG.c_mm2s_burst_size {16}] $spectrum_dma

    set accel [create_bd_cell -type module \
        -reference accelerator_system_top accel]

    connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] \
        [get_bd_intf_pins $control_ic/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins $control_ic/M00_AXI] \
        [get_bd_intf_pins $accel/S_AXI_CONTROL]
    connect_bd_intf_net [get_bd_intf_pins $control_ic/M01_AXI] \
        [get_bd_intf_pins $mailbox_bram/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins $control_ic/M02_AXI] \
        [get_bd_intf_pins $io_dma/S_AXI_LITE]
    connect_bd_intf_net [get_bd_intf_pins $control_ic/M03_AXI] \
        [get_bd_intf_pins $spectrum_dma/S_AXI_LITE]
    connect_bd_intf_net [get_bd_intf_pins $mailbox_bram/BRAM_PORTA] \
        [get_bd_intf_pins $accel/MAILBOX_BRAM]

    connect_bd_intf_net [get_bd_intf_pins $accel/M_AXI_PARAMETER] \
        [get_bd_intf_pins $hp_ic(0)/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins $hp_ic(0)/M00_AXI] \
        [get_bd_intf_pins $ps/S_AXI_HP0]
    connect_bd_intf_net [get_bd_intf_pins $io_dma/M_AXI_MM2S] \
        [get_bd_intf_pins $hp_ic(1)/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins $hp_ic(1)/M00_AXI] \
        [get_bd_intf_pins $ps/S_AXI_HP1]
    connect_bd_intf_net [get_bd_intf_pins $io_dma/M_AXI_S2MM] \
        [get_bd_intf_pins $hp_ic(2)/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins $hp_ic(2)/M00_AXI] \
        [get_bd_intf_pins $ps/S_AXI_HP2]
    connect_bd_intf_net [get_bd_intf_pins $spectrum_dma/M_AXI_MM2S] \
        [get_bd_intf_pins $hp_ic(3)/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins $hp_ic(3)/M00_AXI] \
        [get_bd_intf_pins $ps/S_AXI_HP3]

    connect_bd_intf_net [get_bd_intf_pins $io_dma/M_AXIS_MM2S] \
        [get_bd_intf_pins $accel/S_AXIS_FB]
    connect_bd_intf_net [get_bd_intf_pins $spectrum_dma/M_AXIS_MM2S] \
        [get_bd_intf_pins $accel/S_AXIS_SPECTRUM]
    connect_bd_intf_net [get_bd_intf_pins $accel/M_AXIS_OUTPUT] \
        [get_bd_intf_pins $io_dma/S_AXIS_S2MM]

    set irq_concat [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:xlconcat:* irq_concat]
    set_property CONFIG.NUM_PORTS {4} $irq_concat
    connect_bd_net [get_bd_pins $accel/accelerator_irq] \
        [get_bd_pins $irq_concat/In0]
    connect_bd_net [get_bd_pins $io_dma/mm2s_introut] \
        [get_bd_pins $irq_concat/In1]
    connect_bd_net [get_bd_pins $io_dma/s2mm_introut] \
        [get_bd_pins $irq_concat/In2]
    connect_bd_net [get_bd_pins $spectrum_dma/mm2s_introut] \
        [get_bd_pins $irq_concat/In3]
    connect_bd_net [get_bd_pins $irq_concat/dout] \
        [get_bd_pins $ps/IRQ_F2P]

    set fclk [get_bd_pins $ps/FCLK_CLK0]
    set control_resetn [get_bd_pins $reset_block/peripheral_aresetn]
    set data_resetn [get_bd_pins $data_reset_block/peripheral_aresetn]
    connect_bd_net $fclk \
        [get_bd_pins $ps/M_AXI_GP0_ACLK] \
        [get_bd_pins $ps/S_AXI_HP0_ACLK] \
        [get_bd_pins $ps/S_AXI_HP1_ACLK] \
        [get_bd_pins $ps/S_AXI_HP2_ACLK] \
        [get_bd_pins $ps/S_AXI_HP3_ACLK] \
        [get_bd_pins $reset_block/slowest_sync_clk] \
        [get_bd_pins $data_reset_block/slowest_sync_clk] \
        [get_bd_pins $accel/aclk] \
        [get_bd_pins $control_ic/ACLK] \
        [get_bd_pins $control_ic/S00_ACLK] \
        [get_bd_pins $control_ic/M00_ACLK] \
        [get_bd_pins $control_ic/M01_ACLK] \
        [get_bd_pins $control_ic/M02_ACLK] \
        [get_bd_pins $control_ic/M03_ACLK] \
        [get_bd_pins $mailbox_bram/s_axi_aclk] \
        [get_bd_pins $io_dma/s_axi_lite_aclk] \
        [get_bd_pins $io_dma/m_axi_mm2s_aclk] \
        [get_bd_pins $io_dma/m_axi_s2mm_aclk] \
        [get_bd_pins $spectrum_dma/s_axi_lite_aclk] \
        [get_bd_pins $spectrum_dma/m_axi_mm2s_aclk]
    foreach hp_index {0 1 2 3} {
        connect_bd_net $fclk \
            [get_bd_pins $hp_ic($hp_index)/ACLK] \
            [get_bd_pins $hp_ic($hp_index)/S00_ACLK] \
            [get_bd_pins $hp_ic($hp_index)/M00_ACLK]
    }
    set_property CONFIG.CLK_DOMAIN [get_property CONFIG.CLK_DOMAIN $fclk] \
        [get_bd_pins $accel/aclk]

    connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] \
        [get_bd_pins $reset_block/ext_reset_in] \
        [get_bd_pins $data_reset_block/ext_reset_in]
    connect_bd_net [get_bd_pins $accel/soft_reset_request] \
        [get_bd_pins $data_reset_block/aux_reset_in]
    connect_bd_net $control_resetn \
        [get_bd_pins $accel/aresetn] \
        [get_bd_pins $control_ic/ARESETN] \
        [get_bd_pins $control_ic/S00_ARESETN] \
        [get_bd_pins $control_ic/M00_ARESETN] \
        [get_bd_pins $control_ic/M01_ARESETN] \
        [get_bd_pins $control_ic/M02_ARESETN] \
        [get_bd_pins $control_ic/M03_ARESETN] \
        [get_bd_pins $mailbox_bram/s_axi_aresetn] \
        [get_bd_pins $io_dma/axi_resetn] \
        [get_bd_pins $spectrum_dma/axi_resetn]
    connect_bd_net $data_resetn \
        [get_bd_pins $accel/accelerator_aresetn]
    foreach hp_index {0 1 2 3} {
        connect_bd_net $control_resetn \
            [get_bd_pins $hp_ic($hp_index)/ARESETN] \
            [get_bd_pins $hp_ic($hp_index)/S00_ARESETN] \
            [get_bd_pins $hp_ic($hp_index)/M00_ARESETN]
    }

    set control_seg [lindex [get_bd_addr_segs -quiet -of_objects \
        [get_bd_intf_pins $accel/S_AXI_CONTROL]] 0]
    set mailbox_seg [lindex [get_bd_addr_segs -quiet -of_objects \
        [get_bd_intf_pins $mailbox_bram/S_AXI]] 0]
    set io_dma_seg [lindex [get_bd_addr_segs -quiet -of_objects \
        [get_bd_intf_pins $io_dma/S_AXI_LITE]] 0]
    set spectrum_dma_seg [lindex [get_bd_addr_segs -quiet -of_objects \
        [get_bd_intf_pins $spectrum_dma/S_AXI_LITE]] 0]
    foreach segment [list $control_seg $mailbox_seg $io_dma_seg $spectrum_dma_seg] {
        if {$segment eq ""} {
            error "A required GP0 address segment was not inferred"
        }
    }
    set ps_data [get_bd_addr_spaces $ps/Data]
    assign_bd_address -offset 0x43C00000 -range 0x00001000 \
        -target_address_space $ps_data $control_seg
    assign_bd_address -offset 0x43C10000 -range 0x00001000 \
        -target_address_space $ps_data $mailbox_seg
    assign_bd_address -offset 0x40400000 -range 0x00010000 \
        -target_address_space $ps_data $io_dma_seg
    assign_bd_address -offset 0x40410000 -range 0x00010000 \
        -target_address_space $ps_data $spectrum_dma_seg
    assign_bd_address

    regenerate_bd_layout
    puts "ACCELERATOR_FULL_DQS_STAGE validate_bd_design_begin"
    validate_bd_design
    puts "ACCELERATOR_FULL_DQS_STAGE validate_bd_design_end"

    set gp0_mhz [get_property CONFIG.PCW_M_AXI_GP0_FREQMHZ $ps]
    set hp0_mhz [get_property CONFIG.PCW_S_AXI_HP0_FREQMHZ $ps]
    set hp1_mhz [get_property CONFIG.PCW_S_AXI_HP1_FREQMHZ $ps]
    set hp2_mhz [get_property CONFIG.PCW_S_AXI_HP2_FREQMHZ $ps]
    set hp3_mhz [get_property CONFIG.PCW_S_AXI_HP3_FREQMHZ $ps]
    foreach mhz [list $gp0_mhz $hp0_mhz $hp1_mhz $hp2_mhz $hp3_mhz] {
        if {abs(double($mhz) - 100.0) > 0.001} {
            error "AXI clock propagation mismatch: GP0=$gp0_mhz HP0=$hp0_mhz HP1=$hp1_mhz HP2=$hp2_mhz HP3=$hp3_mhz"
        }
    }

    save_bd_design
    set validation_pass 1
    set bd_file [get_files ${design_name}.bd]
    # Global mode lets the PS7-generated 100 MHz clock constraint drive
    # optimization through the module-reference hierarchy.  Vivado 2018.3
    # otherwise synthesizes accelerator_system_top as an unconstrained OOC
    # checkpoint, which produced a false 16-LUT critical control chain.
    set_property synth_checkpoint_mode None $bd_file
    set wrapper_files [make_wrapper -files $bd_file -top]
    add_files -norecurse $wrapper_files
    set_property top ${design_name}_wrapper [current_fileset]
    update_compile_order -fileset sources_1

    set report [open [file join $report_dir bd_validation.txt] w]
    fconfigure $report -translation lf
    puts $report "evidence=vivado_bd_validation_preimplementation"
    puts $report "vivado_version=[version -short]"
    puts $report "part=$part_name"
    puts $report "board_preset_available=$board_preset_available"
    puts $report "board_preset_applied=$board_preset_applied"
    puts $report "board_part=$selected_board_part"
    puts $report "fclk0_mhz=100"
    puts $report "m_axi_gp0_aclk_mhz=$gp0_mhz"
    puts $report "s_axi_hp0_aclk_mhz=$hp0_mhz"
    puts $report "s_axi_hp1_aclk_mhz=$hp1_mhz"
    puts $report "s_axi_hp2_aclk_mhz=$hp2_mhz"
    puts $report "s_axi_hp3_aclk_mhz=$hp3_mhz"
    puts $report "accelerator_control_address=0x43C00000"
    puts $report "accelerator_control_range_bytes=4096"
    puts $report "mailbox_address=0x43C10000"
    puts $report "mailbox_range_bytes=4096"
    puts $report "io_dma_address=0x40400000"
    puts $report "spectrum_dma_address=0x40410000"
    puts $report "dma_mode=simple"
    puts $report "parameter_path=accelerator_M_AXI_PARAMETER->HP0"
    puts $report "fullband_mm2s_path=io_dma_M_AXI_MM2S->HP1"
    puts $report "result_s2mm_path=io_dma_M_AXI_S2MM->HP2"
    puts $report "spectrum_mm2s_path=spectrum_dma_M_AXI_MM2S->HP3"
    puts $report "mailbox_path=GP0->mailbox_bram_ctrl->accelerator_MAILBOX_BRAM"
    puts $report "control_reset_domain=PS_FCLK_RESET0_N->rst->control_plane"
    puts $report "data_reset_domain=PS_FCLK_RESET0_N_or_soft_reset_request->data_rst->accelerator_only"
    puts $report "infrastructure_reset_domain=PS_FCLK_RESET0_N->rst->DMA_mailbox_controller_HP_fabric"
    puts $report "soft_reset_requires=custom_datapath_quiescent_and_software_verified_DMA_idle"
    puts $report "soft_reset_control_plane_survives=YES"
    puts $report "soft_reset_axi_infrastructure_survives=YES"
    puts $report "synthesis_checkpoint_mode=global"
    puts $report "accelerator_clock_constraint=PS7_FCLK0_10.000ns"
    puts $report "irq_bit0=accelerator_control"
    puts $report "irq_bit1=io_dma_mm2s"
    puts $report "irq_bit2=io_dma_s2mm"
    puts $report "irq_bit3=spectrum_dma_mm2s"
    puts $report "validate_bd_design=PASS"
    puts $report "synthesis_run=NOT_RUN_BY_THIS_SCRIPT"
    puts $report "implementation_run=NOT_RUN"
    puts $report "bitstream=NOT_GENERATED"
    close $report
} reason failure_options]} {
    puts stderr "ACCELERATOR_FULL_BD_FATAL $reason"
    if {[dict exists $failure_options -errorinfo]} {
        puts stderr "ACCELERATOR_FULL_BD_ERRORINFO [dict get $failure_options -errorinfo]"
    }
    set report [open [file join $report_dir bd_validation.txt] w]
    fconfigure $report -translation lf
    puts $report "evidence=vivado_bd_validation_preimplementation"
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
puts "ACCELERATOR_FULL_BD_VALIDATE_PASS"
puts "ACCELERATOR_FULL_BD_IMPLEMENTATION_NOT_RUN"
exit 0
