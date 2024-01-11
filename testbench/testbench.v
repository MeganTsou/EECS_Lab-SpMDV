`timescale 1ns/100ps
// `timescale 1ns/1ns
`define CYCLE       10.0     // CLK period.
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   300000
`define RST_DELAY   2

`define ld_mi 4'd0
`define ld_weight_value 4'd1
`define ld_bias_value 4'd2
`define ld_weight_index 4'd3

`define weight_file "../testbench/init/weight.dat"
`define nzv_file "../testbench/init/nzv_index.dat"
`define bias_file "../testbench/init/bias.dat"
`define weight_len 12288
`define bias_len 256

`define in_token_file "../testbench/in_token/token_g1.dat"
`define in_token_2_file "../testbench/in_token/token_g2.dat"
`define out_token_file "../testbench/result/out_g1.dat"
`define out_token_2_file "../testbench/result/out_g2.dat"
`define token_total_len 32

`ifdef tb0
    // Model weight
`endif

`define SDFFILE "../SYN/Netlist/SpMDV_syn.sdf"  // Modify your sdf file name


module testbed;

parameter weight_bw = 8;
parameter bias_bw = 8;
parameter feature_bw = 8;
parameter weight_index_bw = 6;
parameter d_control_mode_bw = 5;

reg clk, reset;

// Operation
reg [feature_bw-1 : 0] golden_check_mem [0:65535];
reg [feature_bw-1 : 0] golden_check [0:3];
reg [feature_bw-1 : 0] data_in_mem [0:3];



reg [feature_bw*2+6 - 1 : 0] golden_out_mem[0:65535];
reg [feature_bw-1 : 0] raw_data_mem [0 : 65535];
reg [feature_bw-1 : 0] weight_mem [0:65535];

reg [feature_bw-1 : 0] raw_input_w, raw_input, raw_input_sel;
reg [feature_bw-1 : 0] current_weight;
reg [feature_bw-1 : 0] weight_input;
reg raw_data_valid, raw_data_valid_w;
reg w_input_valid_w, w_input_valid;
reg start_init;
wire raw_data_request, ld_w_request;
wire [feature_bw*2+6 - 1 : 0] o_result;
wire o_valid;

// Write out waveform file
`ifdef FSDBOFF
`else
    initial begin
        $dumpfile("SpMDV.vcd");
        $dumpvars;
    end
`endif

// For gate-level simulation only
`ifdef SDF
    initial $sdf_annotate(`SDFFILE, u_SpMDV);
    initial #1 $display("SDF File %s were used for this simulation.", `SDFFILE);
`endif

SpMDV u_SpMDV (
    
    .clk(clk),
	.rst(reset),

    .start_init(start_init),
    // Data input
    .raw_input(raw_input),
    .raw_data_valid(raw_data_valid),
    .raw_data_request(raw_data_request),
    .w_input_valid(w_input_valid),
    .ld_w_request(ld_w_request),

    .o_result(o_result),
    .o_valid(o_valid)
);

// initial $readmemh(`out_token_file, out_token_mem);

// Clock generation
initial clk = 1'b0;
always begin #(`CYCLE/2) clk = ~clk; end

integer i, j, k;

initial begin
    # (`MAX_CYCLE * `CYCLE);
    $display("Error! Runtime exceeded!");
    $finish;
end


reg w_check_f, w_temp_check_f, load_finish_flag;
initial begin
    start_init = 0;
    load_finish_flag = 0;
    task_reset;
    
    // Init weight
    @(negedge clk);
    start_init = 1;
    $readmemh(`weight_file, weight_mem);
    load_weight_task(`weight_len,`ld_weight_value);
    $display("All weight values have been transmitted !");

    $readmemh(`nzv_file, weight_mem);
    load_weight_task(`weight_len,`ld_weight_index);
    $display("All possitions of non-zero values have been transmitted !");

    $readmemh(`bias_file, weight_mem);
    load_weight_task(`bias_len,`ld_bias_value);
    $display("All bias values have been transmitted !");

    @(negedge clk);
    load_finish_flag = 1;
    start_init = 0;
end


integer token_id, pos_id, raw_addr, group_offset;
integer compute_s_time, compute_e_time;
initial begin
    $timeformat(-9,1);
    token_id = 0;
    pos_id = 0;
    group_offset = 0;
    $readmemh(`in_token_file, raw_data_mem);
    raw_data_valid_w = 0;
    while (token_id < `token_total_len) begin
        @(negedge clk);
        raw_data_valid_w = 0;
        if (raw_data_request) begin
            if (token_id == 0 && pos_id == 0) begin
                compute_s_time = $time;
            end

            raw_addr = (token_id - group_offset) * 256 + pos_id;
            raw_input_w = raw_data_mem[raw_addr];
            raw_data_valid_w = 1;

            if (pos_id == 255) begin
                pos_id = 0;
                token_id = token_id + 1;
                // $display("Token %d", token_id);
            end
            else begin
                pos_id = pos_id + 1;
                token_id = token_id;
            end
            
            if (token_id == 16 && pos_id == 0) begin
                group_offset = 16;
                $readmemh(`in_token_2_file, raw_data_mem);
            end
            if ((token_id == 16 || token_id == 32)&& pos_id == 0) begin
                $display("All elements of 16 dense vectors have been transmitted !");
            end
        end
    end
    @(negedge clk);
    @(negedge clk);
end


always @ (*) begin
    raw_input_sel = raw_input_w;
    if (~load_finish_flag)
        raw_input_sel = weight_input;
end

always @ (posedge clk or posedge reset) begin
    if (reset) begin
        raw_data_valid <= 0;
        w_input_valid <= 0;
        raw_input <= 0;
    end
    else begin
        raw_data_valid <= raw_data_valid_w;
        w_input_valid <= w_input_valid_w;
        raw_input <= raw_input_sel;
    end
end

integer out_token_id, out_pos, out_addr, o_group_offset;
integer check_token_num, current_data_num;                    // For check if receive all dense vector or not
reg out_check_temp, out_check, total_check;
initial begin
    out_token_id = 0;
    out_pos = 0;
    out_addr = 0;
    o_group_offset = 0;
    out_check = 1;
    total_check = 1;

    check_token_num = 4096;
    $readmemh(`out_token_file, golden_out_mem);
    while (out_token_id < `token_total_len) begin
        @(negedge clk);
        if (o_valid) begin
            current_data_num = token_id * 256 + pos_id;
            if (~(current_data_num>=check_token_num)) begin
                $display("Wrong! You can't output the result before fetching 16 dense vectors!");
                $finish;
            end

            out_check_temp = o_result === golden_out_mem[out_addr - o_group_offset];
            if (~out_check_temp) begin
                $display("Wrong answer ! token {%2d}, position {%3d}, output = {%h}, golden = {%h}",out_token_id, out_pos, o_result, golden_out_mem[out_addr - o_group_offset]);
            end
            out_check = out_check_temp & out_check;
            total_check = total_check & out_check;
            out_addr = out_addr + 1;

            if (out_pos == 255) begin
                if (out_check)
                    $display("Token {%2d} is correct !", out_token_id);
                out_pos = 0;
                out_token_id = out_token_id + 1;
                out_check = 1;
            end
            else begin
                out_pos = out_pos + 1;
            end

            if (out_token_id == 16 && out_pos == 0) begin
                check_token_num = 8192;
                o_group_offset = 16 * 256;
                $readmemh(`out_token_2_file, golden_out_mem);
            end
        end
    end

    compute_e_time = $time;

    if (total_check) begin
                                                                                                                                      
$display("                              .........       ..                                                                              ");
$display("                             .:::--===--::......--:                                                                           ");
$display("                         ...:--:---=======----:::=+-.                                                                         ");
$display("                      ..::-=+===---==++***####***++++-.  .                                                                    ");
$display("                      .-+++++#==+-=+====+++***####**#*=:-=-.::                                                                ");
$display("                     .:=++-++=----=+***++++***##########**+==-.                                                               ");
$display("                   ..-----===++---==+**#**+*######**#*####*+=:.                                                               ");
$display("                  .:-==-==+*###+=+===+++++*##*######***###*+=-..                                                              ");
$display("                 .:-====+*+*####+***+***++***+**#**#***###**+==.                                                              ");
$display("                .:---=++++****###+***++*+==+++=+******#*##*#*+=:                                                              ");
$display("                ::---=++**+***#***+++++++=-==+=+++*+*++*#####*=-                                                              ");
$display("                :---=+++++++++++==-------========+++*+++*##*#***.                                                             ");
$display("                -:-=+++=====----:::::::::----=======+***+#******:                                                             ");
$display("                --====+===---:::::::::::::::---=======++#+*#**#+.                                                             ");
$display("                :-=+++==----::::::::::::.:::::::----=++++***#*#*.                                                             ");
$display("                .--*====----:::::::::::.::::::::::--==+*++******:                                                             ");
$display("                 .=+-===----::::::::::...:::::::::----+*******+=:.                                                            ");
$display("                  -+-====--::::::::::.....:::::::::---==+*****=--:                                                            ");
$display("                  .=-====--:::::::::::::--=======-------=+**+=----.                                                           ");
$display("                   :--===--::::::::::=+*++==--:---:::---=+*+-:==--.                                                           ");
$display("                    --++**++==------====++*##**+--::::---=*------:                                                            ");
$display("                     -**++++**+*=-::--=++===---:::::::---=*---:::                                                             ");
$display("                     .-=*****++#*=:::------:::::::::::---=+-::::.                                                             ");
$display("                      :+====-==++-:::::::::::::.::::::--==-=-:-:                                                              ");
$display("                      .===----===-::::::::::::::..:::---===-==+-                                                              ");
$display("                      .==--::-===-::::::------:::::-------====+-                                                              ");
$display("                       -=----=++=-::::---::::--==----------==-=.                                                              ");
$display("                       :=====+*++=-------:::::-----------=-==--.                                                              ");
$display("                        =+==**++++==-==-:--=-=*=-::--------=---:                                                              ");
$display("                        .++==++**+=+=+--::.::--::::------===----                                                              ");
$display("                         .=+=-==*#--:...:-==-::::::-----==----::..                                                            ");
$display("                          .-+=--=++++====--::::::-------==----:::...                                                          ");
$display("                            .-====++====----::::::----=+==:-:=-:::...                                                         ");
$display("                              .-=========---:::::---====--:-:=-:::.:...                                                       ");
$display("                                :==-===----::::--=====------:-=--:::..:--:.....                                               ");
$display("                                 .-===---------=====------::--==---::..--:....::............   .............                  ");
$display("                                   :=+==========---------::-::-=+---::.:::........::::::::............::..:......             ");
$display("                                  . .=++******+====------::--::-=+=--:.:..:::.::::::::::...:............::::....::.           ");
$display("                                    :-+**+++**++===------------::-++=-::..:::::::::::::..:::....::::::::::::::....:::.        ");
$display("                              ..:::-+=++++++++++====-----------:::-+++::-----::--:::::..:::...:::::::---:---:::::.:::-.       ");
$display("                            .:---:--*=*+*+++++==+=======--------::.=+*--=------:::::::::-::::-------------------:-::::-.      ");
$display("                           :::::---:*+++++*++===========------::::::+*++==-:::::..:::--------------------------==--===-:.     ");
$display("                        ..::::::::-:-+*++++**+=---===++=--::::::::::-*+=--:::::.::::::----------==-------------====--====:    ");
$display("                    ...:::::::::::::::--====+==-------:::::::::::::::=+-::::::..:::::-:::::----==-===---------==========++=.  ");
$display("                ..:::::::::::::::::::::::::::::::::::::::::::::::::::.=-:::::::.:::::::..::-=---==-================++++==++-  ");
$display("             ..::::::::::::::::::::::::::::::::::::::::::::::::::::::-::::::..:--::::::::-------===---===========+++++++=+++. ");
$display("           .::::::::::::::::::::::::::::::::::::::::::::::::::::::::--::::..::--::::::::::::::---===---=======++++++++++++++: ");
$display("         .::::::::::::::::::::::::::::::::::::::::::::::::::::::::----::::.:---::::::::::::::::---==-==+==++++++++++++++++++: ");
$display("       .:::::::::::::::::::::::::::::::::::::::::::::::::::::::::-==--:::::---:::::::::::::::::----==+===+++++++++++++**++++: ");
$display("      .:::::::::::::::::::::::::::::::::::::::::::::::::::::::::-=+++=-::---:::::.::--::::::::--:--======++++++++++++*+++++=: ");
$display("    .::-::::::::::::::::::::::::::::::::::::::::::::::--:--:::--++**+++===-:::::::---:::::::--::::-====+++++*++++++****++++-. ");
$display("     --::::::::-::::::::-------::::::::::::::::::::--------:--=++++++***+=-::::::==-::::::--::::::-=+++++++++++++*******++-:. ");
$display("    .---:::-------:::------:::::::::::::::::::::::-------:---=+***+**#*+*+=-:::-=-::::::---:::::--=+****++++******++****++-:. ");
$display("    :==--::---------------:::::-::::::--::::::::-------------=**####*++****+==+*=-::::--=-::::--=+*****++++++++++++***++=+=-. ");
$display("    :===-:------=-------::---:::---:-----------------------------+***************+=---==:::::-=+*####*****##***++***+====+=:. ");
$display("   .====--::-----------------------------------------------------=+*#****###********+++=--:--=+++***#####***#******+=--==+=.  ");
$display("   :====+------=------------------------------------------------========++*###**#**++++*+==+++++++++****###**=::::::::::...   ");
$display("   -==-=+===--==------------------------------------------------=========--==+==++++*++++==++==+=+++++++*+*++:                ");
$display("  .-====++=+=-+=----------------------------------------------==================+-====+============++=++++++-                 ");
$display("  :=====+++=*=+==--------------------------------------------============-=====+==========================+=.                 ");
$display("  -=====++*=+*+=====----------------------------------------===================+-==========================:  .               ");
$display(" .=======+*+=*#+======------------------------------------====================+=-==========================                   ");
    $display("Computation start at %d ns, end at %d ns, total time = %d ns", compute_s_time, compute_e_time, compute_e_time - compute_s_time);
    end
    else begin
        $display("Something wrong !");
    end

    #(`CYCLE * 10);
    $finish;
end


// load weight
integer l_i, l_j, w_addr;
task load_weight_task; 
    input [31:0] data_len;
    input [3:0] load_type;

begin
    w_input_valid_w = 0;
    l_i = 0;
    w_addr = 0;
    weight_input = 0;
    while (l_i < data_len) begin
        @(negedge clk);
        w_input_valid_w = 0;
        if (ld_w_request) begin
            w_input_valid_w = 1;
            current_weight = weight_mem[w_addr];
            case(load_type)
                `ld_weight_index: begin
                    weight_input = {{{feature_bw - weight_index_bw}{1'b0}}, current_weight[weight_index_bw*1- 1 : weight_index_bw * 0]};
                end
                `ld_weight_value: begin
                    weight_input = {{{feature_bw - weight_bw}{1'b0}}, current_weight[weight_bw*1- 1 : weight_bw * 0]};
                end
                `ld_bias_value: begin
                    weight_input = {{{feature_bw - bias_bw}{1'b0}}, current_weight[bias_bw*1- 1 : bias_bw * 0]};
                end
            endcase


            w_addr = w_addr + 1;
            l_i = l_i + 1;
        end
    end
    @(negedge clk);
    w_input_valid_w = 0;
end
endtask

// Reset generation
task task_reset; begin
    # ( 0.75 * `CYCLE);
    reset = 1;    
    # ((`RST_DELAY - 0.25) * `CYCLE);
    reset = 0;    
end endtask

endmodule
