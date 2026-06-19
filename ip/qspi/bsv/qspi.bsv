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

package qspi;

import ConcatReg ::*;
import Semi_FIFOF :: *;
import FIFOLevel::*;
import AXI4_Types:: *;
import AXI4_Fabric:: *;
import AXI4_Lite_Types :: *;
import AXI4_Lite_Fabric :: *;
import Connectable ::*;
import FIFO::*;
import FIFOF::*;
import Clocks::*;
import SpecialFIFOs::*;
import ClientServer::*;
import MIMO_MODIFY::*;
import DefaultValue :: *;
import device_common::*;
//	`include "defined_parameters.bsv"
`include "qspi.defines"
`include "Logger.bsv"  // for logging display statements.
import ConfigReg::*;
import Vector::*;
import UniqueWrappers :: * ;
import DReg::*;
import BUtils::*;

typedef struct {
   Bit#(awidth) addr;
   Bit#(3) burst_size;
   Bit#(dwidth) wdata;
} Write_req#(numeric type awidth, numeric type dwidth) deriving (Bits, Eq);

typedef struct {
   Bit#(awidth) addr;
   Bit#(3) burst_size;
} Read_req#(numeric type awidth) deriving (Bits, Eq);

typedef struct {
   Bit#(awidth) addr;
   Bit#(3) burst_size;
   Bit#(8) burst_len;
   Bit#(2) arburst;
} Read_req_axi#(numeric type awidth) deriving (Bits, Eq);

typedef struct {
   AXI4_Lite_Resp rsp;
   Bit#(dwidth) rdata;
} Rd_resp#(numeric type dwidth) deriving (Bits, Eq);

typedef struct {
   AXI4_Lite_Resp rsp;
   Bit#(dwidth) rdata;
   Bool last;
} Rd_resp_axi#(numeric type dwidth) deriving (Bits, Eq);
`ifndef qspi_clk_gate_en
   (*always_ready, always_enabled*)
`endif
interface QSPI_out;
   `ifndef qspi_clk_gate_en (* always_ready, result="clk_o" *) `endif method bit clk_o;
      `ifndef qspi_clk_gate_en (* always_ready, result="io_o" *) `endif method Bit#(4) io_o;
         `ifndef qspi_clk_gate_en (* always_ready, result="io_enable" *) `endif method Bit#(4) io_enable;
            `ifndef qspi_clk_gate_en (* always_ready, always_enabled *) `endif method Action io_i ((* port="io_i" *) Bit#(4) io_in);  // in
               `ifndef qspi_clk_gate_en (* always_ready, result="ncs_o" *) `endif method bit ncs_o;
               endinterface

               interface Ifc_qspi_controller#(numeric type addr_width,
                  numeric type data_width,
                  numeric type user_width);
                  interface QSPI_out io;
                  method Action write_req(Maybe#(Write_req#(addr_width,data_width)) wr_req);
                  method Maybe#(AXI4_Lite_Resp) write_resp;
                  method Action rd_req(Maybe#(Read_req#(addr_width)) req);
                  method Maybe#(Rd_resp#(data_width)) rd_resp;
                  method Bit#(1) interrupts;  // 0=TOF, 1=SMF, 2=Threshold, 3=TCF, 4=TEF 5 = request_ready
                  `ifdef simulate
                     method Phase curphase;
                     `endif
                  endinterface

                  function Reg#(t) readOnlyReg(t r);
                     return (interface Reg;
                        method t _read = r;
                        method Action _write(t x) = noAction;
                        endinterface);
                  endfunction

                  function Reg#(t) conditionalWrite(Reg#(t) r, Bool a);
                     return (interface Reg;
                        method t _read = r._read;
                        method Action _write(t x);
                        if (a)
                        r._write(x);
                        endmethod
                        endinterface);
                  endfunction

                  function Reg#(t) clearSideEffect(Reg#(t) r, Action a, Action b)
                     provisos( Literal#(t),Eq#(t));
                     return (interface Reg;
                        method t _read = r._read;
                        method Action _write(t x);
                        r._write(x);
                        if (x==1) begin
                        a;
                        b;
                        end
                        endmethod
                        endinterface);
                  endfunction

                  function Reg#(Bit#(32)) writeSideEffect(Reg#(Bit#(32)) r, Action a);
                     return (interface Reg;
                        method Bit#(32) _read = r._read;
                        method Action _write(Bit#(32) x);
                        r._write(x);
                        a;
                        endmethod
                        endinterface);
                  endfunction

                  function Reg#(Bit#(n)) writeCCREffect(Reg#(Bit#(n)) r, Action a, Action b);
                     return (interface Reg;
                        method Bit#(n) _read = r._read;
                        method Action _write(Bit#(n) x);
                        r._write(x);
                        `logLevel(qspicontrol, 0, $format("x: %h",x))
                        if (x[11:10]==0 && (x[27:26] == 'b00 || x[27:26]=='b01 || x[25:24]=='b0) && x[9:8]!=0) begin  // no address required and nodata from firmware (i.e. no write)
                        a;
                        end
                        if (x[27:26]=='b11)  //Memory Mapped Mode
                        b;
                        endmethod
                        endinterface);
                  endfunction

                  typedef enum {Instruction_phase=0,
                  Address_phase=1,
                  AlternateByte_phase=2,
                  Dummy_phase=3,
                  DataRead_phase=4,
                  DataWait_phase=5,
                  DataWrite_phase=6,
                  Idle=7} Phase deriving (Bits,Eq,FShow);

                  module mkqspi_controller#(Bit#(32) start_mm_addr,Bit#(32) end_mm_addr)(Ifc_qspi_controller#(addr_width, data_width, user_width))
                     provisos(Add#(a__, 28, addr_width),Mul#(32, b__, data_width),Add#(c__,addr_width,32));

                     /*************** List of implementation defined Registers *****************/
                     Reg#(bit) rg_clk <- mkRegA(1);
                     Reg#(bit) rg_ddr_clk <- mkRegA(1);
                     Reg#(Bit#(8)) rg_clk_counter <- mkRegA(0);
                     Reg#(Bit#(8)) rg_ddr_counter <- mkRegA(0);
                     MIMOConfiguration cfg=defaultValue;
                     cfg.unguarded=True;
                     MIMO#(4,4,16,Bit#(8)) fifo <- mkMIMO(cfg);
                     Reg#(Phase) rg_phase <- mkRegA(Idle);
                     Reg#(Phase) rg_phase_delayed <- mkRegA(Idle);
                     Reg#(Bit#(4)) rg_output <- mkRegA(0);
                     Reg#(Bit#(4)) rg_output_en <- mkRegA(0);
                     Reg#(Bool) rg_input_en <- mkRegA(False);
                     Wire#(Bit#(4)) rg_input <- mkDWire(0);
                     Reg#(Bit#(32)) rg_count_bits <- mkRegA(0);  // count bits to be transfered
                     Reg#(Bit#(32)) rg_count_bytes <- mkRegA(0);  // count bytes to be transfered
                     Reg#(Bool) wr_sdr_clock <- mkDWire(False);  // use this to trigger posedge of sclk
                     Wire#(Bool) wr_ddr_clock <- mkDWire(False);
                     Reg#(Bool) wr_sdr_delayed <- mkDWire(False);
                     Reg#(Bool) wr_instruction_written <- mkDRegA(False);  // this wire is se when the instruction is written by the AXI Master
                     Reg#(Bool) wr_address_written <- mkDRegA(False);  // this wire is set when the address is written by the AXI Master
                     Reg#(Bool) wr_read_request_from_AXI <- mkDRegA(False);  // this wire is set when the address is written by the AXI Master
                     Reg#(Bool) wr_data_written <- mkDRegA(False);  // this wire is set when the data is written by the AXI Master
                     Reg#(Bool) instruction_sent <- mkRegA(False);  // This register is set when the instruction has been sent once to the flash
                     Reg#(Bit#(1)) ncs <- mkRegA(1);  // this is the chip select
                     Reg#(Bit#(1)) delay_ncs <- mkRegA(1);  // this is the chip select

                     // Bug 1 ECO: resolve write-write conflicts between if_abort and
                     // rl_read_request_from_AXI (SLVERR path) so both rules can fire
                     // in the same cycle without (*preempts*) blocking AXI reads.
                     // Multi-bit: RWire carries value; abort takes priority.
                     RWire#(Phase) rw_abort_rg_phase <- mkRWire();
                     RWire#(Phase) rw_axi_rg_phase   <- mkRWire();
                     // Single-bit same-value: either source fires the write.
                     PulseWire pw_abort_sr_busy_clear <- mkPulseWire();
                     PulseWire pw_axi_sr_busy_clear   <- mkPulseWire();
                     PulseWire pw_abort_ncs_set       <- mkPulseWire();
                     PulseWire pw_axi_ncs_set         <- mkPulseWire();
                     // first_read differs between rules: set (AXI) wins over clear (abort).
                     PulseWire pw_first_read_set      <- mkPulseWire();
                     PulseWire pw_first_read_clear    <- mkPulseWire();
                     // thres and fifo.clear() are also shared between if_abort and
                     // rl_read_request_from_AXI burst-reset path — separate wires per rule.
                     PulseWire pw_abort_thres_clear   <- mkPulseWire();
                     PulseWire pw_axi_thres_clear     <- mkPulseWire();
                     PulseWire pw_abort_fifo_clear    <- mkPulseWire();
                     PulseWire pw_axi_fifo_clear      <- mkPulseWire();
                     Wire#(Bool) wr_status_read <- mkDWire(False);  // this wire is set when the status register is written
                     Wire#(Bool) wr_data_read <- mkDWire(False);  // this wire is set when the data register is written
                     Reg#(Bool) half_cycle_delay <- mkRegA(False);
                     Reg#(Bit#(16)) timecounter <- mkRegA(0);
                     Reg#(Bool) read_true <- mkRegA(False);
                     Reg#(Bool) first_read <- mkRegA(False);
                     /*************** End of implementation defined Registers *****************/

                     /**************** Reg and wire for user interface *********************/
                     Wire#(Maybe#(Write_req#(addr_width,data_width))) wr_qspi_req <- mkDWire(tagged Invalid);
                     Wire#(Maybe#(AXI4_Lite_Resp)) wr_write_resp <- mkDWire(tagged Invalid);
                     Wire#(Maybe#(Read_req#(addr_width))) wr_rd_req <- mkDWire(tagged Invalid);
                     Wire#(Maybe#(Rd_resp#(data_width))) wr_rd_resp <- mkDWire(tagged Invalid);
                     FIFOF#(Read_req#(addr_width)) ff_rd_req <- mkFIFOF1();

                     /*************** List of QSPI defined Registers *****************/
                     Reg#(Bit#(1)) sr_busy <- mkConfigRegA(0);  // set when the operation is in progress.
                     Reg#(Bit#(5)) sr_flevel <- mkRegA(0);  // FIFO Level. Number of valid bytes held in the FIFO. 0: empty
                     Reg#(Bit#(1)) sr_tof <- mkRegA(0);  // set when the timeout occurs.
                     Reg#(Bit#(1)) sr_smf <- mkRegA(0);  // set when the unmasked receieved data matches psmar.
                     Reg#(Bit#(1)) sr_ftf <- mkRegA(0);  // set when the FIFO threshold is reached.
                     Reg#(Bit#(1)) sr_tcf <- mkRegA(0);  // set when programmed number of data has been transfered or when aborted.
                     Reg#(Bit#(1)) delay_sr_tcf <- mkRegA(0);  // set when programmed number of data has been transfered or when aborted.
                     Reg#(Bit#(1)) sr_tef <- mkRegA(0);  // set when an error occurs on transfer.
                     Reg#(Bit#(32)) sr = concatReg9(readOnlyReg(19'd0),readOnlyReg(sr_flevel),readOnlyReg(2'd0),readOnlyReg(sr_busy),readOnlyReg(sr_tof),readOnlyReg(sr_smf),readOnlyReg(sr_ftf),readOnlyReg(sr_tcf),readOnlyReg(sr_tef));

                     Reg#(Bit#(8)) prescaler <- mkRegA(0);
                     Reg#(Bit#(8)) cr_prescaler=conditionalWrite(prescaler,sr_busy==0);  // prescaler register part of the control register.
                     Reg#(Bit#(1)) pmm <- mkRegA(0);
                     Reg#(Bit#(1)) cr_pmm =conditionalWrite(pmm,sr_busy==0);  // polling match mode. 0: AND match and 1: OR match.
                     Reg#(Bit#(1)) apms <- mkRegA(0);
                     Reg#(Bit#(1)) cr_apms =conditionalWrite(apms,sr_busy==0);  // automatic poll mode stop. 1: stop when match. 0: stopped by disabling qspi.
                     Reg#(Bit#(1)) cr_toie <- mkRegA(0);  // enabled interrupt on time-out.
                     Reg#(Bit#(1)) cr_smie <- mkRegA(0);  // enables status match interrupt.
                     Reg#(Bit#(1)) cr_ftie <- mkRegA(0);  // enables interrupt on FIFO threshold.
                     Reg#(Bit#(1)) cr_tcie <- mkRegA(0);  // enables interrupt on completion of transfer.
                     Reg#(Bit#(1)) cr_teie <- mkRegA(0);  // enables interrupt on error of transfer.
                     Reg#(Bit#(4)) cr_fthres <- mkRegA(0);  // defines the number of bytes in the FIFO that will cause the FTF in sr to be raised.
                     Reg#(Bit#(1)) fsel <- mkRegA(0);
                     Reg#(Bit#(1)) cr_fsel=conditionalWrite(fsel,sr_busy==0);  // used for flash memory selection TODO: Not required.
                     Reg#(Bit#(1)) dfm <- mkRegA(0);
                     Reg#(Bit#(1)) cr_dfm =conditionalWrite(dfm,sr_busy==0);  // used for dual flash mode TODO: Not required.
                     Reg#(Bit#(1)) sshift <- mkRegA(0);
                     Reg#(Bit#(1)) cr_sshift =conditionalWrite(sshift,sr_busy==0);  // sample shift to account for delays from the flash. TODO: Might not be required.
                     Reg#(Bit#(1)) tcen <- mkRegA(0);
                     Reg#(Bit#(1)) cr_tcen =conditionalWrite(tcen,sr_busy==0);  // enables the timeout counter.
                     Reg#(Bit#(1)) cr_dmaen <- mkRegA(0);  // enables the dma transfer.
                     Reg#(Bit#(1)) cr_abort <- mkRegA(0);  // this bit aborts the ongoing transaction.
                     Reg#(Bit#(1)) cr_en <- mkRegA(0);  // this bit enables the qspi.
                     Reg#(Bit#(32)) cr=concatReg19(cr_prescaler,cr_pmm,cr_apms,readOnlyReg(1'b0),cr_toie,cr_smie,cr_ftie,cr_tcie,cr_teie,readOnlyReg(4'd0),cr_fthres,cr_fsel,cr_dfm,readOnlyReg(1'b0),cr_sshift,cr_tcen,cr_dmaen,cr_abort,cr_en);

                     Reg#(Bit#(5)) fsize <- mkRegA(0);
                     Reg#(Bit#(5)) dcr_fsize =conditionalWrite(fsize,sr_busy==0);  // flash memory size.
                     Reg#(Bit#(3)) csht <- mkRegA(0);
                     Reg#(Bit#(3)) dcr_csht = conditionalWrite(csht,sr_busy==0);  // chip select high time.
                     Reg#(Bit#(1)) ckmode <- mkRegA(0);
                     Reg#(Bit#(1)) dcr_ckmode =conditionalWrite(ckmode,sr_busy==0);  // mode 0 or mode 3.
                     Reg#(Bit#(8)) dcr_mode_byte <- mkRegA(0);
                     Reg#(Bit#(32)) dcr = concatReg7(readOnlyReg(3'd0),dcr_mode_byte,dcr_fsize,readOnlyReg(5'd0),dcr_csht,readOnlyReg(7'd0),dcr_ckmode);
                     Reg#(Bit#(32)) rg_mode_bytes = concatReg2(dcr_mode_byte,readOnlyReg(24'd0));
                     Reg#(Bit#(5)) rg_mode_byte_counter <- mkRegA('d31);

                     Reg#(Bit#(1)) fcr_ctof <- mkRegA(0);  // writing 1 clears the sr_tof flag.
                     Reg#(Bit#(1)) fcr_csmf <- mkRegA(0);  // writing 1 clears the sr_smf flag.
                     Reg#(Bit#(1)) fcr_ctcf <- mkRegA(0);  // writing 1 clears the sr_tcf flag.
                     Reg#(Bit#(1)) fcr_ctef <- mkRegA(0);  // writing 1 clears the sr_tef flag.
                     Reg#(Bit#(32)) fcr=concatReg6(readOnlyReg(27'd0),clearSideEffect(fcr_ctof,sr_tof._write(0),noAction),clearSideEffect(fcr_csmf,sr_smf._write(0),noAction),readOnlyReg(1'b0),clearSideEffect(fcr_ctcf,sr_tcf._write(0),delay_sr_tcf._write(0)),clearSideEffect(fcr_ctef,sr_tef._write(0),noAction));

                     Reg#(Bit#(32)) data_length <- mkRegA(0);
                     Reg#(Bit#(32)) dlr=conditionalWrite(data_length,sr_busy==0);  // data length register

                     Reg#(Bit#(1)) ddrm <- mkRegA(0);
                     Reg#(Bit#(1)) ccr_ddrm =conditionalWrite(ddrm,sr_busy==0);  // double data rate mode.
                     Reg#(Bit#(1)) dhhc <- mkRegA(0);
                     Reg#(Bit#(1)) ccr_dhhc =conditionalWrite(dhhc,sr_busy==0);  // delay output by 1/4 in DDR mode. TODO: Not required.
                     Reg#(Bit#(1)) sioo <- mkRegA(0);
                     Reg#(Bit#(1)) ccr_sioo =conditionalWrite(sioo,sr_busy==0);  // send instruction based on mode selected.
                     Reg#(Bit#(2)) fmode <- mkRegA(0);
                     Reg#(Bit#(2)) ccr_fmode =conditionalWrite(fmode,sr_busy==0);  // 00: indirect Read, 01: indirect Write, 10: Auto polling, 11: MMapped.
                     Reg#(Bit#(2)) dmode <- mkRegA(0);
                     Reg#(Bit#(2)) ccr_dmode =conditionalWrite(dmode,sr_busy==0);  // data mode. 01: single line, 10: two line, 11: four lines.
                     Reg#(Bit#(5)) dcyc <- mkRegA(0);
                     Reg#(Bit#(5)) ccr_dcyc =conditionalWrite(dcyc,sr_busy==0);  // number of dummy cycles.
                     Reg#(Bit#(2)) absize <- mkRegA(0);
                     Reg#(Bit#(2)) ccr_absize=conditionalWrite(absize,sr_busy==0);  // number of alternate byte sizes.
                     Reg#(Bit#(2)) abmode <- mkRegA(0);
                     Reg#(Bit#(2)) ccr_abmode=conditionalWrite(abmode,sr_busy==0);  // alternate byte mode.
                     Reg#(Bit#(2)) adsize <- mkRegA(0);
                     Reg#(Bit#(2)) ccr_adsize=conditionalWrite(adsize,sr_busy==0);  // address size.
                     Reg#(Bit#(2)) admode <- mkRegA(0);
                     Reg#(Bit#(2)) ccr_admode=conditionalWrite(admode,sr_busy==0);  // address mode.
                     Reg#(Bit#(2)) imode <- mkRegA(0);
                     Reg#(Bit#(2)) ccr_imode =conditionalWrite(imode,sr_busy==0);  // instruction mode.
                     Reg#(Bit#(8)) instruction <- mkRegA(0);
                     Reg#(Bit#(8)) ccr_instruction =conditionalWrite(instruction,sr_busy==0);  // instruction to be sent externally.
                     Reg#(Bit#(1)) ccr_dummy_confirmation <- mkRegA(0);  //Programming Dummy confirmation bit needed by Micron model to trigger XIP mode
                     Reg#(Bit#(1)) ccr_dummy_bit <- mkRegA(0);  //Dummy bit to be sent
                     Reg#(Bit#(32)) ccr =writeCCREffect(concatReg14(ccr_ddrm,ccr_dhhc,ccr_dummy_bit,ccr_sioo,ccr_fmode,ccr_dmode,ccr_dummy_confirmation,ccr_dcyc,ccr_absize,ccr_abmode,ccr_adsize,ccr_admode,ccr_imode,ccr_instruction),wr_instruction_written._write(True),first_read._write(True));

                     Reg#(Bit#(32)) mm_data_length <- mkConfigRegA(0);
                     Reg#(Bit#(28)) mm_address <- mkConfigRegA(0);
                     Reg#(Bit#(28)) rg_prev_addr <- mkConfigRegA(0);
                     Reg#(Bit#(32)) rg_address <- mkRegA(0);
                     Reg#(Bit#(32)) ar =conditionalWrite(writeSideEffect(rg_address,wr_address_written._write(True)),sr_busy==0 && ccr_fmode!='b11);  // address register

                     Reg#(Bit#(32)) rg_alternatebyte_reg <- mkRegA(0);
                     Reg#(Bit#(32)) abr=conditionalWrite(rg_alternatebyte_reg,sr_busy==0);  // alternate byte register

                     Reg#(Bit#(32)) rg_data <- mkRegA(0);
                     Reg#(Bit#(32)) dr =writeSideEffect(rg_data,wr_data_written._write(True));  // data register

                     Reg#(Bit#(32)) rg_psmkr <- mkRegA(0);
                     Reg#(Bit#(32)) psmkr =conditionalWrite(rg_psmkr,sr_busy==0);  // polling status mask register

                     Reg#(Bit#(32)) rg_psmar <- mkRegA(0);
                     Reg#(Bit#(32)) psmar =conditionalWrite(rg_psmar,sr_busy==0);  // polling statue match register

                     Reg#(Bit#(16)) pir_interval <- mkRegA(0);  // polling interval
                     Reg#(Bit#(32)) pir =conditionalWrite(concatReg2(readOnlyReg(16'd0),pir_interval),sr_busy==0);  // polling interval register

                     Reg#(Bit#(16)) lptr_timeout <- mkRegA(0);  // timeout period
                     Reg#(Bit#(32)) lptr =conditionalWrite(concatReg2(readOnlyReg(16'd0),lptr_timeout),sr_busy==0);  // low power timeout register.
                     Reg#(Bool) thres <- mkRegA(False);
                     Reg#(Bool) rg_request_ready <- mkRegA(True);
                     Reg#(Bit#(4)) rg_count <- mkRegA(0);
                     Reg#(bit) ddr_en <- mkRegA(0);
                     Reg#(bit) init_mm_xip_delay <- mkRegA(0);

                     Bool ddr_clock = wr_ddr_clock;  //((wr_sdr_clock && !wr_sdr_delayed)||(!wr_sdr_clock && wr_ddr_clock));
                     //    Bool ddr_clock = (wr_sdr_clock || wr_sdr_delayed);
                     Bool transfer_cond = (sr_busy==1 && cr_abort==0 && cr_en==1);
                     Bool clock_cond = ((wr_sdr_clock && ccr_ddrm==0) || (wr_ddr_clock && ccr_ddrm==1));  //##
                     Bool qspi_flush = (cr_abort == 1 || cr_en == 0);
                     /*************** End of QSPI defined Registers *****************/
                     function Reg#(Bit#(32)) access_register(Bit#(8) address);
                        Reg#(Bit#(32)) register=(
                           case (address)
                           `CR : cr;
                           `DCR : dcr;
                           `FCR : fcr;
                           `DLR : dlr;
                           `CCR : ccr;
                           `AR : ar;
                           `ABR : abr;
                           `DR : dr;
                           `SR : sr;
                           `PSMKR : psmkr;
                           `PSMAR : psmar;
                           `PIR : pir;
                           `LPTR : lptr;
                           default: readOnlyReg(0);
                           endcase
                        );
                        return register;
                     endfunction

                     /* This function defines the next phase that needs to be executed. indicates if
                     the operation is over and also the value of rg_count_bits for the next phase*/
                     function Tuple3#(Bit#(32),Bit#(1),Phase) phase_change(Phase current_phase, Bit#(32) count_val, Bit#(1) smf);
                        Phase next_phase=Idle;
                        if (current_phase==Idle)
                        next_phase=Instruction_phase;
                        if (current_phase==Instruction_phase)
                        next_phase=Address_phase;
                        if (current_phase==Address_phase)
                        next_phase=AlternateByte_phase;
                        if (current_phase==AlternateByte_phase)
                        next_phase=Dummy_phase;
                        if (current_phase==Dummy_phase)
                        next_phase=(ccr_fmode=='b00)?DataWrite_phase:DataRead_phase;
                        if (current_phase==DataRead_phase)begin
                           if (ccr_fmode=='b01 || ccr_fmode=='b10)  // indirect modes
                           next_phase=Idle;
                           else if (ccr_fmode=='b10)  // auto-status polling mode
                           if (smf==1)
                           next_phase=Idle;
                           else
                           next_phase=Dummy_phase;
                           else
                           next_phase=DataRead_phase;  //Memory Mapped mode
                        end
                        if (current_phase==DataWrite_phase)
                        next_phase=Idle;

                        if (next_phase==Instruction_phase && (ccr_imode==0||(ccr_sioo==1 && instruction_sent)))  // if single instruction mode or no instruction mode
                        next_phase = Address_phase;
                        if (next_phase==Address_phase && ccr_admode==0)
                        next_phase=AlternateByte_phase;
                        if (next_phase==AlternateByte_phase && ccr_abmode==0)
                        next_phase=Dummy_phase;
                        if (next_phase==Dummy_phase && ccr_dcyc==0)
                        next_phase=ccr_fmode==0?DataWrite_phase:DataRead_phase;
                        if (next_phase==Dummy_phase && (ccr_fmode=='b10 && pir_interval==0))begin  // TODO Check if this is correct or needs more logic.
                           next_phase=Instruction_phase;
                        end
                        if ((next_phase == DataWrite_phase || next_phase == DataRead_phase) && ccr_dmode==0 && ccr_fmode!='b11)begin
                           if (ccr_fmode=='b01 || ccr_fmode=='b00)
                           next_phase=Idle;
                           else if (ccr_fmode=='b10)
                           if (smf==1)
                           next_phase=Idle;
                           else
                           next_phase=Dummy_phase;
                        end

                        if (next_phase==Instruction_phase)begin
                           count_val=8;
                        end
                        if (next_phase==Address_phase)begin
                           count_val=/*(ccr_fmode=='b11)?32:*/(case (ccr_adsize) 0:8; 1:16; 2:24; 3:32; endcase);
                        end
                        if (next_phase==AlternateByte_phase)begin
                           count_val=(case (ccr_absize) 0:8; 1:16; 2:24; 3:32; endcase);
                        end
                        if (next_phase==Dummy_phase)begin
                           count_val=(ccr_fmode=='b10)? zeroExtend(pir_interval):zeroExtend(ccr_dcyc);
                        end
                        if (next_phase==DataWrite_phase)begin
                           count_val=8;
                        end
                        if (next_phase==DataRead_phase)begin
                           count_val= 0;
                        end
                        Bit#(1) tcf=0;
                        if (current_phase!=Idle && next_phase==Idle && (ccr_fmode=='b00 || ccr_fmode=='b01))begin  // only in indirect mode raise completion of transfer TODO remove ccr_fmode=='b11 from this line.
                           tcf=1;
                        end
                        return tuple3(count_val,tcf,next_phase);
                     endfunction

                     Wrapper3#(Phase,Bit#(32),Bit#(1),Tuple3#(Bit#(32),Bit#(1),Phase)) change_phase <- mkUniqueWrapper3(phase_change);

                     /* This rule receives the write request from the AXI and updates the relevant
                     QSPI register set using the lower 12 bits as address map */
                     rule rl_write_request_from_AXI(isValid(wr_qspi_req));
                        //  	let aw <- pop_o (s_xactor.o_wr_addr);
                        //    let w <- pop_o (s_xactor.o_wr_data);
                        let req = fromMaybe(?, wr_qspi_req);
                        let awaddr = req.addr;
                        let awsize = req.burst_size;
                        let wdata = req.wdata;

                        AXI4_Lite_Resp axi4_bresp = AXI4_LITE_OKAY;
                        if (ccr_fmode=='b11 && awaddr[7:0]==`DR) begin  //Undefined behavior when written into integral fields in CR, CCR!!!
                           axi4_bresp = AXI4_LITE_SLVERR;
                           `logLevel(qspicontrol, 0, $format("Sending AXI4_LITE_SLVERR because store in memory mapped mode and not clearing Interrupt Flags"))
                        end
                        `logLevel(qspicontrol, 0, $format("\tReceived AXI write request to Address: %h Data: %h Size: %h",awaddr,wdata,awsize))
                        if (awaddr[7:0]==`DR)begin
                           if (awsize==0)begin
                              dr[7:0] <= wdata[7:0];
                              Vector#(4,Bit#(8)) temp=newVector();
                              temp[0]=wdata[7:0];
                              if (fifo.enqReadyN(1))
                              fifo.enq(1,temp);
                           end
                           else if (awsize==1)begin
                              dr[15:0] <= wdata[15:0];
                              Vector#(4,Bit#(8)) temp = newVector();
                              temp[1]= wdata[7:0];
                              temp[0]= wdata[15:8];
                              if (fifo.enqReadyN(2))
                              fifo.enq(2,temp);
                           end
                           else begin
                              dr <= wdata[31:0];
                              Vector#(4,Bit#(8)) temp = newVector();
                              temp[0]= wdata[31:24];
                              temp[1]= wdata[23:16];
                              temp[2]= wdata[15:8];
                              temp[3]= wdata[7:0];
                              if (fifo.enqReadyN(4))
                              fifo.enq(4,temp);
                           end
                           `logLevel(qspicontrol, 0, $format("fifo count: %d fthres: %d",fifo.count,cr_fthres))
                        end
                        else begin
                           let reg1=access_register(awaddr[7:0]);
                           `logLevel(qspicontrol, 0, $format("Write Reg access: %h Write Data: %h Size: %h",awaddr[7:0],wdata,awsize))
                           //Byte and Half-Word Writes are not permitted in ConfigReg Space
                           reg1 <= wdata[31:0];
                        end

                        wr_write_resp <= tagged Valid(axi4_bresp);
                        //	  let b = AXI4_Lite_Wr_Resp {bresp: axi4_bresp, buser: aw.awuser};
                        //    s_xactor.i_wr_resp.enq (b);
                     endrule

                     /* This rule receives the read request from the AXI and responds with the relevant
                     QSPI register set using the lower 12 bits as address map */
                     //    (*descending_urgency="rl_read_request_from_AXI,rl_write_request_from_AXI"*) //experimental
                     /*rule rl_enq_read_req(isValid(wr_rd_req));
                     ff_rd_req.enq(fromMaybe(?, wr_rd_req));
                     `logLevel(qspicontrol, 0, $format(" QSPI: i am firing"))
                     endrule*/
                     rule rl_read_request_from_AXI(rg_request_ready == True);
                        //		let axir <- pop_o(s_xactor.o_rd_addr);
                        let axir = ff_rd_req.first;
                        ff_rd_req.deq;
                        let araddr = axir.addr;
                        let arsize = axir.burst_size;
                        Bool request_ready = False;
                        `logLevel(qspicontrol, 0, $format("\tReceived AXI read request to Address: %h Size: %h",araddr,arsize))
                        if (zeroExtend(araddr)>=start_mm_addr && zeroExtend(araddr) <= end_mm_addr)begin  // memory mapped space

                           wr_read_request_from_AXI <= True;  //Could this lead to some error? Need to think about this, without fail
                           AXI4_Lite_Resp axi4_rresp = AXI4_LITE_OKAY;

                           Bit#(28) new_addr = arsize==0?{araddr[27:2],~araddr[1:0]}:
                           arsize==1?{araddr[27:2],~araddr[1],araddr[0]}:
                           truncate(araddr);
                           mm_address <= new_addr;

                           Bit#(4) data_length = arsize==0?1:
                           arsize==1?2:
                           arsize==2?4:
                           8;

                           mm_data_length <= zeroExtend(data_length);
                           Bit#(28) address_limit = 1 << dcr_fsize;

                           //It is forbidden to access the flash bank area before the SPI is properly configured -- fmode is '11??
                           //If not sending a SLVERR now if the mode is not memory mapped and if an access is made outside allowed
                           if (ccr_fmode != 2'b11 || araddr[27:0] > address_limit) begin
                              `logLevel(qspicontrol, 0, $format("Sending Slave Error ccr_fmode: %h mm_address: %h address_limit: %h dcr_fsize: %h",ccr_fmode,mm_address,address_limit, dcr_fsize))
                              axi4_rresp = AXI4_LITE_SLVERR;
                              //              let r = AXI4_Lite_Rd_Data {rresp: axi4_rresp, rdata: 0 , ruser: 0};
                              //    	        s_xactor.i_rd_data.enq(r);
                              wr_rd_resp <= tagged Valid Rd_resp {
                                 rsp : axi4_rresp,
                                 rdata : 0 };
                                 axi4_rresp = AXI4_LITE_SLVERR;
                                 rw_axi_rg_phase.wset(Idle);
                                 pw_axi_sr_busy_clear.send();
                                 pw_axi_ncs_set.send();
                                 pw_first_read_set.send();
                                 request_ready = True;
                              end
                              else if (sr_busy==1 ||thres) begin  //Bus is busy with Memory mapped maybe?
                                 `logLevel(qspicontrol, 0, $format("sr_busy: %d, thres: %d rg_prev_addr: %h araddr: %h fifo_count: %d", sr_busy, thres, rg_prev_addr, araddr, fifo.count))
                                 Bit#(28) eff_addr = rg_prev_addr + truncate(mm_data_length);
                                 if ((eff_addr!= truncate(araddr)) || pack(fifo.count)==0 || ccr_dummy_bit==1'b1) begin
                                    `logLevel(qspicontrol, 0, $format("Not Equal eff_addr: %h mm_address : %h araddr: %h rg_prev_addr: %h data_length : %h sum : %h fifo.count: %h ccr_dummy_bit: %h",eff_addr,mm_address,araddr,rg_prev_addr,data_length,rg_prev_addr+zeroExtend(data_length),pack(fifo.count),ccr_dummy_bit))
                                    pw_axi_sr_busy_clear.send();
                                    rw_axi_rg_phase.wset(Idle);
                                    pw_axi_ncs_set.send();
                                    pw_axi_fifo_clear.send();
                                    pw_axi_thres_clear.send();
                                    //`logLevel(qspicontrol, 0, $format("Setting Thres to FALSE"))
                                    pw_first_read_set.send();
                                    request_ready = False;
                                 end
                                 else if (!first_read) begin
                                    request_ready = True;
                                    rg_prev_addr <= truncate(araddr);
                                    Bit#(32) reg1 = 0;
                                    if (arsize==0) begin  // 8 bits
                                       if (fifo.deqReadyN(1))begin
                                          let temp=fifo.first[0];
                                          reg1=duplicate(temp);
                                          fifo.deq(1);
                                       end
                                    end
                                    else if (arsize==1) begin  // 16 bits
                                       if (fifo.deqReadyN(2)) begin
                                          let temp={fifo.first[0],fifo.first[1]};
                                          reg1=duplicate(temp);
                                          fifo.deq(2);
                                       end
                                    end
                                    else begin  // 32 bits
                                       if (fifo.deqReadyN(4)) begin
                                          let temp={fifo.first[0],fifo.first[1],fifo.first[2],fifo.first[3]};
                                          reg1=duplicate(temp);
                                          fifo.deq(4);
                                          `logLevel(qspicontrol, 0, $format(" Memory maqpped requset arrived for %d and value %d \n",araddr,temp))
                                       end
                                    end
                                    `logLevel(qspicontrol, 0, $format("Sending Response to the core: reg1: %h", reg1))
                                    wr_rd_resp <= tagged Valid Rd_resp {
                                       rsp : axi4_rresp,
                                       rdata : duplicate(reg1)};
                                       //             	    let r = AXI4_Lite_Rd_Data {rresp: axi4_rresp, rdata: duplicate(reg1) , ruser: 0};
                                       //    	            s_xactor.i_rd_data.enq(r);
                                    end
                                 end
                              end
                              else begin
                                 let reg1=access_register(araddr[7:0]);
                                 `logLevel(qspicontrol, 0, $format("Reg Read Access: %h arsize: %h",araddr[7:0], arsize))
                                 if (araddr[7:0]==`SR)
                                 wr_status_read <= True;
                                 if (araddr[7:0]==`DR)begin  // accessing the data register for read.
                                    `logLevel(qspicontrol, 0, $format("Accessed DR fifo_count : %d axi.arsize: %d", fifo.count, arsize))
                                    if (ccr_fmode=='b10)
                                    wr_data_read <= True;
                                    if (arsize==0) begin  // 8 bits
                                       if (fifo.deqReadyN(1))begin
                                          let temp=fifo.first[0];
                                          reg1=duplicate(temp);
                                          fifo.deq(1);
                                       end
                                    end
                                    else if (arsize==1) begin  // 16 bits
                                       if (fifo.deqReadyN(2)) begin
                                          let temp={fifo.first[0],fifo.first[1]};
                                          reg1=duplicate(temp);
                                          fifo.deq(2);
                                       end
                                    end
                                    else /*if (arsize==2)*/ begin  // 32 bits -- Even if the request is a long int, respond with int since that's the max we can do
                                       if (fifo.deqReadyN(4)) begin
                                          let temp={fifo.first[0],fifo.first[1],fifo.first[2],fifo.first[3]};
                                          reg1=duplicate(temp);
                                          fifo.deq(4);
                                       end
                                    end
                                 end
                                 `logLevel(qspicontrol, 0, $format("Sending Response : reg1: %x", reg1))
                                 wr_rd_resp <= tagged Valid Rd_resp {
                                    rsp : AXI4_LITE_OKAY,
                                    rdata : duplicate(reg1)};
                                    //    	let r = AXI4_Lite_Rd_Data {rresp: AXI4_LITE_OKAY, rdata: duplicate(reg1) ,ruser: 0};
                                    request_ready = True;
                                    //    	s_xactor.i_rd_data.enq(r);
                                 end
                                 rg_request_ready <= request_ready;
                                 `logLevel(qspicontrol, 0, $format("QSPI: Is Request ready? : %h",request_ready))
                              endrule

                              rule timeout_counter;
                                 if (cr_tcen==1 && sr_tof==0)  // timecounter is enabled
                                 if (timecounter==lptr_timeout[15:0])begin
                                    timecounter <= 0;
                                    sr_tof <= 1;
                                 end
                                 else
                                 timecounter <= timecounter+1;
                              endrule

                              rule delayed_sr_tcf_signal(transfer_cond &&
                                 ((ccr_ddrm==1 && ddr_clock && (ccr_admode!=0 || ccr_dmode!=0)) || wr_sdr_clock));
                                 sr_tcf <= delay_sr_tcf;
                                 `logLevel(qspicontrol, 0, $format(" QSPI: sr_tcf latched"))
                              endrule

                              rule delayed_ncs_generation;
                                 delay_ncs <= ncs;
                              endrule

                              //	rule delay_sdr;
                              //		wr_sdr_clock <= sdr_clk;
                              //        wr_sdr_delayed <= sdr_delayed_clk;
                              //    endrule

                              /*doc:Rule: this Rule generates ddr clock/detect the both posedge and negedge of sdr clock*/
                              rule rl_ddr_clk_gen;
                                 if (ccr_ddrm == 1) begin
                                    if (delay_ncs==1)begin
                                       rg_ddr_counter <= 0;
                                       rg_ddr_clk <= dcr_ckmode;
                                    end
                                    else begin
                                       let half_clock_value=(cr_prescaler>>1);
                                       let lv_dummy = (cr_prescaler + half_clock_value)>>1;
                                       if (cr_prescaler[0]==0)begin  // odd division
                                          if (rg_ddr_counter==(half_clock_value)>>1 || rg_ddr_counter==half_clock_value || rg_ddr_counter==lv_dummy || rg_ddr_counter==cr_prescaler)begin
                                             rg_ddr_clk <= ~rg_ddr_clk;
                                          end
                                          if (rg_ddr_counter==cr_prescaler)
                                          rg_ddr_counter <= 0;
                                          else
                                          rg_ddr_counter <= rg_ddr_counter+1;
                                          if (rg_ddr_counter==(half_clock_value)>>1 || rg_ddr_counter==half_clock_value || rg_ddr_counter==lv_dummy || rg_ddr_counter==cr_prescaler)begin
                                             wr_ddr_clock <= rg_phase==DataRead_phase?unpack(~rg_ddr_clk):unpack(rg_ddr_clk);
                                          end
                                       end
                                       else begin  // even division
                                          if (rg_ddr_counter==(half_clock_value)>>1 || rg_ddr_counter==half_clock_value)begin
                                             rg_ddr_clk <= ~rg_ddr_clk;
                                             wr_ddr_clock <= (rg_phase==DataRead_phase) ? unpack(~rg_ddr_clk): unpack(rg_ddr_clk);
                                          end
                                          if (rg_ddr_counter==half_clock_value) begin
                                             rg_ddr_counter <= 0;
                                          end
                                          else if (delay_ncs==0)
                                          rg_ddr_counter <= rg_ddr_counter+1;
                                       end
                                    end
                                 end
                              endrule

                              /* This Rule generates the clk signal. The Prescaler register defines the
                              division factor wrt to the Global clock. The prescaler will only work when the
                              chip select is low i.e when the operation has been initiated. */
                              rule rl_generate_clk_from_master;
                                 if (delay_ncs==1)begin
                                    rg_clk_counter <= 0;
                                    rg_clk <= dcr_ckmode;
                                    //            `logLevel(qspicontrol, 0, $format("dcr_ckmode: %h",dcr_ckmode))
                                 end
                                 else begin
                                    let half_clock_value=cr_prescaler>>1;
                                    //if(cr_prescaler[0]==0)begin // odd division   og
                                    if (cr_prescaler[0]==1)begin  // odd division
                                       /*
                                       if (rg_clk_counter <= half_clock_value)
                                       rg_clk <= 0;
                                       else
                                       rg_clk <= 1;
                                       if (rg_clk_counter==cr_prescaler)
                                       rg_clk_counter <= 0;
                                       */
                                       if (rg_clk_counter == half_clock_value || rg_clk_counter==cr_prescaler)
                                       rg_clk <= ~rg_clk;
                                       if (rg_clk_counter==cr_prescaler)
                                       rg_clk_counter <= 0;
                                       else
                                       rg_clk_counter <= rg_clk_counter+1;
                                       if (rg_clk_counter == half_clock_value || rg_clk_counter==cr_prescaler)begin
                                          wr_sdr_clock <= rg_phase==DataRead_phase?unpack(~rg_clk):unpack(rg_clk);
                                       end
                                    end
                                    else begin  // even division
                                       if (rg_clk_counter==half_clock_value)begin
                                          rg_clk <= ~rg_clk;
                                          rg_clk_counter <= 0;
                                          wr_sdr_clock <= rg_phase==DataRead_phase ? unpack(~rg_clk): unpack(rg_clk);
                                          wr_sdr_delayed <= rg_phase==DataRead_phase ? unpack(rg_clk): unpack(~rg_clk);
                                          //					let debug_clk = rg_phase==DataRead_phase ? unpack(~rg_clk): unpack(rg_clk);
                                          `logLevel(qspicontrol, 0, $format("half_clock_value %d ", half_clock_value))
                                       end
                                       else if (delay_ncs==0)
                                       rg_clk_counter <= rg_clk_counter+1;
                                    end
                                 end
                                 if (rg_phase == DataRead_phase) begin  // ##
                                    `logLevel(qspicontrol, 0, $format("clk_gen is firing rg_clk_counter %d", rg_clk_counter))
                                 end
                              endrule

                              /* update the status flag on each cycle */
                              rule rl_update_fifo_level;
                                 sr_flevel <= pack(fifo.count);
                              endrule
                              /* set the fifo threshold flag when the FIFO level is equal to the FTHRESH value */
                              (*preempts="rl_set_busy_signal,rl_update_threshold_flag"*)
                              rule rl_update_threshold_flag;
                                 //		`logLevel(qspicontrol, 0, $format(" QSPI: updating threshold flag"))
                                 if (ccr_fmode=='b00)begin  // indirect write mode
                                    sr_ftf <= pack(16-pack(fifo.count)>={1'b0,cr_fthres}+1);
                                 end
                                 else if (ccr_fmode=='b01) begin
                                    sr_ftf <= pack(pack(fifo.count)>=({1'b0,cr_fthres}+1));
                                    `logLevel(qspicontrol, 0, $format("fifo count: %d fthres: %d",fifo.count,cr_fthres))
                                 end
                                 else if (ccr_fmode=='b10 && wr_status_read)begin  // auto_status polling mode
                                    sr_ftf <= 1;
                                 end
                                 else if (ccr_fmode=='b10 && wr_data_read)begin  // auto_status polling mode
                                    sr_ftf <= 0;
                                 end
                                 else if (ccr_fmode=='b11) begin
                                    sr_ftf <= pack(pack(fifo.count)>=({1'b0,cr_fthres}+1));
                                    if (pack(fifo.count)>={1'b0,cr_fthres}+1) begin
                                       ncs <= 1;
                                       sr_busy <= 0;
                                       rg_phase <= Idle;  // Will this work?
                                       thres <= True;
                                       rg_request_ready <= True;
                                    end
                                    //   `logLevel(qspicontrol, 0, $format("THRES is being set to TRUE kyaaaa?"))
                                 end
                              endrule

                              /* If abort is raised or the QSPI is disabled go back to Idle Phase*/
                              //(*descending_urgency = "if_abort,rl_read_request_from_AXI"*)
                              //(*descending_urgency = "if_abort,rl_write_request_from_AXI"*)
                              (*preempts = "if_abort,rl_update_threshold_flag"*)
                              rule if_abort(qspi_flush);
                                 //`logLevel(qspicontrol, 0, $format("Received Abort or Disable request, going to idle"))
                                 rw_abort_rg_phase.wset(Idle);
                                 pw_abort_ncs_set.send();
                                 pw_abort_sr_busy_clear.send();
                                 pw_abort_thres_clear.send();
                                 read_true <= False;
                                 pw_first_read_clear.send();
                                 instruction_sent <= False;
                                 half_cycle_delay <= False;
                                 pw_abort_fifo_clear.send();
                              endrule

                              rule resolve_rg_phase;
                                 if (rw_abort_rg_phase.wget() matches tagged Valid .v)
                                    rg_phase <= v;
                                 else if (rw_axi_rg_phase.wget() matches tagged Valid .v)
                                    rg_phase <= v;
                              endrule

                              rule resolve_sr_busy_clear;
                                 if (pw_abort_sr_busy_clear || pw_axi_sr_busy_clear)
                                    sr_busy <= 0;
                              endrule

                              rule resolve_ncs_set;
                                 if (pw_abort_ncs_set || pw_axi_ncs_set)
                                    ncs <= 1;
                              endrule

                              rule resolve_first_read;
                                 if (pw_first_read_set)        first_read <= True;
                                 else if (pw_first_read_clear) first_read <= False;
                              endrule

                              rule resolve_thres_clear;
                                 if (pw_abort_thres_clear || pw_axi_thres_clear) thres <= False;
                              endrule

                              rule resolve_fifo_clear;
                                 if (pw_abort_fifo_clear || pw_axi_fifo_clear) fifo.clear();
                              endrule

                              /*operate the busy signal in different mode */
                              rule rl_reset_busy_signal(sr_busy==1);
                                 if (cr_abort==1)begin
                                    sr_busy <= 0;
                                    ncs <= 1;
                                 end
                                 else if (ccr_fmode=='b00 || ccr_fmode=='b01)begin  // indirect write or read mode;
                                    if (/*fifo.count==0 &&*/ sr_tcf==1)begin  // if FIFO is empty and the transaction is complete
                                       sr_busy <= 0;
                                       ncs <= 1;
                                    end
                                 end
                                 else if (ccr_fmode=='b10)begin  // automatic polling mode
                                    if (sr_smf==1)begin
                                       sr_busy <= 0;
                                       ncs <= 1;
                                    end
                                 end
                                 else if (ccr_fmode=='b11)begin
                                    if (sr_tof==1 || cr_en==0 || cr_abort==1) begin  // timeout event
                                       sr_busy <= 0;
                                       ncs <= 1;
                                    end
                                 end
                              endrule
                              (*descending_urgency="rl_set_busy_signal,rl_read_request_from_AXI"*)
                              (*descending_urgency="rl_set_busy_signal,rl_write_request_from_AXI"*)
                              rule rl_set_busy_signal(sr_busy==0 && rg_phase==Idle && cr_abort==0 && cr_en==1);
                                 rg_output_en <= 0;
                                 instruction_sent <= False;
                                 //		`logLevel(qspicontrol, 0, $format("\tWaiting for change in phase wr_read_request_from_AXI: %b ccr_fmode: %h thres: %h",wr_read_request_from_AXI,ccr_fmode,thres))
                                 if (wr_instruction_written)begin
                                    sr_busy <= 1;
                                    ncs <= 0;
                                    rg_phase <= Instruction_phase;
                                    rg_count_bits <= 8;
                                    `logLevel(qspicontrol, 0, $format("Entering Instruction phase"))
                                 end
                                 else if (wr_address_written && ccr_admode!=0 && (ccr_fmode=='b01 || ccr_dmode=='d0 || ccr_fmode=='b10))begin
                                    sr_busy <= 1;  // start some transaction
                                    `logLevel(qspicontrol, 0, $format(": Address Written and going to Some mode"))
                                    ncs <= 0;
                                    let {x,y,z} <- change_phase.func(rg_phase,0,0);
                                    rg_count_bits <= x;
                                    rg_count_bytes <= 0;
                                    rg_phase <= z;
                                    `logLevel(qspicontrol, 0, $format(": Mode is :",fshow(z),"Count_bits : %d",x))
                                    if (z==DataRead_phase)
                                    read_true <= True;
                                 end
                                 else if (wr_data_written && ccr_admode!=0 && ccr_dmode!=0 && ccr_fmode=='b00)begin
                                    `logLevel(qspicontrol, 0, $format(": Waiting for all the data to be transmitted "))
                                    rg_phase <= DataWait_phase;
                                 end
                                 else if (wr_read_request_from_AXI && ccr_fmode=='b11 && !thres)begin  // memory-mapped mode.
                                    `logLevel(qspicontrol, 0, $format(": Entering Memory mapped mode"))
                                    sr_busy <= 1;
                                    ncs <= 0;
                                    let {x,y,z} <- change_phase.func(rg_phase,0,0);
                                    rg_count_bits <= x;
                                    rg_count_bytes <= 0;
                                    rg_phase <= z;
                                    `logLevel(qspicontrol, 0, $format(": rg_phase :",fshow(z)))
                                    if (z==DataRead_phase)
                                    read_true <= True;
                                 end
                              endrule
                              //(*descending_urgency="rl_data_wait,rl_read_request_from_AXI"*)
                              //(*descending_urgency="rl_data_wait,rl_write_request_from_AXI"*)
                              rule rl_data_wait(sr_busy==0 && rg_phase==DataWait_phase && cr_abort==0 && cr_en==1);
                                 if (fifo.count >= 16)begin
                                    `logLevel(qspicontrol, 0, $format("All the data received!!!!! "))
                                    sr_busy <= 1;
                                    ncs <= 0;
                                    let {x,y,z} <- change_phase.func(Idle,0,0);
                                    rg_count_bits <= x;
                                    rg_count_bytes <= 0;
                                    rg_phase <= z;
                                    `logLevel(qspicontrol, 0, $format(": Mode is :",fshow(z),"Count_bits : %d",x))
                                 end
                                 else
                                 `logLevel(qspicontrol, 0, $format(" In Data_wait phase !!!!!"))
                              endrule

                              /* This Rule generates the error signal interrupt in different scenarios */
                              rule set_error_signal;
                                 Bit#(32) actual_address=1<<(dcr_fsize);
                                 if (wr_address_written && ar>actual_address && (ccr_fmode=='b00 || ccr_fmode=='b01))
                                 sr_tef <= 1;
                                 else if (wr_address_written && ar+dlr>actual_address &&(ccr_fmode=='b00 || ccr_fmode=='b01))
                                 sr_tef <= 1;
                                 else if (wr_address_written)
                                 sr_tef <= 0;
                              endrule

                              /* Rule to transfer the instruction of 8-bits outside. THe size of instruction is fixed
                              to 8 bits by protocol. Instruction phase will always be in SDR mode */
                              rule rl_transfer_instruction(rg_phase==Instruction_phase && transfer_cond && wr_sdr_clock && !qspi_flush);
                                 Bool end_of_phase=False;
                                 let reverse_instruction=ccr_instruction;
                                 let count_val=rg_count_bits;
                                 `logLevel(qspicontrol, 0, $format(": Executing Instruction Phase SPI Mode: %b Count_bits: %d InstructionReverse: %h",ccr_imode,rg_count_bits,reverse_instruction))
                                 Bit#(4) enable_o=0;
                                 if (ccr_imode=='b01)begin  // single spi mode;
                                    enable_o=4'b1101;
                                    rg_output <= {1'b1,1'b0,1'b0,reverse_instruction[rg_count_bits-1]};
                                    if (rg_count_bits==1) begin  // End of instruction stream
                                       end_of_phase=True;
                                    end
                                    else
                                    count_val=rg_count_bits-1;
                                 end
                                 else if (ccr_imode=='b10)begin  // dual mode;
                                    enable_o=4'b1111;
                                    rg_output <= {1'b1,1'b0,reverse_instruction[rg_count_bits-1:rg_count_bits-2]};
                                    if (rg_count_bits==2)begin  // End of instruction stream
                                       end_of_phase=True;
                                    end
                                    else
                                    count_val=rg_count_bits-2;
                                 end
                                 else if (ccr_imode=='b11)begin  // quad mode;
                                    enable_o=4'b1111;
                                    rg_output <= reverse_instruction[rg_count_bits-1:rg_count_bits-4];
                                    if (rg_count_bits==4)begin  // End of instruction stream
                                       end_of_phase=True;
                                    end
                                    else
                                    count_val=rg_count_bits-4;
                                 end
                                 if (end_of_phase || ccr_imode==0)begin  // End of instruction or no instruction phase
                                    let {x,y,z} <- change_phase.func(rg_phase,count_val,0);
                                    instruction_sent <= True;
                                    rg_count_bits <= x;
                                    delay_sr_tcf <= y;
                                    rg_phase <= z;
                                    rg_count_bytes <= 0;
                                    if (ccr_ddrm==1)
                                    half_cycle_delay <= True;
                                    if (z==DataRead_phase)
                                    read_true <= True;
                                 end
                                 else
                                 rg_count_bits <= count_val;
                                 rg_output_en <= enable_o;
                              endrule

                              /* Rule to transfer the address bits of address outside. The size of address is
                              defined by the ccr_adsize register in ccr */
                              rule rl_transfer_address(rg_phase==Address_phase && transfer_cond && !qspi_flush);
                                 `logLevel(qspicontrol, 0, $format(": Address phase init"))
                                 if (half_cycle_delay && ccr_ddrm == 0 && clock_cond) begin
                                    `logLevel(qspicontrol, 0, $format(": Address phase initial delay 1"))
                                    half_cycle_delay <= False;
                                    read_true <= True;
                                 end
                                 else if (half_cycle_delay && ccr_ddrm == 1 && ddr_en == 0 && ccr_fmode != 'b11) begin
                                    if (rg_count == 3) begin
                                       ddr_en <= 1;
                                       half_cycle_delay <= False;
                                    end
                                    else begin
                                       rg_count <= rg_count + 1;
                                    end
                                    `logLevel(qspicontrol, 0, $format(": Address phase initial delay 2"))
                                 end
                                 else if (ccr_ddrm == 1 && ccr_fmode == 'b11 && ddr_en == 0 && init_mm_xip_delay == 0) begin
                                    let cmp = 2;
                                    if (ccr_dmode == 1)
                                    cmp = 3;
                                    if (rg_count == cmp) begin
                                       ddr_en <= 1;
                                       init_mm_xip_delay <= 1;
                                    end
                                    else begin
                                       rg_count <= rg_count + 1;
                                    end
                                    `logLevel(qspicontrol, 0, $format(": Address phase initial delay 3"))
                                 end
                                 else if (ccr_ddrm == 1 && ddr_en == 0) begin
                                    rg_count <= 1;
                                    ddr_en <= 1;
                                    `logLevel(qspicontrol, 0, $format(": Address phase initial delay 4"))
                                 end
                                 else if ((clock_cond && ccr_ddrm == 0) || (ccr_ddrm == 1 && ddr_en == 1)) begin
                                    if (rg_count > 0) begin
                                       rg_count <= 0;
                                       ddr_en <= 0;
                                    end
                                    Bool end_of_phase=False;
                                    Bit#(4) enable_o=0;
                                    let count_val=rg_count_bits;
                                    Bit#(32) address=(ccr_fmode=='b11)?zeroExtend(mm_address):ar;
                                    rg_prev_addr <= truncate(address);
                                    `logLevel(qspicontrol, 0, $format(": Executing Address Phase SPI Mode: %b Address Size: %d Count_bits: %d Address: %b",ccr_admode,ccr_adsize,rg_count_bits,address))
                                    if (ccr_admode=='b01)begin  // single spi mode;
                                       enable_o=4'b1101;
                                       rg_output <= {1'b1,1'b0,1'b0,address[rg_count_bits-1]};
                                       `logLevel(qspicontrol, 0, $format("Single: Sending Address bit %h bit_number: %d total_address: %h",rg_count_bits-1,address[rg_count_bits-1],address))
                                       if (rg_count_bits==1)begin  // End of address stream
                                          end_of_phase=True;
                                       end
                                       else
                                       count_val=rg_count_bits-1;
                                    end
                                    else if (ccr_admode=='b10)begin  // dual mode;
                                       enable_o=4'b1111;
                                       rg_output <= {1'b1,1'b0,address[rg_count_bits-1:rg_count_bits-2]};
                                       `logLevel(qspicontrol, 0, $format("Double: Sending Address bit %h bit_number: %d total_address: %h",rg_count_bits-1,address[rg_count_bits-1],address))
                                       if (rg_count_bits==2)begin  // End of address stream
                                          end_of_phase=True;
                                       end
                                       else
                                       count_val=rg_count_bits-2;
                                    end
                                    else if (ccr_admode=='b11)begin  // quad mode;
                                       enable_o=4'b1111;
                                       rg_output <= address[rg_count_bits-1:rg_count_bits-4];
                                       `logLevel(qspicontrol, 0, $format("Quad: Sending Address bit %h bit_number: %d total_address: %h",rg_count_bits-1,address[rg_count_bits-1],address))
                                       if (rg_count_bits==4)begin  // End of address stream
                                          end_of_phase=True;
                                       end
                                       else
                                       count_val=rg_count_bits-4;
                                    end
                                    if (end_of_phase || ccr_admode==0)begin  // End of address phase
                                       let {x,y,z} <- change_phase.func(rg_phase,count_val,0);
                                       rg_count_bits <= x;
                                       delay_sr_tcf <= y;
                                       rg_phase <= z;
                                       rg_count_bytes <= 0;
                                       init_mm_xip_delay <= 0;
                                       if (ccr_ddrm == 1 && ccr_dmode != 1)
                                       half_cycle_delay <= True;
                                       if (z==DataRead_phase)
                                       read_true <= True;
                                    end
                                    else
                                    rg_count_bits <= count_val;
                                    rg_output_en <= enable_o;
                                 end
                              endrule

                              /* Rule to transfer the alternate bytes. The size of alternate bytes is
                              defined by the ccr_absize register in ccr */
                              rule rl_transfer_alternatebytes(rg_phase==AlternateByte_phase && transfer_cond && clock_cond && !qspi_flush);
                                 Bool end_of_phase=False;
                                 let count_val=rg_count_bits;
                                 `logLevel(qspicontrol, 0, $format("Executing AltByte Phase SPI Mode: %b AltByte Size: %d Count_bits: %d AltByte: %b",ccr_abmode,ccr_absize,rg_count_bits,abr))
                                 Bit#(4) enable_o=0;
                                 if (ccr_abmode=='b01)begin  // single spi mode;
                                    enable_o=4'b1101;
                                    rg_output <= {1'b1,1'b0,1'b0,abr[rg_count_bits-1]};
                                    if (rg_count_bits==1)begin  // End of instruction stream
                                       end_of_phase=True;
                                    end
                                    else
                                    count_val=rg_count_bits-1;
                                 end
                                 else if (ccr_abmode=='b10)begin  // dual mode;
                                    enable_o=4'b1111;
                                    rg_output <= {1'b1,1'b0,abr[rg_count_bits-1:rg_count_bits-2]};
                                    if (rg_count_bits==2)begin  // End of instruction stream
                                       end_of_phase=True;
                                    end
                                    else
                                    count_val=rg_count_bits-2;
                                 end
                                 else if (ccr_abmode=='b11)begin  // quad mode;
                                    enable_o=4'b1111;
                                    rg_output <= abr[rg_count_bits-1:rg_count_bits-4];
                                    if (rg_count_bits==4)begin  // End of instruction stream
                                       end_of_phase=True;
                                    end
                                    else
                                    count_val=rg_count_bits-4;
                                 end
                                 if (end_of_phase || ccr_abmode==0)begin  // End of alternate byte phase
                                    let {x,y,z} <- change_phase.func(rg_phase,count_val,0);
                                    rg_count_bits <= x;
                                    delay_sr_tcf <= y;
                                    rg_phase <= z;
                                    rg_count_bytes <= 0;
                                    if (z==DataRead_phase)
                                    read_true <= True;end
                                    else
                                    rg_count_bits <= count_val;
                                    rg_output_en <= enable_o;
                                 endrule

                                 rule rl_transfer_dummy_cycle(rg_phase==Dummy_phase && transfer_cond && !qspi_flush);
                                    if (ccr_ddrm == 1 && half_cycle_delay) begin
                                       if (rg_count == 0) begin
                                          half_cycle_delay <= False;
                                          ddr_en <= 1;
                                       end
                                       else
                                       rg_count <= rg_count + 1;
                                       `logLevel(qspicontrol, 0, $format(": dummy init delay"))
                                    end
                                    else if ((clock_cond && ccr_ddrm == 0) || (ccr_ddrm == 1 && ddr_en == 1)) begin
                                       rg_count <= 0;
                                       ddr_en <= 0;
                                       let {x,y,z} <- change_phase.func(rg_phase,rg_count_bits,0);
                                       Bit#(5) count_val = rg_mode_byte_counter;
                                       Bit#(4) enable_o = rg_output_en;
                                       `logLevel(qspicontrol, 0, $format(": Executing Dummy Phase: rg_mode_bytes: %b rg_mode_byte_counter: %d",rg_mode_bytes, rg_mode_byte_counter))
                                       if (ccr_dmode==1) begin
                                          if (ccr_dummy_confirmation==1) begin
                                             //rg_output_en <= 4'b1101;
                                             enable_o = 4'b1101;
                                             rg_output <= {1'b1,1'b0,1'b0,rg_mode_bytes[rg_mode_byte_counter]};
                                             if (count_val>=28)
                                             count_val = count_val - 1;
                                             else
                                             enable_o = 4'b1100;
                                          end
                                          else begin
                                             //rg_output_en <= 4'b1101;
                                             enable_o = 4'b1100;
                                             rg_output <= {1'b1,1'b0,1'b0,1'b0};
                                          end
                                       end
                                       else if (ccr_dmode==2) begin
                                          if (ccr_dummy_confirmation==1) begin
                                             //rg_output_en <= 4'b1111;
                                             enable_o = 4'b1111;
                                             rg_output <= {1'b1,1'b0,rg_mode_bytes[rg_mode_byte_counter:rg_mode_byte_counter-1]};
                                             if (count_val>=28)
                                             count_val = count_val - 2;
                                             else
                                             enable_o = 4'b1100;
                                          end
                                          else begin
                                             //rg_output_en <= 4'b1100;
                                             enable_o = 4'b1100;
                                             rg_output <= {1'b1,1'b0,1'b0,1'b0};
                                          end
                                       end
                                       else begin
                                          if (ccr_dummy_confirmation==1) begin
                                             //rg_output_en <= 4'b1111;
                                             enable_o = 4'b1111;
                                             rg_output <= rg_mode_bytes[rg_mode_byte_counter:rg_mode_byte_counter-3];
                                             `logLevel(qspicontrol, 0, $format("Dummy in memory map mode is firing %h",rg_output))
                                             if (count_val>=28)
                                             count_val = count_val - 4;
                                             else
                                             enable_o = 4'b0000;  // ##
                                          end
                                          else begin
                                             //rg_output_en <= 4'b0000;
                                             enable_o = 4'b0000;
                                          end
                                       end
                                       if (rg_count_bits==0 || (rg_count_bits==1 && z!=DataRead_phase))begin  // End of dummy cycles;
                                          delay_sr_tcf <= y;
                                          rg_phase <= z;
                                          `logLevel(qspicontrol, 0, $format("From Dummy to :",fshow(z)))
                                          if (z==DataRead_phase) begin
                                             if (ccr_ddrm == 0)  //##
                                             read_true <= True;
                                             `logLevel(qspicontrol, 0, $format(": read is updated in dummy phase"))
                                          end
                                          rg_count_bytes <= 0;
                                          rg_count_bits <= x;
                                          rg_mode_byte_counter <= 'd-1;  //All ones
                                          if (ccr_ddrm==1)
                                          half_cycle_delay <= True;
                                       end
                                       else begin
                                          rg_count_bits <= rg_count_bits-1;
                                          rg_mode_byte_counter <= count_val;
                                          rg_output_en <= enable_o;
                                       end
                                    end
                                    else
                                    ddr_en <= 1;
                                 endrule

                                 /* Rule to transfer the dummy_cycles. The size of dummy cycles is
                                 defined by the ccr_dcyc register in ccr. The number of dummy cycles should be calculated of
                                 the complete cycle even in DDR mode hence using sdr clock*/
                                 /* rule rl_transfer_dummy_cycle(rg_phase==Dummy_phase && transfer_cond && wr_sdr_clock && !qspi_flush);
                                 let {x,y,z} <- change_phase.func(rg_phase,rg_count_bits,0);
                                 `logLevel(qspicontrol, 0, $format("Executing Dummy Phase, Dummy_confirmation_bit : %d dummy_bit : %d", ccr_dummy_confirmation, ccr_dummy_bit))
                                 if (ccr_dmode==1) begin
                                    if (ccr_dummy_confirmation==1) begin
                                       rg_output_en <= 4'b1101;
                                       rg_output <= {1'b1,1'b0,1'b0,ccr_dummy_bit};
                                       ccr_dummy_confirmation <= 0;
                                    end
                                    else begin
                                       rg_output_en <= 4'b1101;
                                       rg_output <= {1'b1,1'b0,1'b0,1'b0};
                                    end
                                 end
                                 else if (ccr_dmode==2) begin
                                    if (ccr_dummy_confirmation==1) begin
                                       rg_output_en <= 4'b1101;
                                       rg_output <= {1'b1,1'b0,1'b0,ccr_dummy_bit};
                                       ccr_dummy_confirmation <= 0;
                                    end
                                    else begin
                                       rg_output_en <= 4'b1100;
                                       rg_output <= {1'b1,1'b0,1'b0,1'b0};
                                    end
                                 end
                                 else begin
                                    if (ccr_dummy_confirmation==1) begin
                                       `logLevel(qspicontrol, 0, $format("Data going to output %d", ccr_dummy_bit))
                                       rg_output_en <= 1;
                                       rg_output[0] <= ccr_dummy_bit;
                                       ccr_dummy_confirmation <= 0;
                                    end
                                    else
                                    rg_output_en <= 0;
                                 end
                                 if (rg_count_bits==0 || (rg_count_bits==1 && z!=DataRead_phase))begin  // End of dummy cycles;
                                    delay_sr_tcf <= y;
                                    rg_phase <= z;
                                    `logLevel(qspicontrol, 0, $format("From Dummy to :",fshow(z)))
                                    if (z==DataRead_phase)
                                    read_true <= True;
                                    rg_count_bytes <= 0;
                                    rg_count_bits <= x;
                                    if (ccr_ddrm==1)
                                    half_cycle_delay <= True;
                                 end
                                 else begin
                                    rg_count_bits <= rg_count_bits-1;
                                 end
                                 endrule*/

                                 /* read data from the flash memory and store it in the DLR register. Simulataneously
                                 put Bytes in the FIFO*/
                                 (*descending_urgency="rl_data_read_phase,rl_read_request_from_AXI"*)
                                 (*descending_urgency="rl_data_read_phase,rl_write_request_from_AXI"*)
                                 rule rl_data_read_phase(rg_phase==DataRead_phase /*&& ccr_fmode!='b11*/ && transfer_cond && !qspi_flush);
                                    //rg_output_en <= 0;
                                    if ((half_cycle_delay || read_true) && ccr_ddrm == 0 && clock_cond) begin
                                       half_cycle_delay <= False;
                                       read_true <= False;
                                    end
                                    else if ((half_cycle_delay || read_true) && ccr_ddrm == 1) begin
                                       if (rg_count == 2) begin
                                          half_cycle_delay <= False;
                                          read_true <= False;
                                       end
                                       else
                                       rg_count <= rg_count + 1;
                                    end
                                    else if (clock_cond) begin
                                       rg_count <= 0;
                                       Bit#(32) data_reg=dr;
                                       Bit#(32) count_byte=rg_count_bytes;
                                       Bit#(32) count_bits=rg_count_bits;
                                       Bit#(32) data_length1=(ccr_fmode=='b11)?mm_data_length:dlr;
                                       `logLevel(qspicontrol, 0, $format(": Executing DataRead Phase SPI Mode: %b DLR : %d Count_bits: %d Input :%b ccr_ddrm: %b rg_count_byte %h",ccr_dmode,data_length1,rg_count_bits,rg_input,ccr_ddrm, rg_count_bytes))
                                       /* write incoming bit to the data register */
                                       if (ccr_dmode==1)begin  // single line mode;
                                          data_reg=data_reg<<1;
                                          data_reg[0]=rg_input[1];
                                          `logLevel(qspicontrol, 0, $format("Single data_reg : %b",data_reg))
                                          count_bits=count_bits+1;
                                          rg_output_en <= 4'b1101;
                                          rg_output <= {1'b1,1'b0,1'b0,1'b0};

                                       end
                                       else if (ccr_dmode==2)begin  // dual line mode;
                                          rg_output_en <= 4'b1100;
                                          data_reg=data_reg<<2;
                                          data_reg[1:0]=rg_input[1:0];
                                          `logLevel(qspicontrol, 0, $format("Dual data_reg : %b",data_reg))
                                          count_bits=count_bits+1;
                                          rg_output <= {1'b1,1'b0,1'b0,1'b0};
                                       end
                                       else if (ccr_dmode==3) begin  // quad line mode;
                                          rg_output_en <= 4'b0000;
                                          data_reg=data_reg<<4;
                                          data_reg[3:0]=rg_input;
                                          `logLevel(qspicontrol, 0, $format("Quad data_reg : %b",data_reg))
                                          count_bits=count_bits+1;
                                       end

                                       `logLevel(qspicontrol, 0, $format(" Data read phase data_length %h data_length1 %h", data_length, data_length1))
                                       /* write the last successfully received byte into the FIFO */
                                       if (ccr_dmode==1)begin  // single line mode
                                          if (count_byte==data_length1 && ccr_ddrm==1 && count_bits[2:0]=='b111)  //To make sure that the Flash does not send any data the next half edge since ncs is made 1 after the second edge
                                          ncs <= 1;
                                          if (rg_count_bits[2:0]=='b111)begin  // multiple of eight bits have been read.
                                             `logLevel(qspicontrol, 0, $format("Enquing FIFO count_byte %h", count_byte))
                                             Vector#(4,Bit#(8)) temp = newVector();
                                             temp[0]=data_reg[7:0];
                                             `logLevel(qspicontrol, 0, $format("Single Enqueing FIFO : data is %h",temp[0]))
                                             if (!first_read)
                                             fifo.enq(1,temp);
                                             count_byte=count_byte+1;
                                          end
                                       end
                                       else if (ccr_dmode==2) begin  // dual line mode
                                          if (count_byte==data_length1 && ccr_ddrm==1 && count_bits[1:0]=='b11) begin  //To make sure that the Flash does not send any data the next half edge since ncs is made 1 after the second edge
                                             `logLevel(qspicontrol, 0, $format("data read phase ncs made 1"))
                                             ncs <= 1;
                                          end
                                          if (rg_count_bits[1:0]=='b11)begin  // multiple of eight bits have been read.
                                             `logLevel(qspicontrol, 0, $format("Enquing FIFO"))
                                             Vector#(4,Bit#(8)) temp = newVector();
                                             temp[0]=data_reg[7:0];
                                             `logLevel(qspicontrol, 0, $format("Dual Enqueing FIFO : data is %h",temp[0]))
                                             if (!first_read)
                                             fifo.enq(1,temp);
                                             count_byte=count_byte+1;
                                          end
                                       end
                                       else if (ccr_dmode==3) begin  // quad line mode
                                          if (count_byte==data_length1 && ccr_ddrm==1 && count_bits[0]=='b1)  //To make sure that the Flash does not send any data the next half edge since ncs is made 1 after the second edge
                                          ncs <= 1;
                                          if (rg_count_bits[0]=='b1)begin  // multiple of eight bits have been read.
                                             `logLevel(qspicontrol, 0, $format("Enquing FIFO"))
                                             Vector#(4,Bit#(8)) temp = newVector();
                                             temp[0]=data_reg[7:0];
                                             `logLevel(qspicontrol, 0, $format("Quad Enqueing FIFO : data is %h",temp[0]))
                                             if (!first_read)
                                             fifo.enq(1,temp);
                                             count_byte=count_byte+1;
                                          end
                                       end

                                       bit smf=0;
                                       `logLevel(qspicontrol, 0, $format("count_byte: %d data_length1: %d",count_byte,data_length1))
                                       /* condition for termination of dataread_phase */
                                       if (data_length1!='hFFFFFFFF)begin  // if limit is not undefined
                                          if (count_byte==data_length1)begin  // if limit has bee reached.
                                             `logLevel(qspicontrol, 0, $format("Limit has reached: rg_count_bytes %h data_length %h",count_byte,data_length))
                                             if (ccr_fmode=='b10)begin  // auto-status polling mode
                                                if (cr_pmm==0)begin  // ANDed mode
                                                   if ((psmar&psmkr) == (psmkr&dr))  // is the unmasked bits match
                                                   smf=1;
                                                   else
                                                   smf=0;
                                                end
                                                else begin  // ORed mode
                                                   let p=psmkr&dr;
                                                   let q=psmkr&psmar;
                                                   let r=~(p^q);
                                                   if (|(r)==1)
                                                   smf=1;
                                                   else
                                                   smf=0;
                                                end
                                             end
                                             else if (ccr_fmode=='b11)begin  // memory mapped mode
                                                if (first_read) begin

                                                   let data =case (data_length1)
                                                   1 : duplicate(data_reg[7:0]);
                                                   2 : duplicate(data_reg[15:0]);
                                                   4 : duplicate(data_reg[31:0]);
                                                   default: data_reg;
                                                endcase;

                                                `logLevel(qspicontrol, 0, $format("Sending response back to the proc data_reg: %h",data_reg))
                                                wr_rd_resp <= tagged Valid Rd_resp {
                                                   rsp : AXI4_LITE_OKAY,
                                                   rdata : duplicate(data)};
                                                   //                            let r = AXI4_Lite_Rd_Data {rresp: AXI4_LITE_OKAY, rdata: duplicate(data_reg) , ruser: 0};
                                                   //    				        s_xactor.i_rd_data.enq(r);
                                                   first_read <= False;
                                                   //rg_request_ready <= True;
                                                end
                                             end
                                             let {x,y,z} <- change_phase.func(rg_phase,rg_count_bits,smf);
                                             /* if (z==DataRead_phase)
                                             read_true <= True;*/
                                             rg_phase <= z;
                                             `logLevel(qspicontrol, 0, $format("rg_phase:",fshow(z)," sr_tcf: %d",y))
                                             sr_tcf <= y;  // set completion of transfer flag
                                             rg_count_bytes <= 0;
                                             rg_count_bits <= 0;
                                          end
                                          else begin
                                             rg_count_bytes <= count_byte;
                                             rg_count_bits <= count_bits;
                                             `logLevel(qspicontrol, 0, $format(": read data count bits 1"))
                                          end
                                       end
                                       else if (dcr_fsize!='h1f)begin  // if limit is not infinite
                                          Bit#(32) new_limit=1<<(dcr_fsize);
                                          `logLevel(qspicontrol, 0, $format("Sending completion -- newlimit : %h",new_limit))
                                          if (truncate(rg_count_bytes)==new_limit)begin  // If reached End of Flash memory
                                             let {x,y,z} <- change_phase.func(rg_phase,rg_count_bits,smf&cr_apms);
                                             rg_phase <= z;
                                             if (z==DataRead_phase)
                                             read_true <= True;
                                             sr_tcf <= y;  // set completion of transfer flag
                                             rg_count_bytes <= 0;
                                             rg_count_bits <= 0;
                                          end
                                          else begin
                                             rg_count_bytes <= count_byte;
                                             rg_count_bits <= count_bits;
                                             `logLevel(qspicontrol, 0, $format(": read data count bits 2"))
                                          end
                                       end
                                       else begin  // keep looping until abort signal is not raised.
                                          rg_count_bytes <= count_byte;
                                          rg_count_bits <= count_bits;
                                          `logLevel(qspicontrol, 0, $format(": read data count bits 3"))
                                       end
                                       dr <= data_reg;
                                       sr_smf <= smf;
                                    end
                                 endrule

                                 /* write data from the FIFO to the FLASH. Simulataneously*/
                                 (*descending_urgency="rl_data_write_phase,rl_read_request_from_AXI"*)
                                 // (*descending_urgency="rl_data_write_phase,rl_write_request_from_AXI"*)
                                 (*preempts="rl_write_request_from_AXI, rl_data_write_phase"*)
                                 (*preempts=" rl_data_write_phase, delayed_sr_tcf_signal"*)
                                 (*preempts=" rl_data_read_phase, delayed_sr_tcf_signal"*)
                                 (*preempts=" delayed_sr_tcf_signal, rl_read_request_from_AXI"*)
                                 (*preempts=" rl_write_request_from_AXI, delayed_sr_tcf_signal"*)
                                 (*preempts=" rl_write_request_from_AXI, set_error_signal"*)
                                 (*preempts=" rl_write_request_from_AXI, timeout_counter"*)
                                 (*preempts=" rl_write_request_from_AXI, rl_read_request_from_AXI"*)

                                 rule rl_data_write_phase(rg_phase==DataWrite_phase && transfer_cond && clock_cond && !qspi_flush);
                                    if (half_cycle_delay)
                                    half_cycle_delay <= False;
                                    else begin
                                       Bit#(8) data_reg=fifo.first()[0];
                                       Bit#(32) count_byte=rg_count_bytes;
                                       Bit#(32) count_bits=rg_count_bits;
                                       Bit#(4) enable_o=0;
                                       /* write incoming bit to the data register */
                                       if (ccr_dmode==1)begin  // single line mode;
                                          enable_o=4'b1101;
                                          rg_output <= {1'b1,1'b0,1'b0,data_reg[rg_count_bits-1]};
                                          count_bits=count_bits-1;
                                       end
                                       else if (ccr_dmode==2)begin  // dual line mode;
                                          enable_o=4'b1111;
                                          rg_output <= {1'b1,1'b0,data_reg[rg_count_bits-1:rg_count_bits-2]};
                                          count_bits=count_bits-2;
                                       end
                                       else if (ccr_dmode==3) begin  // quad line mode;
                                          enable_o=4'b1111;
                                          rg_output <= data_reg[rg_count_bits-1:rg_count_bits-4];
                                          count_bits=count_bits-4;
                                       end
                                       `logLevel(qspicontrol, 0, $format("Executing DataWrite Phase SPI Mode: %b DLR : %d Count_bits: %d Input :%b Enable: %b",ccr_dmode,dlr,rg_count_bits,rg_input,enable_o))

                                       /* write the last successfully received byte into the FIFO */
                                       if (ccr_dmode==1)begin  // single line mode
                                          if (rg_count_bits==1)begin  // multiple of eight bits have been read.
                                             fifo.deq(1);
                                             count_byte=count_byte+1;
                                             count_bits=8;
                                          end
                                       end
                                       else if (ccr_dmode==2) begin  // dual line mode
                                          if (rg_count_bits==2)begin  // multiple of eight bits have been read.
                                             fifo.deq(1);
                                             count_byte=count_byte+1;
                                             count_bits=8;
                                          end
                                       end
                                       else if (ccr_dmode==3) begin  // quad line mode
                                          if (rg_count_bits==4)begin  // multiple of eight bits have been read.
                                             fifo.deq(1);
                                             count_byte=count_byte+1;
                                             count_bits=8;
                                          end
                                       end

                                       /* condition for termination of dataread_phase */
                                       if (dlr!='hFFFFFFFF)begin  // if limit is not undefined
                                          if (rg_count_bytes==dlr)begin  // if limit has bee reached.
                                             rg_phase <= Idle;
                                             sr_tcf <= 1;  // set completion of transfer flag
                                             rg_count_bytes <= 0;
                                             rg_count_bits <= 0;
                                          end
                                          else begin
                                             rg_count_bytes <= count_byte;
                                             rg_count_bits <= count_bits;
                                          end
                                       end
                                       else if (dcr_fsize!='h1f)begin  // if limit is not infinite
                                          Bit#(32) new_limit=1<<(dcr_fsize);
                                          if (truncate(rg_count_bytes)==new_limit)begin  // If reached End of Flash memory
                                             rg_phase <= Idle;
                                             sr_tcf <= 1;  // set completion of transfer flag
                                             rg_count_bytes <= 0;
                                             rg_count_bits <= 0;
                                          end
                                          else begin
                                             rg_count_bytes <= count_byte;
                                             rg_count_bits <= count_bits;
                                          end
                                       end
                                       else begin  // keep looping untill abort signal is not raised.
                                          rg_count_bytes <= count_byte;
                                          rg_count_bits <= count_bits;
                                       end
                                       rg_output_en <= enable_o;
                                    end
                                 endrule

                                 rule display_all_Registers;
                                    `logLevel(qspicontrol, 0, $format("\tPhase: ",fshow(rg_phase)," CR WRitten %d",wr_instruction_written, "Address Written: %d",wr_address_written))
                                    `logLevel(qspicontrol, 0, $format("\tCR: %h\tDCR: %h\tSR: %h\tFCR: %h",cr,dcr,sr,fcr))
                                    `logLevel(qspicontrol, 0, $format("\tDLR: %h\tCCR: %h\tAR: %h\tABR: %h",dlr,ccr,ar,abr))
                                    `logLevel(qspicontrol, 0, $format("\tDR: %h\tPSMKR: %h\tPSMAR: %h\tPIR: %h",dr,psmkr,psmar,pir,"\n"))
                                 endrule

                                 `ifdef simulate
                                    rule delay_phase(((wr_sdr_clock && ccr_ddrm==0) || (ddr_clock && ccr_ddrm==1)));
                                       rg_phase_delayed <= rg_phase;
                                    endrule
                                 `endif

                                 interface QSPI_out io;
                                    method bit clk_o;
                                    return delay_ncs==1?dcr_ckmode:rg_clk;
                                 endmethod
                                 method Bit#(4) io_o;
                                    return rg_output;
                                 endmethod
                                 method Bit#(4) io_enable;
                                    return rg_output_en;
                                 endmethod
                                 method Action io_i (Bit#(4) io_in);  // in
                                    if (rg_phase==DataRead_phase)
                                    `logLevel(qspicontrol, 0, $format(" <= = Input to QSPI from BFM : %b \n", io_in))
                                    rg_input <= io_in;
                                 endmethod
                                 method bit ncs_o = ncs;
                              endinterface

                              method Action write_req(Maybe#(Write_req#(addr_width, data_width)) wr_req);
                                 wr_qspi_req <= wr_req;
                              endmethod
                              method Maybe#(AXI4_Lite_Resp) write_resp;
                                 return wr_write_resp;
                              endmethod
                              method Action rd_req(Maybe#(Read_req#(addr_width)) req);
                                 //wr_rd_req <= req;
                                 ff_rd_req.enq(fromMaybe(?,req));
                                 //`logLevel(qspicontrol, 0, $format(" QSPI: i am firing"))
                              endmethod
                              method Maybe#(Rd_resp#(data_width)) rd_resp;
                                 return wr_rd_resp;
                              endmethod

                              method Bit#(1) interrupts;  // 0=TOF, 1=SMF, 2=Threshold, 3=TCF, 4=TEF 5=request_ready
                                 return |{1'b0,sr_tef&cr_teie, sr_tcf&cr_tcie, sr_ftf&cr_ftie, sr_smf&cr_smie , sr_tof&cr_toie};
                              endmethod
                              `ifdef simulate method curphase = rg_phase_delayed; `endif
                              endmodule

                              interface Ifc_qspi_axi4lite#(numeric type addr_width,
                                 numeric type data_width,
                                 numeric type user_width);
                                 interface QSPI_out io;
                                 interface AXI4_Lite_Slave_IFC#(addr_width, data_width, user_width) slave;
                                 method Bit#(1) interrupts;  // 0=TOF, 1=SMF, 2=Threshold, 3=TCF, 4=TEF 5 = request_ready
                              endinterface

                              //(*synthesize*)
                              module mkqspi_axi4lite#(Clock slow_clk, Reset slow_rst, Bit#(32) start_mm_addr, Bit#(32) end_mm_addr `ifdef testmode ,Bool test_mode `endif )(Ifc_qspi_axi4lite#(addr_width,
                                 data_width,
                                 user_width))
                                 provisos(Add#(a__, 28, addr_width),Mul#(32, b__, data_width),Add#(c__,addr_width,32));

                                 Reg#(bit) rg_req_en <- mkRegA(0);
                                 AXI4_Lite_Slave_Xactor_IFC #(addr_width, data_width, user_width) s_xactor <- mkAXI4_Lite_Slave_Xactor;

                                 SyncFIFOIfc#(Maybe#(Write_req#(addr_width,data_width))) ff_wr_req <- mkSyncFIFOFromCC(1, slow_clk);
                                 SyncFIFOIfc#(AXI4_Lite_Resp) ff_sync_wr_resp <- mkSyncFIFOToCC(1, slow_clk, slow_rst);
                                 SyncFIFOIfc#(Maybe#(Read_req#(addr_width))) ff_rd_req <- mkSyncFIFOFromCC(1, slow_clk);
                                 SyncFIFOIfc#(Rd_resp#(data_width)) ff_sync_rd_resp <- mkSyncFIFOToCC(1, slow_clk, slow_rst);

                                 Ifc_qspi_controller#(addr_width, data_width, user_width) qspi <- mkqspi_controller(start_mm_addr,end_mm_addr,clocked_by slow_clk, reset_by slow_rst);
                                 (*preempts="rl_write_request, rl_read_request"*)
                                 rule rl_write_request(rg_req_en == 0);  // this Rule is running at fast_clk (i.e 166MHz)
                                    let aw <- pop_o (s_xactor.o_wr_addr);
                                    let w <- pop_o (s_xactor.o_wr_data);
                                    ff_wr_req.enq(tagged Valid (Write_req {
                                       addr : truncate(aw.awaddr),
                                       burst_size : extend(aw.awsize),
                                       wdata : truncate(w.wdata) }));
                                       rg_req_en <= 1;
                                       `logLevel(qspicontrol, 0, $format(" QSPI: Received Write request addr %x data %x ", aw.awaddr, w.wdata))
                                    endrule

                                    rule rl_write_req_send_to_controller;  // this Rule is running at slow_clk (i.e less than or equal to 166MHz)
                                       let w = ff_wr_req.first;
                                       ff_wr_req.deq;
                                       qspi.write_req(w);
                                    endrule

                                    rule rl_write_response(isValid(qspi.write_resp));  // this Rule is running at slow_clk (i.e less than or equal to 166MHz)
                                       ff_sync_wr_resp.enq(fromMaybe(?, qspi.write_resp));
                                       `logLevel(qspicontrol, 0, $format(" QSPI: Sending Write response"))
                                    endrule

                                    rule rl_write_response_sent_to_host;  // this Rule is running at fast_clk (i.e 166MHz)
                                       let w = ff_sync_wr_resp.first;
                                       ff_sync_wr_resp.deq;
                                       rg_req_en <= 0;
                                       let b = AXI4_Lite_Wr_Resp {bresp : w, buser : 0};
                                       s_xactor.i_wr_resp.enq (b);
                                    endrule

                                    rule rl_read_request(rg_req_en == 0);  // this Rule is running at fast_clk (i.e 166MHz)
                                       let ar <- pop_o(s_xactor.o_rd_addr);
                                       ff_rd_req.enq(tagged Valid (Read_req {
                                          addr : truncate(ar.araddr),
                                          burst_size : extend(ar.arsize)}));
                                          rg_req_en <= 1;
                                          `logLevel(qspicontrol, 0, $format("QSPI: qspi received read request"))
                                       endrule

                                       rule rl_read_request_send_to_controller;  // this Rule is running at slow_clk (i.e less than or equal to 166MHz)
                                          let r = ff_rd_req.first;
                                          ff_rd_req.deq;
                                          `logLevel(qspicontrol, 0, $format("QSPI: qspi sent read request"))
                                          qspi.rd_req(r);
                                       endrule

                                       rule rl_read_response(isValid(qspi.rd_resp));  // this Rule is running at slow_clk (i.e less than or equal to 166MHz)
                                          ff_sync_rd_resp.enq(fromMaybe(?, qspi.rd_resp));
                                       endrule

                                       rule rl_read_response_send_to_host;  // this Rule is running at fast_clk (i.e 166MHz)
                                          let r = ff_sync_rd_resp.first;
                                          ff_sync_rd_resp.deq;
                                          rg_req_en <= 0;
                                          let rsp = AXI4_Lite_Rd_Data {rresp: r.rsp, rdata: duplicate(r.rdata) , ruser: 0};
                                          s_xactor.i_rd_data.enq(rsp);
                                          `logLevel(qspicontrol, 0, $format("QSPI: Sending Read Response"))
                                       endrule

                                       interface io = qspi.io;

                                          interface slave = s_xactor.axi_side;

                                          method Bit#(1) interrupts;
                                          return qspi.interrupts;
                                       endmethod

                                    endmodule

                                    interface Ifc_qspi_axi4#(numeric type addr_width,
                                       numeric type id_width,
                                       numeric type data_width,
                                       numeric type user_width);
                                       interface QSPI_out io;
                                       interface AXI4_Slave_IFC#(addr_width, id_width, data_width, user_width) slave;
                                       method Bit#(1) interrupts;  // 0=TOF, 1=SMF, 2=Threshold, 3=TCF, 4=TEF 5 = request_ready
                                    endinterface

                                    module mkqspi_axi4#(Clock slow_clk, Reset slow_rst, Bit#(32) start_mm_addr, Bit#(32) end_mm_addr `ifdef testmode ,Bool test_mode `endif )(Ifc_qspi_axi4#(addr_width,
                                       id_width,
                                       data_width,
                                       user_width))
                                       provisos(Add#(a__, 28, addr_width),Mul#(32, b__, data_width),Add#(c__,addr_width,32), Mul#(8, e__, data_width),Add#(d__, 8, data_width));

                                       Clock core_clock <- exposeCurrentClock;
                                       Reset core_reset <- exposeCurrentReset;

                                       Reg#(bit) rg_req_en <- mkRegA(0);
                                       Reg#(Bit#(id_width)) rg_rid <- mkRegA(0);
                                       Reg#(Bit#(id_width)) rg_wid <- mkRegA(0);
                                       Reg#(Bit#(8)) rg_rdburst_count <- mkRegA(0,clocked_by slow_clk, reset_by slow_rst);
                                       Reg#(Bit#(8)) rg_rdburst_count_rsp <- mkRegA(0,clocked_by slow_clk, reset_by slow_rst);
                                       Reg#(Bit#(8)) rg_rsp_burst_len <- mkRegA(0,clocked_by slow_clk, reset_by slow_rst);
                                       Reg#(Read_req_axi#(addr_width)) rg_rdpacket <- mkRegA(?,clocked_by slow_clk, reset_by slow_rst);

                                       AXI4_Slave_Xactor_IFC #(addr_width, id_width, data_width, user_width) s_xactor <- mkAXI4_Slave_Xactor;

                                       `ifdef qspi_clk_gate_en
                                          Reg#(bit) rg_clk_en <- mkRegA(0);
                                          GatedClockIfc qspi_gated_clk <- mkGatedClock(False,slow_clk);
                                          //Reset          qspi_gated_clk_rst <- mkAsyncReset(2,slow_rst,qspi_gated_clk.new_clk);
                                       `endif
                                       `ifdef qspi_loc_rst_en
                                          Reg#(Bit#(1)) rg_rst <- mkRegA(0);
                                          MakeResetIfc reg_reset <- mkReset(0,False,core_clock);  // create a new reset for curr_clk
                                          Reset qspi_curr_reset <- mkResetEither(reg_reset.new_rst,slow_rst);  // OR default and new_rst
                                          // Reset qspi_reg_rst <- mkAsyncReset(2,qspi_curr_reset,slow_clk);    // div rst

                                       `endif
                                       `ifdef qspi_clk_gate_loc_rst_en
                                          Reg#(Bit#(8)) rg_rst_clk = concatReg3(readOnlyReg(6'b0), `ifdef qspi_loc_rst_en rg_rst `else readOnlyReg(1'b0) `endif , `ifdef qspi_clk_gate_en rg_clk_en `else readOnlyReg(1'b0) `endif );
                                       `endif
                                       `ifdef qspi_clk_gate_en
                                          `ifdef qspi_loc_rst_en
                                             Ifc_qspi_controller#(addr_width, data_width, user_width) qspi <- mkqspi_controller(start_mm_addr, end_mm_addr,clocked_by qspi_gated_clk.new_clk, reset_by qspi_curr_reset );
                                          `else
                                             Ifc_qspi_controller#(addr_width, data_width, user_width) qspi <- mkqspi_controller(start_mm_addr, end_mm_addr,clocked_by qspi_gated_clk.new_clk, reset_by slow_rst );
                                          `endif
                                          SyncFIFOIfc#(Maybe#(Write_req#(addr_width,data_width))) ff_wr_req <- mkSyncFIFOFromCC(2, qspi_gated_clk.new_clk);
                                          SyncFIFOIfc#(AXI4_Lite_Resp) ff_sync_wr_resp <- mkSyncFIFOToCC(2, qspi_gated_clk.new_clk, slow_rst );
                                          SyncFIFOIfc#(Read_req_axi#(addr_width)) ff_rd_req <- mkSyncFIFOFromCC(2, qspi_gated_clk.new_clk);
                                          SyncFIFOIfc#(Rd_resp_axi#(data_width)) ff_sync_rd_resp <- mkSyncFIFOToCC(2, qspi_gated_clk.new_clk, slow_rst );

                                          rule clock_en;
                                             qspi_gated_clk.setGateCond(unpack(rg_clk_en));
                                          endrule
                                       `else
                                          `ifdef qspi_loc_rst_en
                                             Ifc_qspi_controller#(addr_width, data_width, user_width) qspi <- mkqspi_controller(start_mm_addr, end_mm_addr,clocked_by slow_clk, reset_by qspi_curr_reset );
                                          `else
                                             Ifc_qspi_controller#(addr_width, data_width, user_width) qspi <- mkqspi_controller(start_mm_addr, end_mm_addr,clocked_by slow_clk, reset_by slow_rst );
                                          `endif
                                          SyncFIFOIfc#(Maybe#(Write_req#(addr_width,data_width))) ff_wr_req <- mkSyncFIFOFromCC(2, slow_clk);
                                          SyncFIFOIfc#(AXI4_Lite_Resp) ff_sync_wr_resp <- mkSyncFIFOToCC(2, slow_clk, slow_rst );
                                          SyncFIFOIfc#(Read_req_axi#(addr_width)) ff_rd_req <- mkSyncFIFOFromCC(2, slow_clk);
                                          SyncFIFOIfc#(Rd_resp_axi#(data_width)) ff_sync_rd_resp <- mkSyncFIFOToCC(2, slow_clk, slow_rst );
                                       `endif
                                       `ifdef qspi_loc_rst_en
                                          rule reset_qspi(rg_rst == 1);
                                             reg_reset.assertReset;
                                          endrule
                                       `endif
                                       rule rl_write_request(rg_req_en == 0);  // this Rule is running at fast_clk (i.e 166MHz)
                                          let aw <- pop_o (s_xactor.o_wr_addr);
                                          let w <- pop_o (s_xactor.o_wr_data);
                                          `ifdef qspi_clk_gate_loc_rst_en
                                             if (aw.awaddr[7:0] == `Qspi_Clk_En) begin
                                                rg_rst_clk <= truncate(w.wdata);
                                                let b = AXI4_Wr_Resp {bresp : AXI4_OKAY, buser : 0, bid : aw.awid};
                                                s_xactor.i_wr_resp.enq (b);
                                                `logLevel(qspicontrol, 0, $format("QSPI: Sending gated clk Write response"))
                                             end
                                          `endif
                                          `ifndef qspi_clk_gate_loc_rst_en
                                             ff_wr_req.enq(tagged Valid (Write_req {
                                                addr : truncate(aw.awaddr),
                                                burst_size : aw.awsize,
                                                wdata : truncate(w.wdata) }));
                                                rg_req_en <= 1;
                                                rg_wid <= aw.awid;
                                             `elsif qspi_clk_gate_en
                                                else if (rg_clk_en == 1) begin
                                                   ff_wr_req.enq(tagged Valid (Write_req {
                                                      addr : truncate(aw.awaddr),
                                                      burst_size : aw.awsize,
                                                      wdata : truncate(w.wdata) }));
                                                      rg_req_en <= 1;
                                                      rg_wid <= aw.awid;
                                                   end
                                                `else
                                                   else begin
                                                      ff_wr_req.enq(tagged Valid (Write_req {
                                                         addr : truncate(aw.awaddr),
                                                         burst_size : aw.awsize,
                                                         wdata : truncate(w.wdata) }));
                                                         rg_req_en <= 1;
                                                         rg_wid <= aw.awid;
                                                      end
                                                   `endif
                                                   `ifdef qspi_clk_gate_en
                                                      else begin
                                                         let b = AXI4_Wr_Resp {bresp : AXI4_SLVERR, buser : 0, bid : aw.awid};
                                                         s_xactor.i_wr_resp.enq (b);
                                                      end
                                                   `endif
                                                   `logLevel(qspicontrol, 0, $format("QSPI: qspi received write request awaddr %h", aw.awaddr))
                                                endrule

                                                rule rl_write_req_send_to_controller;  // this Rule is running at slow_clk (i.e less than or equal to 166MHz)
                                                   let w = ff_wr_req.first;
                                                   ff_wr_req.deq;
                                                   qspi.write_req(w);
                                                endrule

                                                rule rl_write_response(isValid(qspi.write_resp));  // this Rule is running at slow_clk (i.e less than or equal to 166MHz)
                                                   ff_sync_wr_resp.enq(fromMaybe(?, qspi.write_resp));
                                                   `logLevel(qspicontrol, 0, $format("QSPI: Sending Write response"))
                                                endrule

                                                rule rl_write_response_sent_to_host;  // this Rule is running at fast_clk (i.e 166MHz)
                                                   let w = ff_sync_wr_resp.first;
                                                   ff_sync_wr_resp.deq;
                                                   rg_req_en <= 0;
                                                   AXI4_Resp resp = AXI4_OKAY;
                                                   if (w == AXI4_LITE_SLVERR)
                                                   resp = AXI4_SLVERR;
                                                   let b = AXI4_Wr_Resp {bresp : resp, buser : 0, bid : rg_wid};
                                                   s_xactor.i_wr_resp.enq (b);
                                                endrule

                                                rule rl_read_request(rg_req_en == 0);  // this Rule is running at fast_clk (i.e 166MHz)
                                                   let ar <- pop_o(s_xactor.o_rd_addr);
                                                   `ifdef qspi_clk_gate_loc_rst_en
                                                      if (ar.araddr[7:0] == `Qspi_Clk_En ) begin
                                                         let rsp = AXI4_Rd_Data {rresp: AXI4_OKAY, rdata: duplicate({rg_rst_clk}) , ruser: 0, rid: ar.arid, rlast: True};
                                                         s_xactor.i_rd_data.enq(rsp);
                                                         `logLevel(qspicontrol, 0, $format("QSPI: qspi sent read request"))
                                                      end
                                                   `endif
                                                   `ifndef qspi_clk_gate_loc_rst_en
                                                      ff_rd_req.enq(Read_req_axi {
                                                         addr : truncate(ar.araddr),
                                                         burst_size : ar.arsize,
                                                         burst_len : ar.arlen,
                                                         arburst : ar.arburst});
                                                         rg_req_en <= 1;
                                                         rg_rid <= ar.arid;
                                                      `elsif qspi_clk_gate_en
                                                         else if (rg_clk_en == 1) begin

                                                            ff_rd_req.enq(Read_req_axi {
                                                               addr : truncate(ar.araddr),
                                                               burst_size : ar.arsize,
                                                               burst_len : ar.arlen,
                                                               arburst : ar.arburst});
                                                               rg_req_en <= 1;
                                                               rg_rid <= ar.arid; end
                                                            `else
                                                               else begin
                                                                  ff_rd_req.enq(Read_req_axi {
                                                                     addr : truncate(ar.araddr),
                                                                     burst_size : ar.arsize,
                                                                     burst_len : ar.arlen,
                                                                     arburst : ar.arburst});
                                                                     rg_req_en <= 1;
                                                                     rg_rid <= ar.arid; end
                                                                  `endif
                                                                  `ifdef qspi_clk_gate_en
                                                                     else begin
                                                                        let rsp = AXI4_Rd_Data {rresp: AXI4_SLVERR, rdata: duplicate({rg_rst_clk}) , ruser: 0, rid: ar.arid, rlast: True};
                                                                        s_xactor.i_rd_data.enq(rsp);
                                                                     end
                                                                  `endif
                                                                  `logLevel(qspicontrol, 0, $format("QSPI: qspi received read request"))
                                                               endrule

                                                               rule rl_read_request_send_to_controller(rg_rdburst_count==0);  // this Rule is running at slow_clk (i.e less than or equal to 166MHz)
                                                                  let r = ff_rd_req.first;
                                                                  rg_rdpacket <= r;

                                                                  if (r.burst_len!=0)
                                                                  rg_rdburst_count <= 1;
                                                                  ff_rd_req.deq;
                                                                  //`logLevel(qspicontrol, 0, $format("QSPI: qspi sent read request"))
                                                                  qspi.rd_req(tagged Valid(Read_req {addr: r.addr, burst_size: r.burst_size}));
                                                               endrule

                                                               rule rl_read_request_send_to_controller_burst(rg_rdburst_count!=0);  // this Rule is running at slow_clk (i.e less than or equal to 166MHz)
                                                                  let rd_req=rg_rdpacket;
                                                                  rd_req.addr = axi4burst_addrgen(rd_req.burst_len, rd_req.burst_size, rd_req.arburst, rd_req.addr);

                                                                  rg_rdpacket.addr <= rd_req.addr;
                                                                  qspi.rd_req(tagged Valid(Read_req {addr: rd_req.addr, burst_size: rd_req.burst_size}));
                                                                  if (rg_rdburst_count==rd_req.burst_len)
                                                                  rg_rdburst_count <= 0;
                                                                  else
                                                                  rg_rdburst_count <= rg_rdburst_count+1;

                                                               endrule

                                                               rule rl_read_response(isValid(qspi.rd_resp) && (rg_rdburst_count_rsp==0));  // this Rule is running at slow_clk (i.e less than or equal to 166MHz)
                                                                  if (rg_rdpacket.burst_len!=0)
                                                                  rg_rdburst_count_rsp <= 1;

                                                                  let resp = fromMaybe(?, qspi.rd_resp);
                                                                  ff_sync_rd_resp.enq(Rd_resp_axi {rdata: resp.rdata, rsp: resp.rsp, last: (rg_rdburst_count==0)});

                                                               endrule

                                                               rule rl_read_response_burst(isValid(qspi.rd_resp) && (rg_rdburst_count_rsp!=0));  // this Rule is running at slow_clk (i.e less than or equal to 166MHz)

                                                                  Bool lv_rlast = rg_rdburst_count_rsp==rg_rdpacket.burst_len;

                                                                  let resp = fromMaybe(?, qspi.rd_resp);
                                                                  ff_sync_rd_resp.enq(Rd_resp_axi {rdata: resp.rdata, rsp: resp.rsp, last: lv_rlast});

                                                                  if (lv_rlast)
                                                                  rg_rdburst_count_rsp <= 0;
                                                                  else
                                                                  rg_rdburst_count_rsp <= rg_rdburst_count_rsp+1;

                                                               endrule

                                                               rule rl_read_response_send_to_host;  // this Rule is running at fast_clk (i.e 166MHz)
                                                                  let r = ff_sync_rd_resp.first;
                                                                  ff_sync_rd_resp.deq;

                                                                  if (r.last)
                                                                  rg_req_en <= 0;

                                                                  AXI4_Resp resp = AXI4_OKAY;
                                                                  if (r.rsp == AXI4_LITE_SLVERR)
                                                                  resp = AXI4_SLVERR;

                                                                  let rsp = AXI4_Rd_Data {rresp: resp, rdata: duplicate(r.rdata) , ruser: 0, rid: rg_rid, rlast: r.last};
                                                                  s_xactor.i_rd_data.enq(rsp);
                                                                  `logLevel(qspicontrol, 0, $format("QSPI: Sending Read Response"))
                                                               endrule

                                                               interface io = qspi.io;

                                                                  interface slave = s_xactor.axi_side;

                                                                  method Bit#(1) interrupts;
                                                                  return qspi.interrupts;
                                                               endmethod

                                                            endmodule

                                                         endpackage
