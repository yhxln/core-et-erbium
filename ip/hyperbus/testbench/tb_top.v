// Copyright 2017 Gnarly Grey LLC

// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:

// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
// CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// SPDX-License-Identifier: MIT
// Modifications Copyright (c) 2026 Ainekko, Co.

module tb_top;
// Inputs
	reg i_clk;
	reg i_rstn;
	reg i_cfg_access;
	reg i_mem_valid;
	reg [3:0] i_mem_wstrb;
	reg [31:0] i_mem_addr;
	reg [31:0] i_mem_wdata;

	// Outputs
	wire o_mem_ready;
	wire [31:0] o_mem_rdata;
	wire o_csn0;
	wire o_csn1;
	wire o_clk;
	wire o_clkn;
	wire o_resetn;

	// Bidirs
	wire [7:0] io_dq;
	wire io_rwds;
hbc_wrapper hbc (
    .i_clk(i_clk), 
    .i_rstn(i_rstn), 
    .i_cfg_access(i_cfg_access), 
    .i_mem_valid(i_mem_valid), 
    .o_mem_ready(o_mem_ready), 
    .i_mem_wstrb(i_mem_wstrb), 
    .i_mem_addr(i_mem_addr), 
    .i_mem_wdata(i_mem_wdata), 
    .o_mem_rdata(o_mem_rdata), 
    .o_csn0(o_csn0), 
    .o_csn1(o_csn1), 
    .o_clk(o_clk), 
    .o_clkn(o_clkn), 
    .io_dq(io_dq), 
    .io_rwds(io_rwds), 
    .o_resetn(o_resetn)
    );

    wire [7:0] dq_out;
    wire [7:0] dq_in;
    wire dq_oen,rwds_out,rwds_oen;
    assign io_rwds=rwds_oen? rwds_out:1'bZ;
    assign io_dq=dq_oen ? dq_out:8'hZZ;
hyperbus hyperram (
.cs_n(o_csn0),
.clk(o_clk),
.clk_n(o_clkn), // Not used internally

.dq_in(io_dq),
.dq_out(dq_out),
.dq_oen(dq_oen),
.rwds_in(io_rwds),
.rwds_out(rwds_out),
.rwds_oen(rwds_oen),
// Bus side signals
// CSR Signals
.reg_initial_latency(4'h6),
.rst_n(o_resetn)
);

initial begin
	i_clk=0;
	i_rstn = 0;
	$dumpfile("waves.vcd");
	for(integer i=0;i<4;i = i+1) $dumpvars(0,hyperram.wr[i]);
	$dumpvars;
	#20 i_rstn=1;
	forever begin
		i_clk=#5 ~i_clk;
	end
end

endmodule
