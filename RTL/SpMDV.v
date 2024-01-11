module SpMDV 
(
	input clk,
	input rst,

	// Input signals
	input start_init,
    input [7 : 0] raw_input,
    input raw_data_valid,
	input w_input_valid,

	// Ouput signals
    output reg raw_data_request,
	output reg ld_w_request,
	output reg [21 : 0] o_result,
	output reg o_valid
	
);

// Register and wires assignments
reg [4:0] currState, nextState;
reg [7:0] value_op_w;
wire [7:0] value_op_w1, value_op_w2, value_op_w3;
reg [7:0] position_op_w, pre_value_op_w;
wire [7:0] position_op_w1, position_op_w2, position_op_w3;
wire [7:0] bias_op_w, token_op_w;
reg CEN1, CEN2, CEN3, CEN4, CEN5, CEN6, WEN1, WEN2, WEN3, WEN4, WEN5, WEN6, cenb, wenb, cent, went;
reg [11:0] address;
reg [7:0] bias_address, pre_bias_address, bias_ctr, bias_ctr_nxt;
reg [11:0] vec_entry_ctr, vec_entry_ctr_nxt;
reg [13:0] element_ctr, element_ctr_nxt;
reg [11:0] token_address;
reg [21:0] Output [255:0], answer;
reg [21:0] total, total_nxt;
reg [1:0] bank_ctr, bank_ctr_nxt;
reg [7:0] ans_entry, ans_entry_nxt;
reg [3:0] token_ctr, token_ctr_nxt;
reg[7:0] row_ctr, row_ctr_nxt;

// Parameters
parameter IDLE = 4'd0, INPUT_WEIGHT_VALUE = 4'd1, INPUT_WEIGHT_POS = 4'd2, INPUT_BIAS = 4'd3,  VECTOR = 4'd4, CAL = 4'd5, OUTPUT = 4'd6;

// FSM
always@(posedge clk or negedge rst)
begin
    if (~rst) begin
		currState <= nextState;
		element_ctr <= element_ctr_nxt;
		bias_ctr <= bias_ctr_nxt;
		vec_entry_ctr <= vec_entry_ctr_nxt;
		bank_ctr <= bank_ctr_nxt;
		ans_entry <= ans_entry_nxt;
		token_ctr <= token_ctr_nxt;
		total <= total_nxt;
		row_ctr <= row_ctr_nxt;
	end
    else begin
		currState <= IDLE;
		element_ctr <= 12'd0;
		bias_ctr <= 8'd0;
		vec_entry_ctr <= 8'd0;
		bank_ctr <= 2'd0;
		ans_entry <= 8'd0;
		token_ctr <= 4'd0;
		row_ctr <= 8'd0;
		total <= 0;
	end
end



always@(*)begin
	case (currState)
	IDLE                 : nextState = INPUT_WEIGHT_VALUE;
	INPUT_WEIGHT_VALUE   : nextState = ( element_ctr == 12287 ) ? INPUT_WEIGHT_POS : INPUT_WEIGHT_VALUE;
	INPUT_WEIGHT_POS     : nextState = ( element_ctr == 12287 ) ?       INPUT_BIAS : INPUT_WEIGHT_POS;
	INPUT_BIAS           : nextState = ( bias_ctr == 255      ) ?           VECTOR : INPUT_BIAS;
	VECTOR               : nextState = ( vec_entry_ctr == 4095) ?              CAL : VECTOR;
	CAL                  : nextState = ( element_ctr == 12289 ) ?           OUTPUT : CAL;
	OUTPUT               : nextState = ( ans_entry == 255     ) ?           CAL : OUTPUT;
	default              : nextState = IDLE;
	endcase
end

// SRAM for input weight values
sram_4096x8 WV1(.A(address), .D(raw_input), .Q(value_op_w1), .CLK(clk), .CEN(CEN1), .WEN(WEN1));
sram_4096x8 WV2(.A(address), .D(raw_input), .Q(value_op_w2), .CLK(clk), .CEN(CEN2), .WEN(WEN2));
sram_4096x8 WV3(.A(address), .D(raw_input), .Q(value_op_w3), .CLK(clk), .CEN(CEN3), .WEN(WEN3));

// SRAM for input weight positions
sram_4096x8 WP1(.A(address), .D(raw_input), .Q(position_op_w1), .CLK(clk), .CEN(CEN4), .WEN(WEN4));
sram_4096x8 WP2(.A(address), .D(raw_input), .Q(position_op_w2), .CLK(clk), .CEN(CEN5), .WEN(WEN5));
sram_4096x8 WP3(.A(address), .D(raw_input), .Q(position_op_w3), .CLK(clk), .CEN(CEN6), .WEN(WEN6));

// SRAM for 16 input vectors
sram_4096x8 M4(.A(token_address), .D(raw_input), .Q(token_op_w), .CLK(clk), .CEN(cent), .WEN(went));

// SRAM for input bias
sram_256x8 B1(.A(bias_address), .D(raw_input), .Q(bias_op_w), .CLK(clk), .CEN(cenb), .WEN(wenb));

// Sequential Circuit

// Input
always@(posedge clk or negedge rst) begin  // not sure if wen needs to be specified to avoid latch
	if (~rst) begin
		if (currState == INPUT_WEIGHT_VALUE) begin

			if (start_init == 1)begin
				if (element_ctr <12286) ld_w_request <= 1'd1;
				else ld_w_request <= 1'd0;
			end
			else begin
				ld_w_request <= 1'd0;
				// CEN1 <= 1'd1;
				// CEN2 <= 1'd1; // not sure if needed, 
				// CEN3 <= 1'd1;
			end

			if (ld_w_request == 1) begin
				// address <= element_ctr % 4096;
				if (element_ctr < 4095) begin
					CEN1 <= 1'd0;
					WEN1 <= 1'd0;
					CEN2 <= 1'd1;
					CEN3 <= 1'd1; 
				end
				else if (element_ctr >= 4095 && element_ctr < 8191) begin
					CEN2 <= 1'd0;
					WEN2 <= 1'd0;
					CEN1 <= 1'd1;
					CEN3 <= 1'd1;
				end
				else begin
					CEN3 <= 1'd0;
					WEN3 <= 1'd0;
					CEN2 <= 1'd1;
					CEN1 <= 1'd1;
				end
			end
			else begin
				CEN1 <= 1'd1;
				CEN2 <= 1'd1;
				CEN3 <= 1'd1;
			end

		end
		
		else if ( currState == INPUT_WEIGHT_POS ) begin
			if (start_init == 1 )begin
				if (element_ctr <12286) ld_w_request <= 1'd1;
				else ld_w_request <= 1'd0;
			end
			else begin
				ld_w_request <= 1'd0;
				// CEN4 <= 1'd1;
				// CEN5 <= 1'd1;
				// CEN6 <= 1'd1;
			end
			if (ld_w_request == 1) begin
				// address <= element_ctr % 4096;
				if (element_ctr < 4095) begin
					CEN4 <= 1'd0;
					WEN4 <= 1'd0;
					CEN5 <= 1'd1;
					CEN6 <= 1'd1;
				end
				else if (element_ctr >= 4095 && element_ctr < 8191) begin
					CEN5 <= 1'd0;
					WEN5 <= 1'd0;
					CEN4 <= 1'd1;
					CEN6 <= 1'd1;
				end
				else begin
					CEN6 <= 1'd0;
					WEN6 <= 1'd0;
					CEN4 <= 1'd1;
					CEN5 <= 1'd1;
				end
			end
			else begin
				CEN4 <= 1'd1;
				CEN5 <= 1'd1;
				CEN6 <= 1'd1;
				WEN6 <= 1'd0;
				WEN4 <= 1'd0;
				WEN5 <= 1'd0;

			end
		end

		else if ( currState == INPUT_BIAS )begin
			if (start_init == 1)begin
				if ( bias_ctr < 254) ld_w_request <= 1'd1;
				else ld_w_request <= 1'd0;
			end
			else ld_w_request <= 1'd0;
			if ( ld_w_request == 1)begin
				// bias_address <= bias_ctr;
				cenb <= 1'd0;
				wenb <= 1'd0;
			end
			else begin
				cenb <= 1'd1;
				wenb <= 1'd0;
			end
		end

		else if ( currState == VECTOR )begin
			if (vec_entry_ctr < 4094) raw_data_request <= 1'd1;
			else raw_data_request <= 1'd0;
			if (raw_data_request == 1)begin
				// token_address <= vec_entry_ctr;
				cent <= 1'd0;
				went <= 1'd0;
			end
			else begin
				cent <= 1'd1;
				went <= 1'd0;
			end
		end

		else if ( currState == CAL ) begin
			// address <= element_ctr % 4096;
			// bias_address <= {bank_ctr, position_op_w};
			// token_address <= {token_ctr, bank_ctr, position_op_w};
			cenb <= 1'd0;
			wenb <= 1'd1;
			cent <= 1'd0;
			went <= 1'd1;
			pre_value_op_w <= value_op_w;
			pre_bias_address <= bias_address;
			if (element_ctr < 4095) begin
				CEN1 <= 1'd0;
				WEN1 <= 1'd1;
				CEN2 <= 1'd1;
				CEN3 <= 1'd1; 

				// position_op_w <= position_op_w1;
				CEN4 <= 1'd0;
				WEN4 <= 1'd1;
				CEN5 <= 1'd1;
				CEN6 <= 1'd1;
			end
			else if (element_ctr >= 4095 && element_ctr < 8191) begin
				// value_op_w <= value_op_w2;
				CEN2 <= 1'd0;
				WEN2 <= 1'd1;
				CEN1 <= 1'd1;
				CEN3 <= 1'd1; 

				// position_op_w <= position_op_w2;
				CEN5 <= 1'd0;
				WEN5 <= 1'd1;
				CEN4 <= 1'd1;
				CEN6 <= 1'd1;
			end
			else begin
				// value_op_w <= value_op_w3;
				CEN3 <= 1'd0;
				WEN3 <= 1'd1;
				CEN2 <= 1'd1;
				CEN1 <= 1'd1;

				// position_op_w <= position_op_w3;
				CEN6 <= 1'd0;
				WEN6 <= 1'd1;
				CEN4 <= 1'd1;
				CEN5 <= 1'd1;
			end
		end
		else begin
			ld_w_request <= 1'd0;
			pre_value_op_w <= pre_value_op_w;
			CEN1 <= 1'd1;
			CEN2 <= 1'd1;
			CEN3 <= 1'd1;
			CEN4 <= 1'd1;
			CEN5 <= 1'd1;
			CEN6 <= 1'd1;
			cenb <= 1'd1;
			cent <= 1'd1;
			WEN1 <= 1'd1;
			WEN2 <= 1'd1;
			WEN3 <= 1'd1;
			WEN4 <= 1'd1;
			WEN5 <= 1'd1;
			WEN6 <= 1'd1;
			wenb <= 1'd1;
			went <= 1'd1;
		end
	end
	else begin
		raw_data_request <= 1'd0;
		ld_w_request <= 1'd0;
		pre_value_op_w <= pre_value_op_w;
		CEN1 <= 1'd1;
		CEN2 <= 1'd1;
		CEN3 <= 1'd1;
		CEN4 <= 1'd1;
		CEN5 <= 1'd1;
		CEN6 <= 1'd1;
		cent <= 1'd1;
		cenb <= 1'd1;
		WEN1 <= 1'd1;
		WEN2 <= 1'd1;
		WEN3 <= 1'd1;
		WEN4 <= 1'd1;
		WEN5 <= 1'd1;
		WEN6 <= 1'd1;
		wenb <= 1'd1;
		went <= 1'd1;
	end
end

// SRAM address assignments
always@(*)begin
	// address
	if (currState == INPUT_WEIGHT_POS || currState == INPUT_WEIGHT_VALUE || currState == CAL)begin
		address = element_ctr % 4096;
	end
	else address = 12'd0;
	
	// bias address
	if (currState == INPUT_BIAS)begin
		bias_address = bias_ctr;
	end
	else if (currState == CAL)begin
		bias_address = row_ctr;
	end
	else bias_address = 8'd0;

	// token address
	if (currState == VECTOR)begin
		token_address = vec_entry_ctr;
	end
	else if (currState == CAL)begin
		token_address = {token_ctr, bank_ctr, position_op_w[5:0]};
	end
	else token_address = 12'd0;
end

// select output of SRAM
always@(*)begin
	if (element_ctr < 4095) begin
		value_op_w = value_op_w1;
		position_op_w = position_op_w1;
	end
	else if (element_ctr >= 4095 && element_ctr < 8191) begin
		value_op_w = value_op_w2;
		position_op_w = position_op_w2;
	end
	else begin
		value_op_w = value_op_w3;
		position_op_w = position_op_w3;
	end
end

// Calculate and Save	
always@(*)begin
	if (currState == CAL && element_ctr >= 2)begin
		answer = pre_value_op_w * token_op_w; // shift?
		if ( (element_ctr-30) % 48 == 0 && element_ctr != 0 ) total_nxt = total + answer + {10'd0,bias_op_w,4'd0};
		else total_nxt = total + answer;
	end
	else total_nxt = 22'd0;

end


// Output
always @(posedge clk) begin
	if (currState == OUTPUT)begin
		o_valid <= 1'd1;
		o_result <= Output[ans_entry];
	end
	else o_valid <= 1'd0;
	
end


always@(posedge clk) begin
	if (currState == CAL)begin
		if ((element_ctr-50) % 48 == 0 && element_ctr != 0) Output[row_ctr-1] <= total;
		else Output[row_ctr-1] <= 0;
	end
end




// Combinational Circuit for counters

always@(*)begin

	// Counters of input weight
	if (currState == INPUT_WEIGHT_VALUE || currState == INPUT_WEIGHT_POS)begin
		if (element_ctr == 12287) element_ctr_nxt = 14'd0;
		else if (w_input_valid == 1) element_ctr_nxt = element_ctr + 1;
		else element_ctr_nxt = element_ctr;
	end
	else if (currState == CAL)begin
		if (cenb == 0) element_ctr_nxt = element_ctr + 1;
		else element_ctr_nxt = element_ctr;
	end
	else element_ctr_nxt = 14'd0;
	
	// Counters of input bias
	if (currState == INPUT_BIAS) begin
		if (w_input_valid == 1) bias_ctr_nxt = bias_ctr + 1;
		else bias_ctr_nxt = bias_ctr;
	end
	else bias_ctr_nxt = 8'd0;

	// Counters of vector state
	if (currState == VECTOR)begin
		if (raw_data_valid == 1) vec_entry_ctr_nxt = vec_entry_ctr + 1;
		else vec_entry_ctr_nxt = vec_entry_ctr;
	end
	else vec_entry_ctr_nxt = 12'd0;

	// CAL bank ctr
	if (currState == CAL)begin
		if (bank_ctr == 3) bank_ctr_nxt = 2'd0;
		else if (element_ctr>=1) bank_ctr_nxt = bank_ctr + 1;
		else bank_ctr_nxt = bank_ctr;
	end
	else begin
		bank_ctr_nxt = 2'd0;
	end

	// CAL row_ctr
	if (currState == CAL)begin
		if (row_ctr == 255) row_ctr_nxt = 8'd0;
		else if (element_ctr % 47 == 0 )begin
			if (element_ctr != 0) row_ctr_nxt = row_ctr + 1;
			else row_ctr_nxt = row_ctr;
		end
		else row_ctr_nxt = row_ctr;
	end
	else begin
		row_ctr_nxt = 8'd0;
	end
	// CAL token ctr
	if (currState == CAL)begin
		if (element_ctr == 12289) token_ctr_nxt = token_ctr + 1;
		else token_ctr_nxt = token_ctr;
	end
	else if (currState == IDLE) token_ctr_nxt = 4'd0;
	else begin
		token_ctr_nxt = token_ctr;
	end

	// OUTPUT answer entry counter
	if (currState == OUTPUT)begin
		if (o_valid == 1'd1) ans_entry_nxt = ans_entry + 1;
		else ans_entry_nxt = ans_entry;
	end
	else ans_entry_nxt = 8'd0;

end


endmodule