/*
Copyright (c) 2018, IIT Madras All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted
provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions
  and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of
  conditions and the following disclaimer in the documentation and/or other materials provided
  with the distribution.
* Neither the name of IIT Madras nor the names of its contributors may be used to endorse or
  promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

SPDX-License-Identifier: BSD-3-Clause
Modifications Copyright (c) 2026 Ainekko, Co.
*/

package uart_axi;
`include "Logger.bsv"
`include "uart.defines"

import AXI4_Lite_Types::*;
import AXI4_Lite_Fabric::*;
import AXI4_Types::*;
import AXI4_Fabric::*;
import Semi_FIFOF::*;
import RS232_modified::*;
import GetPut::*;
import FIFO::*;
import BUtils::*;
import device_common::*;
import ConcatReg ::*;
import uart_cfg_regs::*;

export RS232 (..);
export Ifc_uart_axi4lite (..);
export mkuart_axi4lite;

interface Ifc_uart_axi4lite#(numeric type addr_width,
   numeric type data_width,
   numeric type user_width,
   numeric type depth);
   // AXI4-Lite slave write-address channel
   (*always_ready, always_enabled, prefix=""*)
   method Action axi_awvalid(
   (*port="axi_awvalid"*) Bool awvalid,
   (*port="axi_awaddr"*) Bit#(addr_width) awaddr,
   (*port="axi_awsize"*) Bit#(2) awsize,
   (*port="axi_awuser"*) Bit#(user_width) awuser,
   (*port="axi_awprot"*) Bit#(3) awprot);
   (*always_ready, result="axi_awready"*) method Bool axi_awready;

   // AXI4-Lite slave write-data channel
   (*always_ready, always_enabled, prefix=""*)
   method Action axi_wvalid(
   (*port="axi_wvalid"*) Bool wvalid,
   (*port="axi_wdata"*) Bit#(data_width) wdata,
   (*port="axi_wstrb"*) Bit#(TDiv#(data_width,8)) wstrb);
   (*always_ready, result="axi_wready"*) method Bool axi_wready;

   // AXI4-Lite slave write-response channel
   (*always_ready, result="axi_bvalid"*) method Bool axi_bvalid;
   (*always_ready, result="axi_bresp"*) method Bit#(2) axi_bresp;
   (*always_ready, always_enabled, prefix=""*)
   method Action axi_bready((*port="axi_bready"*) Bool bready);

   // AXI4-Lite slave read-address channel
   (*always_ready, always_enabled, prefix=""*)
   method Action axi_arvalid(
   (*port="axi_arvalid"*) Bool arvalid,
   (*port="axi_araddr"*) Bit#(addr_width) araddr,
   (*port="axi_arsize"*) Bit#(2) arsize,
   (*port="axi_aruser"*) Bit#(user_width) aruser,
   (*port="axi_arprot"*) Bit#(3) arprot);
   (*always_ready, result="axi_arready"*) method Bool axi_arready;

   // AXI4-Lite slave read-data channel
   (*always_ready, result="axi_rvalid"*) method Bool axi_rvalid;
   (*always_ready, result="axi_rresp"*) method Bit#(2) axi_rresp;
   (*always_ready, result="axi_rdata"*) method Bit#(data_width) axi_rdata;
   (*always_ready, always_enabled, prefix=""*)
   method Action axi_rready((*port="axi_rready"*) Bool rready);

   (*always_ready, always_enabled*)
   (*prefix=""*) interface RS232 io;
   (*always_ready, always_enabled*)
   (*prefix=""*) method Bit#(1) interrupt;
endinterface

module mkuart_axi4lite#(parameter Bit#(16) baudrate,
   parameter Bit#(2) stopbits, parameter Bit#(2) parity `ifdef testmode ,Bool test_mode `endif )
   (Ifc_uart_axi4lite#(addr_width,data_width,user_width, depth))
   provisos(Mul#(32, a__, data_width),
   Add#(d__, 8, data_width),
   Mul#(8, b__, data_width),
   Mul#(4, f__, data_width),
   Add#(c__, 32, data_width),
   Add#(g__, 16, data_width),
   Mul#(16, h__, data_width),
   Add#(i__, 9, data_width),
   Add#(2, e__, depth),
   Add#(j__, TLog#(TAdd#(depth, 1)), 8),
   Add#(k__, TLog#(TAdd#(depth, 1)), data_width),
   Add#(l__, 1, data_width)
);

   AXI4_Lite_Slave_Xactor_IFC#(addr_width,data_width,user_width) s_xactor <- mkAXI4_Lite_Slave_Xactor();
   UserInterface#(addr_width,data_width, depth) user_ifc <- mkuart_user(baudrate, stopbits, parity);

   rule perform_read;
      let rd_req <- pop_o(s_xactor.o_rd_addr);
      let {rdata, succ} <- user_ifc.read_req(rd_req.araddr, unpack(truncate(rd_req.arsize)));
      let lv_resp = AXI4_Lite_Rd_Data {rresp: succ?AXI4_LITE_OKAY:AXI4_LITE_SLVERR,
                                        rdata: rdata, ruser: ?};
      s_xactor.i_rd_data.enq(lv_resp);
   endrule

   rule perform_write;
      let wr_req  <- pop_o(s_xactor.o_wr_addr);
      let wr_data <- pop_o(s_xactor.o_wr_data);
      let succ <- user_ifc.write_req(wr_req.awaddr, wr_data.wdata, unpack(wr_req.awsize));
      let lv_resp = AXI4_Lite_Wr_Resp {bresp: succ?AXI4_LITE_OKAY:AXI4_LITE_SLVERR, buser: ?};
      s_xactor.i_wr_resp.enq(lv_resp);
   endrule

   interface io = user_ifc.io;

   // AXI write-address channel
   method Action axi_awvalid(awvalid, awaddr, awsize, awuser, awprot);
      s_xactor.axi_side.m_awvalid(awvalid, awaddr, awsize, awuser, awprot);
   endmethod
   method axi_awready = s_xactor.axi_side.m_awready;

   // AXI write-data channel
   method Action axi_wvalid(wvalid, wdata, wstrb);
      s_xactor.axi_side.m_wvalid(wvalid, wdata, wstrb);
   endmethod
   method axi_wready = s_xactor.axi_side.m_wready;

   // AXI write-response channel
   method axi_bvalid = s_xactor.axi_side.m_bvalid;
   method axi_bresp  = s_xactor.axi_side.m_bresp;
   method Action axi_bready(bready);
      s_xactor.axi_side.m_bready(bready);
   endmethod

   // AXI read-address channel
   method Action axi_arvalid(arvalid, araddr, arsize, aruser, arprot);
      s_xactor.axi_side.m_arvalid(arvalid, araddr, arsize, aruser, arprot);
   endmethod
   method axi_arready = s_xactor.axi_side.m_arready;

   // AXI read-data channel
   method axi_rvalid = s_xactor.axi_side.m_rvalid;
   method axi_rresp  = s_xactor.axi_side.m_rresp;
   method axi_rdata  = s_xactor.axi_side.m_rdata;
   method Action axi_rready(rready);
      s_xactor.axi_side.m_rready(rready);
   endmethod

   method interrupt = user_ifc.interrupt;
endmodule:mkuart_axi4lite

endpackage:uart_axi
