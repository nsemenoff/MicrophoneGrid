`timescale 1 ns / 1 ps

module CIC_one_step ( clk, din, dout, ena );
parameter IN_SIZE=1;
parameter OUT_SIZE=8;

input clk;
wire clk;
input [IN_SIZE-1:0] din;
wire [IN_SIZE-1:0] din;
output [OUT_SIZE-1:0] dout;
wire [OUT_SIZE-1:0] dout;
input ena;
wire ena;

localparam MAX_VAL = 2**(OUT_SIZE-1);
localparam MIN_VAL = -2**(OUT_SIZE-1);

reg [OUT_SIZE-1:0] result;
reg [OUT_SIZE-1:0] old_din;
reg [OUT_SIZE-1:0] delay1;
reg [OUT_SIZE-1:0] delay2;
reg [OUT_SIZE-1:0] delay3;
reg [OUT_SIZE-1:0] delay4;

always @(posedge clk)
begin
    if (ena) begin
            if (IN_SIZE==1) begin
                if (din)
 //                   if ((old_din + 1)<MAX_VAL)
                        old_din <= old_din + 1;
 //                   else 
 //                       old_din <= MAX_VAL;
                else 
 //                   if ((old_din - 1)>MIN_VAL)
                        old_din <= old_din - 1;
 //                   else
 //                       old_din <= MIN_VAL;
            end
            else if ((old_din + din)>MAX_VAL)
                    old_din <= MAX_VAL; // old_din + din;
                else if ((old_din + din)<MIN_VAL)
                    old_din <= MIN_VAL; // old_din + din;
                else
                    old_din <= old_din + din;
        
        result <= old_din - delay4;
        delay1 <= old_din;
        delay2 <= delay1;
        delay3 <= delay2;
        delay4 <= delay3;
    end
end

assign dout = result;

endmodule
