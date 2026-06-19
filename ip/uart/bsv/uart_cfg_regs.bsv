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

package uart_cfg_regs;
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
import Clocks::*;
import BUtils::*;
import ConfigReg ::*;
import device_common::*;
import ConcatReg ::*;
`ifdef IQC
   import iqc::*;
`endif

export RS232 (..);
export UserInterface (..);
export mkuart_user;

interface UserInterface#(numeric type addr_width ,numeric type data_width, numeric type depth);
   method ActionValue#(Tuple2#(Bit#(data_width),Bool)) read_req (Bit#(addr_width) addr,
   AccessSize size);
   method ActionValue#(Bool) write_req(Bit#(addr_width) addr, Bit#(data_width) data,
   AccessSize size);
   `ifndef uart_clk_gate_en
      (*always_ready, always_enabled*)
   `endif
   interface RS232 io;
   `ifndef uart_clk_gate_en
      (*always_ready, always_enabled*)
   `endif
   method Bit#(1) interrupt;
endinterface

module mkuart_user#(parameter Bit#(16) baudrate, Bit#(2) stopbits, Bit#(2) parity)
   (UserInterface#(addr_width,data_width, depth))
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

   Reg#(Bit#(16)) baud_value <- mkRegA(baudrate);
   Reg#(Bit#(16)) rg_delay_control <- mkRegA(0);
   Reg#(StopBits) rg_stopbits <- mkRegA(unpack(stopbits));
   `ifdef uart_modem
      Reg#(Bit#(5)) rg_modem <- mkRegA(30);
      Reg#(Bit#(1)) auto_rts <- mkRegA(0);
      Reg#(Bit#(1)) rg_stickparity <- mkRegA(0);
   `endif
   Reg#(Parity) rg_parity <- mkRegA(unpack(parity));
   Reg#(Bit#(6)) rg_charsize <- mkRegA(8);
   `ifdef IQC
      Reg#(Bit#(8)) rg_qual_cycles <- mkRegA(0);
      Ifc_iqc#(1) iqc <- mkiqc(rg_qual_cycles);
   `endif
   Reg#(UInt#(TLog#(TAdd#(depth,1)))) rg_rx_threshold <- mkRegA(unpack('1)*4/5);

   //Reg#(Bit#(9)) rg_control= concatReg3(rg_charsize, rg_parity, rg_stopbits);
   /* Instantiating a UART module with the respective parameters */
   UART#(depth) uart <- mkUART(`ifdef uart_modem auto_rts,rg_modem, `endif rg_charsize, rg_parity, rg_stopbits, baud_value, rg_delay_control `ifdef uart_modem ,rg_stickparity `endif );  // charasize,Parity,Stop Bits,BaudDIV, Delay_control
   Reg#(Bit#(16)) rg_interrupt_en <- mkRegA(0);
   Reg#(Bit#(16)) rg_interrupt_raw <- mkRegA(0);
   Reg#(Bit#(4)) error_status_register <- mkConfigRegA(0);
   Clock cc <- exposeCurrentClock;
   Reset crst <- exposeCurrentReset; 
   SyncBitIfc#(Bit#(1)) sync_sin <- mkSyncBitToCC(cc, crst);
   /* Combines all the status bits into one complete status register */
   let status= { `ifdef uart_modem uart.modem_status[7:1] `else 7'd0 `endif , uart.error_status, error_status_register, pack(uart.receiver_full), pack(uart.receiver_not_empty),
   pack(uart.transmittor_full), pack(uart.transmittor_empty) };  //Remember uart.modem_status[0]
   /* Sends the value in the threshold register for every instance so that it is verifed if threshold is reached. */
   rule rl_send_rx_threshold;
      uart.rx_threshold(rg_rx_threshold);
   endrule

   rule rl_capture_error_bits(uart.new_error_bits matches tagged Valid .bits);
      error_status_register <= bits;
   endrule
   rule rl_capture_interrupt_bits;
      // bit 1 inverted: status[1]=tx_full, irq bit 1=tx_not_full
      rg_interrupt_raw <= rg_interrupt_raw | {status[15:2], ~status[1], status[0]};
   endrule

   `ifdef uart_modem
      /* If Loopback is enabled connects the transmitter section and the receiver section together */
      rule rl_loopback(rg_modem[0]==1'b1);
         uart.rs232.sin(uart.rs232.sout);
         uart.rs232.cts(uart.rs232.rts);
         uart.rs232.dsr(uart.rs232.dtr);
         uart.rs232.ri(uart.rs232.out1);
         uart.rs232.dcd(uart.rs232.out2);
         //the MODEM Control output pins are forced to their inactive state (high).
      endrule
   `endif

   /* Used for reading data from the respective register by using its address */
   method ActionValue#(Tuple2#(Bit#(data_width),Bool)) read_req (Bit#(addr_width) addr,
   AccessSize size);
   /* Returns the status register's data */
   if ( addr[5:0]==`StatusReg)begin
         return tuple2(duplicate(status),True);
      end
      /* Returns the receiver register's data if data is present and DCD, RI , DSR and CTS are active */
      else if (addr[5:0]==`RxReg) begin
            Bit#(32) data =0;
            if (uart.receiver_not_empty `ifdef uart_modem && uart.modem_status[3:0] == 4'b1111 `endif )
               data <- uart.tx.get;
            `logLevel( uart, 1, $format("UART read data: %h %c", data, data))
            data= data >> (32-rg_charsize);
            return tuple2(duplicate(data),True);
         end
         /* Returns the control register's data */
         else if ( addr[5:0]==`ControlReg `ifdef uart_modem`endif ) begin
               return tuple2(duplicate({ `ifdef uart_modem 14'b0,uart.modem_status[0] , auto_rts,rg_modem `else 5'd0 `endif ,rg_charsize, pack(rg_parity), pack(rg_stopbits), `ifdef uart_modem rg_stickparity `else 1'b0 `endif }),True);
            end
            /* Returns the baud register's data */
            else if (addr[5:0]==`BaudReg) begin
                  return tuple2(duplicate(baud_value),True);
               end
               /* Returns the delay register's data */
               else if (addr[5:0]==`DelayReg) begin
                     return tuple2(duplicate(rg_delay_control),True);
                  end
                  /* Returns the interrupt enable register's data */
                  else if (addr[5:0]==`InterruptRaw) begin
                        return tuple2(zeroExtend(rg_interrupt_raw), True);
		  end
                  else if (addr[5:0]==`InterruptStatus) begin
                        return tuple2(zeroExtend(rg_interrupt_raw & rg_interrupt_en), True);
		  end
                  else if (addr[5:0]==`InterruptEn) begin
                        return tuple2(duplicate(rg_interrupt_en), True);
                     end
                     /* If Input Qualification Cycles are implemented returns the qualification register's value */
                     `ifdef IQC
                        else if (addr[5:0]==`IQ_cycles) begin
                              return tuple2(duplicate(rg_qual_cycles), True);
                           end
                        `endif
                        /* Returns the threshold register's data */
                        else if (addr[5:0]==`RX_Threshold) begin
                              Bit#(8) lv1= zeroExtend(pack(rg_rx_threshold));
                              return tuple2(duplicate(lv1), True);
                           end
                           else
                           return tuple2(?,False);
endmethod
   /* Used for writing data from the respective register by using its address */
   method ActionValue#(Bool) write_req(Bit#(addr_width) addr, Bit#(data_width) data,
   AccessSize size);
   /* Call the put method of the TX Register using the data . */
   if (addr[5:0]==`TxReg) begin
         uart.rx.put(truncate(data));  //putting write data in the UART
         `logLevel( uart, 0, $format("Sending ASCII: %c", data[7:0]))
         return True;
      end
      /* Write the baud value from the input data */
      else if (addr[5:0]==`BaudReg) begin
            baud_value <= truncate(data);
            return True;
         end
         /* Write the delay register value from the input data. */
         else if (addr[5:0]==`DelayReg) begin
               rg_delay_control <= truncate(data);
               return True;
            end
            /* Write the individual controls parts from the input data. */
            else if (addr[5:0]==`ControlReg) begin
                  `ifdef uart_modem
                     auto_rts <= data[16];
                     rg_modem <= data[15:11];
                  `endif
                  `ifdef uart_modem
                     rg_stickparity <= data[0];
                  `endif
                  rg_charsize <= data[10:5];
                  rg_parity <= unpack(data[4:3]);
                  rg_stopbits <= unpack(data[2:1]);
                  //rg_control<= truncate(data);
                  return True;
               end
               /* Write the interrupt enable register value from the input data. */
               else if (addr[5:0]==`InterruptRaw) begin
	       	       rg_interrupt_raw <= rg_interrupt_raw ^ {6'd0,data[9:0]};
		       return True;
	       end
               else if (addr[5:0]==`InterruptEn) begin
                     rg_interrupt_en <= {6'd0, data[9:0]};
                     return True;
                  end
                  /* Clears the status register value based on the input data. */
                  else if (addr[5:0]==`StatusReg) begin
                        `ifdef uart_modem
                           Bit#(12) clear_status_errors= data[15:4];
                        `else
                           Bit#(5) clear_status_errors= data[8:4];
                        `endif
                        uart.clear_status(clear_status_errors);
                        error_status_register <= error_status_register & clear_status_errors[3:0];
                        return True;
                     end
                     /* If Input Qualification Cycles are implemented writes the qualification register's value from the input data */
                     `ifdef IQC
                        else if (addr[5:0]==`IQ_cycles) begin
                              rg_qual_cycles <= truncate(data);
                              return True;
                           end
                        `endif
                        /* Clears the transmitter and receiver FIFOs based on the bits set and writes the Receiver Threshold value. */
                        else if (addr[5:0]==`RX_Threshold) begin
                              `ifdef uart_modem
                                 if (data[7] == 1'b1)
                                    begin
                                       uart.transmittor_clear;
                                       uart.receiver_clear;
                                    end
                                    else
                                    begin
                                       if (data[5] == 1'b1)
                                          uart.transmittor_clear;
                                       if (data[6] == 1'b1)
                                          uart.receiver_clear;
                                    end
                              `endif
                              rg_rx_threshold <= unpack(truncate(data));
                              return True;
                           end
                           else
                           return False;
endmethod

   interface RS232 io;
      /* Receives data from any other UART compatible device to our UART. */
      method Action sin(Bit#(1) x) `ifdef uart_modem if (rg_modem[0]==1'b0) `endif ;
         sync_sin.send(x);
         `ifdef IQC
            let lv_qualified_inputs <- iqc.qualify(sync_sin.read);
         `else
            let lv_qualified_inputs = sync_sin.read;
         `endif
         uart.rs232.sin(lv_qualified_inputs);
      endmethod
      /* Sends out data from the UART to the other UART compatible device. */
      method sout= uart.rs232.sout;
      method sout_en= uart.rs232.sout_en;
      `ifdef uart_modem
         /*Clear To Send pin is an input pin which takes in a signal to a modem and decides if it is ready to receive data
         depending upon the same */
         method Action cts(Bit#(1) x) if (rg_modem[0]==1'b0);
         uart.rs232.cts(x);
      endmethod
         /* Data Set Ready pin is an input pin which takes in a signal to a modem and decides if it can expect incoming data
         for reception. */
         method Action dsr(Bit#(1) x) if (rg_modem[0]==1'b0);
         uart.rs232.dsr(x);
      endmethod
         /*Ring Indicator pin is an input pin which takes in a signal to a modem and decides if it can expect incoming data
         for reception. */
         method Action ri(Bit#(1) x) if (rg_modem[0]==1'b0);
         uart.rs232.ri(x);
      endmethod
         /*Data Carrier Detect pin is an input pin which takes in a signal to a modem and decides if it can expect incoming
         data for reception. */
         method Action dcd(Bit#(1) x) if (rg_modem[0]==1'b0);
         uart.rs232.dcd(x);
      endmethod
         /* Request to Send is an output pin which gives out a signal to a modem to start sending data. */
         method Bit#(1) rts();
         if (rg_modem[0]==1'b0)
            return uart.rs232.rts();
            else
            return 1;
      endmethod
         /* Data Terminal Ready is an output pin which gives out a signal to a modem that it is ready to receive data. */
         method Bit#(1) dtr();
         if (rg_modem[0]==1'b0)
            return uart.rs232.dtr();
            else
            return 1;
      endmethod
         /* Both OUT1 and OUT2 are ordinary output pins used to store arbitrary outputs. */
         method Bit#(1) out1();
         if (rg_modem[0]==1'b0)
            return uart.rs232.out1();
            else
            return 1;
      endmethod
         method Bit#(1) out2();
         if (rg_modem[0]==1'b0)
            return uart.rs232.out2();
            else
            return 1;
      endmethod
      `endif
      method Bit#(2) dma_ready;
      return uart.rs232.dma_ready;
   endmethod
   endinterface
   method Bit#(1) interrupt;
   `ifdef uart_modem
      /* If Modem Status Interrupt is enabled and either DCTS,DDSR,DDCD,and TERI are enabled send interrupt */
      if (uart.modem_status[7:4] != 4'b0000 && rg_interrupt_en[9] == 1)
         return 1;
         /* If any other interrupt as well as the status is enabled return 1 */
         else
      `endif
      return |(rg_interrupt_raw[8:0] & rg_interrupt_en[8:0]);
endmethod

endmodule:mkuart_user

endpackage:uart_cfg_regs
