set dcp_path {C:/tmp/zv5-sparse-sim/zephyr_full_bd/checkpoints/zephyr_full_post_synth.dcp}
open_checkpoint $dcp_path
puts "TOP=[get_property TOP [current_design]]"
proc print_immediate_modules {label} {
  puts "${label}_BEGIN"
  foreach cell [get_cells] {
    if {![get_property IS_PRIMITIVE $cell]} {
      puts "CELL=[get_property NAME $cell] REF=[get_property REF_NAME $cell]"
    }
  }
  puts "${label}_END"
}

current_instance {zephyr_full_i/accel/inst/u_accelerator}
print_immediate_modules ACCELERATOR_MODULES
current_instance u_pe_memory_subsystem
print_immediate_modules PE_MEMORY_MODULES
current_instance ..
current_instance u_realtime_layernorm_coordinator
print_immediate_modules LAYERNORM_MODULES
close_design
exit
