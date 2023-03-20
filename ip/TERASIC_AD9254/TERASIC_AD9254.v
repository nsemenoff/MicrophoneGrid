module TERASIC_AD9254(
		input					clk,
		input					clk100,
		input					reset_n,

		// avalon slave port
		input					slave_chip_select_n,
		input		[7:0]		slave_address,
		input					slave_read,
		output	reg	[31:0]	    slave_readdata,
		input					slave_write,
		input		[31:0]	    slave_writedata,

		// avalon master port
		output				master_chip_select_n,
		output	[16:0]	    master_addr, // byte addresss
		output				master_write,
		output	[15:0]	    master_writedata,
		input 				master_waitrequest_n,

		// export
		output				mic_clock,
        output              mic_select,
		input	[31:0]		mic_data
);

// register
// addr 0 write:
//          bit 1: capture flag. rising trigger
//          bit 2: test data
// addr 0 read:
//          bit 0: done flag

////////////////
// avalon slave

reg 			flag_done /*synthesis noprune*/;
reg 			flag_capture /*synthesis noprune*/;
reg [19:0]	    flag_capture_num /*synthesis noprune*/;
reg 			flag_dummy_data /*synthesis noprune*/;
reg 			flag_doppler /*synthesis noprune*/;

always @(posedge clk or negedge reset_n)
begin
	if (~reset_n)
	begin
		flag_doppler <= 1'b0;
		flag_capture <= 1'b0;
		flag_capture_num <= 0;
		flag_dummy_data <= 1'b0;
	end
	else 
	
		case (slave_address)
			1 : 	begin // rx_len
						slave_readdata <= flag_capture_num;
						if (~slave_chip_select_n & slave_write)
							begin
								flag_capture_num <= slave_writedata[19:0];
							end
						end
			0 : begin // other addresses
						slave_readdata <= {28'hdeadbf, 1'b0, flag_out_of_range, flag_overflow, flag_done};
						if (~slave_chip_select_n & slave_read )
							begin
								flag_capture <= 1'b0;
							end
						else if (~slave_chip_select_n & slave_write)
							begin
							    flag_doppler     <= slave_writedata[3];
								flag_dummy_data  <= slave_writedata[2];
								flag_capture     <= slave_writedata[1];
							end
						end
		endcase;
end

////////////////
// gen start capture signal
wire start_capture /* synthesis keep */;
reg pre_flag_capture /*synthesis noprune */;

assign start_capture = ~pre_flag_capture & flag_capture;

always @(posedge clk or negedge reset_n)
begin
	if (~reset_n)
		pre_flag_capture <= 1'b0;
	else
		pre_flag_capture <= flag_capture;
end

////////////////
// state
`define STATE_STANDYBY	2'd0
`define STATE_INIT		2'd1
`define STATE_CAPTURE	2'd2
`define STATE_DONE		2'd3

//wire 			state_capturing;
reg [1:0] 	state /*synthesis noprune*/;

wire read_more;
wire write_more;

reg 		 	flag_out_of_range; // 
reg 		 	flag_overflow;
reg [16:0] 	read_cnt /*synthesis noprune*/;
reg [16:0] 	write_cnt /*synthesis noprune*/;
reg			wait_last_write_done;

reg [31:0]  rx_num;

reg			en_380k;
reg         ff_380k;
reg [31:0]	cnt_380k;
reg [15:0]	cnt_gen;

always @(posedge clk or negedge reset_n)
begin
	if (~reset_n)
		begin
			state <= `STATE_INIT;
			flag_out_of_range <= 1'b0;
			flag_overflow <= 1'b0;
			flag_done <= 1'b0;
			fifo_aclr <= 1'b0;
			ff_380k <= 1'b0;
			cnt_380k <= 0;
			cnt_gen <= 0;
		end
	else if (start_capture)
		begin
			state <= `STATE_INIT;
			read_cnt <= 0;
			write_cnt <= 0;
			flag_out_of_range <= 1'b0;
			flag_overflow <= 1'b0;
			wait_last_write_done <= 1'b0;
			flag_done <= 1'b0;
			fifo_aclr <= 1'b1;
			ff_380k <= 1'b0;
			cnt_380k <= 0;
			cnt_gen <= 0;
		end
	else
   	begin
	
		rx_num <= flag_capture_num;

		// States
		case(state)
			`STATE_STANDYBY: 
				begin
				fifo_aclr <= 1'b1;
				state <= `STATE_STANDYBY;
				end

			`STATE_INIT: // send Tx packet
				begin
					fifo_aclr <= 1'b0;
                    if (clk_counter[8:0]==9'b000000000)
                        state <= `STATE_CAPTURE;
					// reading
					read_cnt <= 0; // continued read
					write_cnt <= 0; // continued read
				end

			`STATE_CAPTURE: // Capture Rx data
				begin
						read_cnt  <= read_cnt + 1; // continued read
						
						// writing
						if (write_cnt == flag_capture_num[15:0])
							state <= `STATE_DONE;
						else
							if ( (clk_counter[9]==1'b0) && (clk_counter[2:0]==3'b000) )
                                write_cnt <= write_cnt + 1; // write new data from Mics
				end

			`STATE_DONE: 
				begin
					flag_done <= 1'b1;
					state <= `STATE_STANDYBY;
				end

		endcase
	end

end

//////////////////////////
// write ADC data to fifo
// ADC --> FIFO
reg  fifo_aclr;
wire fifo_wrreq;
wire fifo_rdreq;
wire fifo_rdempty;
wire fifo_wrfull;
wire [13:0]	fifo_q;

wire doppler_ena;
wire [13:0] doppler_data;

//////////////////////////
// write FIFO data to Memory (MM Master Port)
// FIFO ---> Memory (MM Master Port)

assign fifo_wrreq = read_more & (state == `STATE_CAPTURE); // state_capturing & read_more;
assign fifo_rdreq = master_write & master_waitrequest_n;

assign read_more = (write_cnt < rx_num)?1'b1:1'b0;
assign write_more = (write_cnt < (flag_capture_num))?1'b1:1'b0;

assign master_chip_select_n = (state != `STATE_CAPTURE);
assign master_write = ( state == `STATE_CAPTURE ); //(state == `STATE_CAPTURE); //state_capturing;
assign master_writedata = data_wr; // {1'b0, write_cnt[14:0]}; 
//assign master_writedata = write_cnt[15:0];

assign master_addr = {write_cnt[15:0], 1'b0}; // << 1; // one word = 2 bytes

// TX/RX signals

reg [15:0] clk_counter;
reg clk_state;
reg clk_select;

// -------------------------------------------------- //

always @(posedge clk) 
begin
    clk_counter <= clk_counter + 1;
    clk_state <= clk_counter[3]; // clock for Mics
    clk_select <= clk_counter[9]; // select for Mics
end

// -------------------------------------------------- //

// RX Mic signals
reg [15:0] dout[63:0];
reg [15:0] shiftreg[31:0];

genvar k,j;

generate
    for (k = 0; k < 32; k=k+1) begin:q
        always @(posedge clk) begin
            if (clk_counter[3:0]==5) begin // 7???
                shiftreg[k][15:1] <= shiftreg[k][14:0];
                shiftreg[k][0] <= mic_data[k];
            end
        end
    end
endgenerate    
 
generate
    for (j = 0; j < 32; j = j + 1) begin:r
        always @ (posedge(clk)) begin
                if ((clk_counter[9:4]==20) && (clk_counter[3:0]==9)) /// 27 ????????? // 23
                        dout[2*j+1][15:0] <= shiftreg[j][15:0];
                else if ((clk_counter[9:4]==52) && (clk_counter[3:0]==9)) // 55
                        dout[2*j+0][15:0] <= shiftreg[j][15:0];
        end
    end
endgenerate
// -------------------------------------------------- //

assign mic_clock = !clk_state; // main Mic clock
assign mic_select = clk_select; // main Mic select

reg data_wr_flag;
reg [15:0] data_wr;

always @(posedge clk) 
begin
    data_wr_flag <= 1'b1;

    case (write_cnt[5:0])
        6'd0 : begin data_wr <= {write_cnt[5:0], write_cnt[15:6]}; end //dout[0]; end
        6'd1 : begin data_wr <= {6'b000000, write_cnt[15:6]}; end //dout[1]; end
        6'd2 : begin data_wr <= dout[2]; end
        6'd3 : begin data_wr <= dout[3]; end
        6'd4 : begin data_wr <= dout[4]; end
        6'd5 : begin data_wr <= dout[5]; end
        6'd6 : begin data_wr <= dout[6]; end
        6'd7 : begin data_wr <= dout[7]; end
        6'd8 : begin data_wr <= dout[8]; end
        6'd9 : begin data_wr <= dout[9]; end
        6'd10 : begin data_wr <= dout[10]; end
        6'd11 : begin data_wr <= dout[11]; end
        6'd12 : begin data_wr <= dout[12]; end
        6'd13 : begin data_wr <= dout[13]; end
        6'd14 : begin data_wr <= dout[14]; end
        6'd15 : begin data_wr <= dout[15]; end
        6'd16 : begin data_wr <= dout[16]; end
        6'd17 : begin data_wr <= dout[17]; end
        6'd18 : begin data_wr <= dout[18]; end
        6'd19 : begin data_wr <= dout[19]; end
        6'd20 : begin data_wr <= dout[20]; end
        6'd21 : begin data_wr <= dout[21]; end
        6'd22 : begin data_wr <= dout[22]; end
        6'd23 : begin data_wr <= dout[23]; end
        6'd24 : begin data_wr <= dout[24]; end
        6'd25 : begin data_wr <= dout[25]; end
        6'd26 : begin data_wr <= dout[26]; end
        6'd27 : begin data_wr <= dout[27]; end
        6'd28 : begin data_wr <= dout[28]; end
        6'd29 : begin data_wr <= dout[29]; end
        6'd30 : begin data_wr <= dout[30]; end
        6'd31 : begin data_wr <= dout[31]; end
        6'd32 : begin data_wr <= dout[32]; end
        6'd33 : begin data_wr <= dout[33]; end
        6'd34 : begin data_wr <= dout[34]; end
        6'd35 : begin data_wr <= dout[35]; end
        6'd36 : begin data_wr <= dout[36]; end
        6'd37 : begin data_wr <= dout[37]; end
        6'd38 : begin data_wr <= dout[38]; end
        6'd39 : begin data_wr <= dout[39]; end
        6'd40 : begin data_wr <= dout[40]; end
        6'd41 : begin data_wr <= dout[41]; end
        6'd42 : begin data_wr <= dout[42]; end
        6'd43 : begin data_wr <= dout[43]; end
        6'd44 : begin data_wr <= dout[44]; end
        6'd45 : begin data_wr <= dout[45]; end
        6'd46 : begin data_wr <= dout[46]; end
        6'd47 : begin data_wr <= dout[47]; end
        6'd48 : begin data_wr <= dout[48]; end
        6'd49 : begin data_wr <= dout[49]; end
        6'd50 : begin data_wr <= dout[50]; end
        6'd51 : begin data_wr <= dout[51]; end
        6'd52 : begin data_wr <= dout[52]; end
        6'd53 : begin data_wr <= dout[53]; end
        6'd54 : begin data_wr <= dout[54]; end
        6'd55 : begin data_wr <= dout[55]; end
        6'd56 : begin data_wr <= dout[56]; end
        6'd57 : begin data_wr <= dout[57]; end
        6'd58 : begin data_wr <= dout[58]; end
        6'd59 : begin data_wr <= dout[59]; end
        6'd60 : begin data_wr <= dout[60]; end
        6'd61 : begin data_wr <= dout[61]; end
        6'd62 : begin data_wr <= dout[62]; end
        6'd63 : begin data_wr <= 123; end //dout[63]; end
               
       default : begin
                    data_wr <= write_cnt[15:0];
                  end
     endcase
end

endmodule
