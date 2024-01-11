# operating conditions and boundary conditions #
set cycle  10.0;  # modify your clock cycle here #

create_clock -period $cycle [get_ports  clk]
set_dont_touch_network      [get_clocks clk]
set_fix_hold                [get_clocks clk]
set_ideal_network           [get_ports clk]
set_clock_uncertainty  0.1  [get_clocks clk]
set_clock_latency      0.5  [get_clocks clk]


set_input_delay  [ expr 2.5 ] -clock clk [all_inputs]
set_output_delay [ expr 2.5 ] -clock clk [all_outputs] 
set_load         0.05     [all_outputs]

set_operating_conditions  -max_library slow -max slow
set_wire_load_model -name tsmc13_wl10 -library slow                        

set_max_fanout 20 [all_inputs]
