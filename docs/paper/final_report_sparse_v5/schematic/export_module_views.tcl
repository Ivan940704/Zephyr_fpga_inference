set dcp_path {C:/tmp/zv5-sparse-sim/zephyr_full_bd/checkpoints/zephyr_full_post_synth.dcp}
set output_dir {C:/Users/User/Documents/ChatGPT/Zephyr_fpga_inference/_worktrees/sparse-memory-v5-32pe/docs/paper/final_report_sparse_v5/schematic}

open_checkpoint $dcp_path

current_instance {zephyr_full_i/accel/inst/u_accelerator}
set accelerator_view {Sparse-v5 Accelerator Modules}
show_schematic -name $accelerator_view [get_cells -filter {IS_PRIMITIVE == 0}]
write_schematic -force -format svg -orientation landscape -scope all \
  -name $accelerator_view [file join $output_dir sparse_v5_modules_accelerator.svg]
write_schematic -force -format pdf -orientation landscape -scope all \
  -name $accelerator_view [file join $output_dir sparse_v5_modules_accelerator.pdf]

current_instance u_pe_memory_subsystem
set pe_memory_view {Sparse-v5 PE and Sparse-Memory Modules}
show_schematic -name $pe_memory_view [get_cells -filter {IS_PRIMITIVE == 0}]
write_schematic -force -format svg -orientation landscape -scope all \
  -name $pe_memory_view [file join $output_dir sparse_v5_modules_pe_memory.svg]
write_schematic -force -format pdf -orientation landscape -scope all \
  -name $pe_memory_view [file join $output_dir sparse_v5_modules_pe_memory.pdf]

current_instance ..
current_instance u_realtime_layernorm_coordinator
set layernorm_view {Sparse-v5 PL LayerNorm Modules}
show_schematic -name $layernorm_view [get_cells -filter {IS_PRIMITIVE == 0}]
write_schematic -force -format svg -orientation landscape -scope all \
  -name $layernorm_view [file join $output_dir sparse_v5_modules_layernorm.svg]
write_schematic -force -format pdf -orientation landscape -scope all \
  -name $layernorm_view [file join $output_dir sparse_v5_modules_layernorm.pdf]

current_instance
set done_file [open [file join $output_dir module_export_complete.txt] w]
puts $done_file "Vivado 2018.3 module schematics exported from $dcp_path"
close $done_file
