# CP6 sparse-memory service-only OOC synthesis/place/route gate.
# Every project source, include root, and constraint is explicitly listed and
# must resolve below sparse_memory_v1/.  This flow never generates a bitstream.

set script_dir [file dirname [file normalize [info script]]]
set sparse_root [file normalize [file join $script_dir ..]]
set rtl_dir [file join $sparse_root rtl]
set final_report_dir [file join $sparse_root reports cp6]
set build_root [file join $sparse_root build]
set part_name xc7z020clg400-1
set period_ns 10.000
set run_id "service_ooc_[clock format [clock seconds] -gmt true -format %Y%m%dT%H%M%SZ]_[pid]"
set started_utc [clock format [clock seconds] -gmt true \
    -format %Y-%m-%dT%H:%M:%SZ]
set report_dir [file join $build_root "c6so_${run_id}"]
set fixed_summary [file join $final_report_dir cp6_service_ooc_summary.txt]

file mkdir $final_report_dir
file mkdir $build_root
file mkdir $report_dir

proc cp6_atomic_write {path lines} {
    set temporary "${path}.tmp.[pid]"
    set handle [open $temporary wb]
    foreach line $lines {
        puts $handle $line
    }
    close $handle
    file rename -force $temporary $path
}

proc cp6_atomic_publish {source destination} {
    set temporary "${destination}.tmp.[pid]"
    file copy -force $source $temporary
    file rename -force $temporary $destination
}

proc cp6_one_line {text} {
    return [string map [list "\r" " " "\n" " "] $text]
}

proc cp6_sha256 {path} {
    if {[catch {exec certutil.exe -hashfile [file nativename $path] SHA256} \
        output]} {
        error "CP6_HASH_FAIL: [cp6_one_line $output]"
    }
    set compact [string map [list " " "" "\r" "" "\n" ""] $output]
    if {![regexp -nocase {([0-9a-f]{64})} $compact unused digest]} {
        error "CP6_HASH_PARSE_FAIL: $path"
    }
    return [string tolower $digest]
}

set fixed_report_names [list \
    cp6_service_ooc_resolved_inputs.txt \
    cp6_service_utilization_post_synth.rpt \
    cp6_service_timing_post_synth.rpt \
    cp6_service_check_timing_post_synth.rpt \
    cp6_service_utilization_post_route.rpt \
    cp6_service_timing_post_route.rpt \
    cp6_service_setup_paths_post_route.rpt \
    cp6_service_hold_paths_post_route.rpt \
    cp6_service_check_timing_post_route.rpt \
    cp6_service_route_status_post_route.rpt \
    cp6_service_ooc_summary.txt]
cp6_atomic_write $fixed_summary [list \
    checkpoint=CP6 \
    run_id=$run_id \
    started_utc=$started_utc \
    status=IN_PROGRESS \
    gate_pass=0 \
    failure_detail=run_not_completed]
foreach report_name [lrange $fixed_report_names 0 end-1] {
    set fixed_path [file join $final_report_dir $report_name]
    if {[file exists $fixed_path]} {
        file delete -force $fixed_path
    }
}

proc cp6_checked_path {root candidate expected_type kind report_handle} {
    set normalized_root [string trimright \
        [string map {\\ /} [file normalize $root]] /]
    set normalized_path [string map {\\ /} [file normalize $candidate]]
    set root_lower [string tolower $normalized_root]
    set path_lower [string tolower $normalized_path]
    if {$path_lower ne $root_lower &&
        [string first "${root_lower}/" $path_lower] != 0} {
        error "CP6_ISOLATION_FAIL: $kind resolves outside sparse_memory_v1: $normalized_path"
    }
    if {$expected_type eq "file" && ![file isfile $normalized_path]} {
        error "CP6_INPUT_MISSING: $normalized_path"
    }
    if {$expected_type eq "directory" && ![file isdirectory $normalized_path]} {
        error "CP6_INCLUDE_MISSING: $normalized_path"
    }
    if {[file type $normalized_path] eq "link"} {
        error "CP6_ISOLATION_FAIL: symbolic-link input is forbidden: $normalized_path"
    }
    puts $report_handle "$kind=$normalized_path"
    return $normalized_path
}

proc cp6_normalize_text_report {path} {
    set input_file [open $path rb]
    set contents [read $input_file]
    close $input_file
    set contents [string map [list "\r\n" "\n" "\r" "\n"] $contents]
    regsub -all -line {[ \t]+$} $contents "" contents
    set contents "[string trimright $contents "\n"]\n"
    set output_file [open $path wb]
    puts -nonewline $output_file $contents
    close $output_file
}

set cp6_run_failed [catch {

set raw_verilog_sources [list \
    [file join $rtl_dir sparse_memory_dma_v1.v] \
    [file join $rtl_dir sparse_memory_v4_table_v1.v]]
set systemverilog_sources [list \
    [file join $rtl_dir sparse_memory_service_v1.sv]]
set include_files [list \
    [file join $rtl_dir sparse_memory_v4_map_v1.vh]]
set xdc_file [file join $sparse_root constraints \
    sparse_memory_service_v1_cp6_100mhz.xdc]

set resolved_path_report [file join $report_dir \
    cp6_service_ooc_resolved_inputs.txt]
set resolved_handle [open $resolved_path_report w]
puts $resolved_handle "checkpoint=CP6"
puts $resolved_handle "scope=service_only_ooc"
puts $resolved_handle "sparse_root=[string map {\\ /} $sparse_root]"
set checked_include [cp6_checked_path $sparse_root $rtl_dir directory \
    include_dir $resolved_handle]
set checked_verilog_sources [list]
foreach source $raw_verilog_sources {
    lappend checked_verilog_sources [cp6_checked_path $sparse_root $source \
        file verilog $resolved_handle]
}
set checked_systemverilog_sources [list]
foreach source $systemverilog_sources {
    lappend checked_systemverilog_sources [cp6_checked_path $sparse_root \
        $source file systemverilog $resolved_handle]
}
set checked_include_files [list]
foreach include_file $include_files {
    lappend checked_include_files [cp6_checked_path $sparse_root \
        $include_file file include_file $resolved_handle]
}
set checked_xdc [cp6_checked_path $sparse_root $xdc_file file xdc \
    $resolved_handle]
set runner_path [cp6_checked_path $sparse_root [file normalize [info script]] \
    file runner $resolved_handle]
set guarded_design_paths [concat $checked_verilog_sources \
    $checked_systemverilog_sources $checked_include_files \
    [list $checked_xdc]]
set pre_run_hashes [dict create]
foreach guarded_path [concat $guarded_design_paths [list $runner_path]] {
    set digest [cp6_sha256 $guarded_path]
    dict set pre_run_hashes $guarded_path $digest
    puts $resolved_handle "sha256=$digest|$guarded_path"
}
set runner_sha256 [dict get $pre_run_hashes $runner_path]
close $resolved_handle

cd $report_dir
create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
set_property include_dirs [list $checked_include] [current_fileset]
foreach source $checked_verilog_sources {
    read_verilog $source
}
foreach source $checked_systemverilog_sources {
    read_verilog -sv $source
}
read_xdc $checked_xdc

synth_design -top sparse_memory_service_v1 -part $part_name \
    -mode out_of_context -flatten_hierarchy rebuilt

set util_synth_path [file join $report_dir \
    cp6_service_utilization_post_synth.rpt]
set timing_synth_path [file join $report_dir \
    cp6_service_timing_post_synth.rpt]
set check_synth_path [file join $report_dir \
    cp6_service_check_timing_post_synth.rpt]
report_utilization -hierarchical -file $util_synth_path
report_timing_summary -delay_type min_max -max_paths 20 \
    -report_unconstrained -file $timing_synth_path
check_timing -verbose -file $check_synth_path

opt_design
place_design -directive Explore
phys_opt_design
route_design -directive Explore

set util_route_path [file join $report_dir \
    cp6_service_utilization_post_route.rpt]
set timing_route_path [file join $report_dir \
    cp6_service_timing_post_route.rpt]
set setup_route_path [file join $report_dir \
    cp6_service_setup_paths_post_route.rpt]
set hold_route_path [file join $report_dir \
    cp6_service_hold_paths_post_route.rpt]
set check_route_path [file join $report_dir \
    cp6_service_check_timing_post_route.rpt]
set route_status_path [file join $report_dir \
    cp6_service_route_status_post_route.rpt]

report_utilization -hierarchical -file $util_route_path
report_timing_summary -delay_type min_max -max_paths 20 \
    -report_unconstrained -file $timing_route_path
report_timing -delay_type max -max_paths 20 -nworst 1 -sort_by group \
    -file $setup_route_path
report_timing -delay_type min -max_paths 20 -nworst 1 -sort_by group \
    -file $hold_route_path
check_timing -verbose -file $check_route_path
report_route_status -file $route_status_path

set setup_paths [get_timing_paths -delay_type max -max_paths 1 \
    -nworst 1 -quiet]
set hold_paths [get_timing_paths -delay_type min -max_paths 1 \
    -nworst 1 -quiet]
set wns_ns NA
set whs_ns NA
if {[llength $setup_paths] > 0} {
    set wns_ns [get_property SLACK [lindex $setup_paths 0]]
}
if {[llength $hold_paths] > 0} {
    set whs_ns [get_property SLACK [lindex $hold_paths 0]]
}

set utilization_text [report_utilization -return_string]
set slice_luts NA
set slice_registers NA
regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)\s*\|} \
    $utilization_text unused slice_luts
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
    $utilization_text unused slice_registers
set ramb36_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB36E1}]]
set ramb18_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME == RAMB18E1}]]
set dsp_count [llength [get_cells -hierarchical -quiet \
    -filter {REF_NAME =~ DSP48*}]]
set unrouted_count [llength [get_nets -hierarchical -quiet \
    -filter {ROUTE_STATUS == UNROUTED}]]

set check_text [check_timing -return_string]
set no_clock_pins NA
set constant_clock_pins NA
set unconstrained_internal NA
set unconstrained_due_to_constant_clock NA
regexp {There are\s+([0-9]+)\s+register/latch pins with no clock\.} \
    $check_text unused no_clock_pins
regexp {There are\s+([0-9]+)\s+register/latch pins with constant_clock\.} \
    $check_text unused constant_clock_pins
regexp {There are\s+([0-9]+)\s+pins that are not constrained for maximum delay\.} \
    $check_text unused unconstrained_internal
regexp {There are\s+([0-9]+)\s+pins that are not constrained for maximum delay due to constant clock\.} \
    $check_text unused unconstrained_due_to_constant_clock
set route_text [report_route_status -return_string]
set routing_error_nets NA
set routable_nets NA
set fully_routed_nets NA
set incomplete_routable_nets NA
regexp -nocase {# of nets with routing errors[^:]*:\s*([0-9]+)} \
    $route_text unused routing_error_nets
regexp -nocase {# of routable nets[^:]*:\s*([0-9]+)} \
    $route_text unused routable_nets
regexp -nocase {# of fully routed nets[^:]*:\s*([0-9]+)} \
    $route_text unused fully_routed_nets
if {$routable_nets ne "NA" && $fully_routed_nets ne "NA"} {
    set incomplete_routable_nets [expr {$routable_nets - $fully_routed_nets}]
}

set clock_objects [get_clocks -quiet cp6_sparse_service_clk]
set actual_period_ns NA
if {[llength $clock_objects] == 1} {
    set actual_period_ns [get_property PERIOD [lindex $clock_objects 0]]
}

set resources_below_80 0
set service_resources_preserved 0
if {$slice_luts ne "NA" && $slice_registers ne "NA"} {
    set bram36_equivalent [expr {$ramb36_count + ($ramb18_count / 2.0)}]
    set resources_below_80 [expr {$slice_luts < 42560 &&
        $slice_registers < 85120 && $bram36_equivalent < 112.0 &&
        $dsp_count < 176}]
    # The registered narrow products intentionally reduce this service from
    # six DSP48s to four.  Keep an anti-optimization floor, but match the
    # architecture that is actually compiled by this evidence flow.
    set service_resources_preserved [expr {$slice_luts >= 500 &&
        $slice_registers >= 500 && $ramb36_count >= 64 &&
        $dsp_count >= 4}]
} else {
    set bram36_equivalent NA
}

set source_hash_stable 1
foreach guarded_path $guarded_design_paths {
    if {[cp6_sha256 $guarded_path] ne
        [dict get $pre_run_hashes $guarded_path]} {
        set source_hash_stable 0
    }
}
set runner_hash_stable [expr {[cp6_sha256 $runner_path] eq
    $runner_sha256}]

set gate_pass 1
if {$wns_ns eq "NA" || $wns_ns < 0.0} { set gate_pass 0 }
if {$whs_ns eq "NA" || $whs_ns < 0.0} { set gate_pass 0 }
if {$unrouted_count != 0} { set gate_pass 0 }
if {$routing_error_nets eq "NA" || $routing_error_nets != 0} {
    set gate_pass 0
}
if {$routable_nets eq "NA" || $routable_nets <= 0 ||
    $fully_routed_nets eq "NA" || $fully_routed_nets != $routable_nets ||
    $incomplete_routable_nets != 0} {
    set gate_pass 0
}
if {$unconstrained_internal eq "NA" || $unconstrained_internal != 0} {
    set gate_pass 0
}
if {$unconstrained_due_to_constant_clock eq "NA" ||
    $unconstrained_due_to_constant_clock != 0} {
    set gate_pass 0
}
if {$no_clock_pins eq "NA" || $no_clock_pins != 0} { set gate_pass 0 }
if {$constant_clock_pins eq "NA" || $constant_clock_pins != 0} {
    set gate_pass 0
}
if {[llength $clock_objects] != 1 || $actual_period_ns eq "NA" ||
    abs($actual_period_ns - $period_ns) > 0.001} {
    set gate_pass 0
}
if {!$resources_below_80} { set gate_pass 0 }
if {!$service_resources_preserved} { set gate_pass 0 }
if {!$source_hash_stable || !$runner_hash_stable} { set gate_pass 0 }

set summary_path [file join $report_dir cp6_service_ooc_summary.txt]
set summary [open $summary_path w]
puts $summary "checkpoint=CP6"
puts $summary "evidence_type=Vivado_OOC_synthesis_place_route"
puts $summary "design_scope=sparse_memory_service_v1_only"
puts $summary "top=sparse_memory_service_v1"
puts $summary "accelerator_top_included=0"
puts $summary "bitstream_generated=0"
puts $summary "vivado_version=[version -short]"
puts $summary "part=$part_name"
puts $summary "target_frequency_mhz=100"
puts $summary "target_period_ns=$period_ns"
puts $summary "actual_period_ns=$actual_period_ns"
puts $summary "post_route_wns_ns=$wns_ns"
puts $summary "post_route_whs_ns=$whs_ns"
puts $summary "unrouted_nets=$unrouted_count"
puts $summary "routing_error_nets=$routing_error_nets"
puts $summary "routable_nets=$routable_nets"
puts $summary "fully_routed_nets=$fully_routed_nets"
puts $summary "incomplete_routable_nets=$incomplete_routable_nets"
puts $summary "no_clock_pins=$no_clock_pins"
puts $summary "constant_clock_pins=$constant_clock_pins"
puts $summary "unconstrained_internal_endpoints=$unconstrained_internal"
puts $summary "unconstrained_due_to_constant_clock=$unconstrained_due_to_constant_clock"
puts $summary "slice_luts=$slice_luts"
puts $summary "slice_registers=$slice_registers"
puts $summary "ramb36e1_primitives=$ramb36_count"
puts $summary "ramb18e1_primitives=$ramb18_count"
puts $summary "bram36_equivalent=$bram36_equivalent"
puts $summary "dsp48_primitives=$dsp_count"
puts $summary "resources_below_80_percent=$resources_below_80"
puts $summary "service_resources_preserved=$service_resources_preserved"
puts $summary "guarded_design_file_count=[llength $guarded_design_paths]"
puts $summary "runner_sha256=$runner_sha256"
puts $summary "source_hash_stable=$source_hash_stable"
puts $summary "runner_hash_stable=$runner_hash_stable"
puts $summary "run_id=$run_id"
puts $summary "started_utc=$started_utc"
puts $summary "finished_utc=[clock format [clock seconds] -gmt true -format %Y-%m-%dT%H:%M:%SZ]"
puts $summary "status=[expr {$gate_pass ? {PASS} : {FAIL}}]"
puts $summary "gate_pass=$gate_pass"
close $summary

foreach report_path [list $resolved_path_report $util_synth_path \
    $timing_synth_path $check_synth_path $util_route_path \
    $timing_route_path $setup_route_path $hold_route_path \
    $check_route_path $route_status_path $summary_path] {
    cp6_normalize_text_report $report_path
}

puts "CP6_SERVICE_OOC_METRICS wns=$wns_ns unrouted=$unrouted_count unconstrained_internal=$unconstrained_internal LUT=$slice_luts FF=$slice_registers RAMB36=$ramb36_count RAMB18=$ramb18_count DSP=$dsp_count"
if {!$gate_pass} {
    error "CP6_SERVICE_OOC_GATE_FAIL: inspect $summary_path"
}

# Publish current-run evidence only after every fail-closed gate passes.  The
# summary is renamed last so gate_pass=1 can never point at partial reports.
foreach report_name [lrange $fixed_report_names 0 end-1] {
    cp6_atomic_publish [file join $report_dir $report_name] \
        [file join $final_report_dir $report_name]
}
cp6_atomic_publish $summary_path $fixed_summary
puts "CP6_SERVICE_OOC_GATE_PASS"
} cp6_run_message cp6_run_options]

if {$cp6_run_failed} {
    set finished_utc [clock format [clock seconds] -gmt true \
        -format %Y-%m-%dT%H:%M:%SZ]
    set failure_lines [list \
        checkpoint=CP6 \
        evidence_type=Vivado_OOC_synthesis_place_route \
        design_scope=sparse_memory_service_v1_only \
        run_id=$run_id \
        started_utc=$started_utc \
        finished_utc=$finished_utc \
        status=FAIL \
        gate_pass=0 \
        failure_detail=[cp6_one_line $cp6_run_message] \
        workdir=[string map {\\ /} $report_dir]]
    foreach {field variable_name} {
        post_route_wns_ns wns_ns
        post_route_whs_ns whs_ns
        unrouted_nets unrouted_count
        routing_error_nets routing_error_nets
        routable_nets routable_nets
        fully_routed_nets fully_routed_nets
        incomplete_routable_nets incomplete_routable_nets
        no_clock_pins no_clock_pins
        constant_clock_pins constant_clock_pins
        unconstrained_internal_endpoints unconstrained_internal
        unconstrained_due_to_constant_clock unconstrained_due_to_constant_clock
        slice_luts slice_luts
        slice_registers slice_registers
        ramb36e1_primitives ramb36_count
        ramb18e1_primitives ramb18_count
        dsp48_primitives dsp_count
        source_hash_stable source_hash_stable
        runner_hash_stable runner_hash_stable
    } {
        if {[info exists $variable_name]} {
            lappend failure_lines "$field=[set $variable_name]"
        }
    }
    cp6_atomic_write $fixed_summary $failure_lines
    return -options $cp6_run_options $cp6_run_message
}
