# Elaborated-hierarchy gate for the connected PE Array datapath.
#
# Usage:
#   vivado -mode batch -source check_pe_array_datapath_hierarchy.tcl \
#       -tclargs /absolute/path/to/rtl/pe_array

if {$argc >= 1} {
    set pe_root [file normalize [lindex $argv 0]]
} else {
    set pe_root [file normalize \
        [file join [file dirname [file normalize [info script]]] ../..]]
}

set baseline_rtl [file join $pe_root baseline v1 rtl]
set wrapper_rtl [file join $pe_root rtl top pe_array_datapath.v]
set report_dir [file join $pe_root reports pe_array_datapath]

set verilog_2001_sources [list \
    [file join $baseline_rtl nonlinear pe_sigmoid_lut_255.v] \
    [file join $baseline_rtl postprocess pe_gate_postprocess.v] \
    [file join $baseline_rtl pe pe_membrane_sequencer.v] \
    [file join $baseline_rtl stream pe_output_serializer.v] \
    [file join $baseline_rtl stream pe_shared_requant_engine.v] \
    [file join $baseline_rtl index pe_spike_decision.v] \
    [file join $baseline_rtl index pe_active_index_writer.v] \
    [file join $baseline_rtl pe pe_cdf_sequencer.v] \
    $wrapper_rtl]

set historical_systemverilog_sources [list \
    [file join $baseline_rtl arithmetic pe_requant_lane.sv] \
    [file join $baseline_rtl arithmetic pe_local_requant_bank_4lane.sv] \
    [file join $baseline_rtl pe pe_hybrid_mac.sv]]

foreach source_file [concat $historical_systemverilog_sources \
                            $verilog_2001_sources] {
    if {![file isfile $source_file]} {
        error "Missing PE Array datapath source: $source_file"
    }
}

file mkdir $report_dir
create_project -in_memory -part xc7z020clg400-1

foreach source_file $historical_systemverilog_sources {
    read_verilog -sv $source_file
}
foreach source_file $verilog_2001_sources {
    read_verilog $source_file
}

# -rtl preserves the structural module boundaries without mapping arithmetic.
synth_design -rtl -top pe_array_datapath -part xc7z020clg400-1 \
    -flatten_hierarchy none

proc get_ref_cells {ref_name} {
    # Vivado appends __parameterized<N> for a source module elaborated with a different parameter set.
    # Match only that generated suffix rather than accepting an arbitrary REF_NAME prefix.
    return [get_cells -hierarchical -quiet -filter "REF_NAME == $ref_name || REF_NAME =~ ${ref_name}__parameterized*"]
}

proc count_ref_name {ref_name} {
    return [llength [get_ref_cells $ref_name]]
}

set expected_refs [list \
    [list pe_hybrid_mac 16] \
    [list pe_local_requant_bank_4lane 1] \
    [list pe_requant_lane 5] \
    [list pe_gate_postprocess 1] \
    [list pe_sigmoid_lut_255 1] \
    [list pe_membrane_sequencer 1] \
    [list pe_output_serializer 1] \
    [list pe_shared_requant_engine 1] \
    [list pe_spike_decision 1] \
    [list pe_active_index_writer 1] \
    [list pe_cdf_sequencer 1]]

set forbidden_refs [list \
    pe_active_index_buffer \
    pe_array_controller \
    pe_array_top \
    pe_gsn_cell \
    complex_mac \
    complex_multiplier]

set failed 0
set hierarchy_report [open \
    [file join $report_dir hierarchy_elaborated.txt] w]
puts $hierarchy_report "top=pe_array_datapath"
puts $hierarchy_report "part=xc7z020clg400-1"

foreach expected $expected_refs {
    set ref_name [lindex $expected 0]
    set expected_count [lindex $expected 1]
    set actual_count [count_ref_name $ref_name]
    puts $hierarchy_report \
        "$ref_name expected=$expected_count actual=$actual_count"
    if {$actual_count != $expected_count} {
        puts stderr \
            "HIERARCHY ERROR: $ref_name expected=$expected_count actual=$actual_count"
        set failed 1
    }
}

foreach ref_name $forbidden_refs {
    set actual_count [count_ref_name $ref_name]
    puts $hierarchy_report "$ref_name forbidden actual=$actual_count"
    if {$actual_count != 0} {
        puts stderr \
            "HIERARCHY ERROR: forbidden $ref_name actual=$actual_count"
        set failed 1
    }
}

# Preserve the physical split: four lanes below Local RQ and one below Shared RQ.
# Parent prefixes are derived from their elaborated cells, independent of wrapper instance naming.
set local_bank_cells [get_ref_cells pe_local_requant_bank_4lane]
set shared_engine_cells [get_ref_cells pe_shared_requant_engine]
set local_lane_count 0
set shared_lane_count 0
set unclassified_lane_count 0
set local_bank_prefix ""
set shared_engine_prefix ""
if {[llength $local_bank_cells] == 1} {
    set local_bank_prefix "[get_property NAME [lindex $local_bank_cells 0]]/"
}
if {[llength $shared_engine_cells] == 1} {
    set shared_engine_prefix "[get_property NAME [lindex $shared_engine_cells 0]]/"
}
puts $hierarchy_report ""
puts $hierarchy_report "requant_lane_placement:"
foreach lane_cell [get_ref_cells pe_requant_lane] {
    set lane_name [get_property NAME $lane_cell]
    set lane_ref [get_property REF_NAME $lane_cell]
    if {$local_bank_prefix ne "" && [string first $local_bank_prefix $lane_name] == 0} {
        incr local_lane_count
        set lane_owner "local_bank"
    } elseif {$shared_engine_prefix ne "" && [string first $shared_engine_prefix $lane_name] == 0} {
        incr shared_lane_count
        set lane_owner "shared_engine"
    } else {
        incr unclassified_lane_count
        set lane_owner "unclassified"
    }
    puts $hierarchy_report "$lane_name ref=$lane_ref owner=$lane_owner"
}
puts $hierarchy_report "local_bank_lanes expected=4 actual=$local_lane_count"
puts $hierarchy_report "shared_engine_lanes expected=1 actual=$shared_lane_count"
puts $hierarchy_report "unclassified_lanes expected=0 actual=$unclassified_lane_count"
if {$local_lane_count != 4 || $shared_lane_count != 1 || $unclassified_lane_count != 0} {
    puts stderr "HIERARCHY ERROR: requant lane placement local/shared/unclassified=$local_lane_count/$shared_lane_count/$unclassified_lane_count"
    set failed 1
}

# Preserve a complete REF_NAME inventory to make unexpected hierarchy visible
# without making this checker depend on Vivado-generated primitive names.
array set ref_inventory {}
foreach cell [get_cells -hierarchical -quiet] {
    set ref_name [get_property REF_NAME $cell]
    if {$ref_name ne ""} {
        if {![info exists ref_inventory($ref_name)]} {
            set ref_inventory($ref_name) 0
        }
        incr ref_inventory($ref_name)
    }
}
puts $hierarchy_report ""
puts $hierarchy_report "ref_name_inventory:"
foreach ref_name [lsort [array names ref_inventory]] {
    puts $hierarchy_report "$ref_name=$ref_inventory($ref_name)"
}
close $hierarchy_report

if {$failed} {
    error "PE Array datapath hierarchy does not match the approved physical architecture"
}

puts "PE_ARRAY_DATAPATH_HIERARCHY_PASS hybrid=16 local_bank=1 requant_lanes=5 shared_engine=1"
close_project
exit
