`timescale 1ns/1ps
//------------------------------------------------------------------------------
// Behavioural SDR SDRAM model with protocol and timing checks.
// Modelled after the ISSI IS42S32160F (16M x 32, 4 banks, 13 row / 9 column
// bits). Only the features used by U400 are modelled: burst length 1, CAS
// latency 2, auto precharge, auto refresh, load mode register.
//
// Memory is hashed on {bank, row[7:0], column} to keep the array small.
//------------------------------------------------------------------------------
module sdram_model #(
    parameter NAME  = "SDRAM",
    parameter tCK   = 12.5,
    parameter tRCD  = 20.0,   // IS42S32160F-7 numbers
    parameter tRP   = 20.0,
    parameter tRAS  = 42.0,
    parameter tRAS_MAX = 100000.0,
    parameter tRC   = 63.0,
    parameter tRFC  = 63.0,
    parameter tWR   = 2,      // clocks
    parameter tMRD  = 2,      // clocks
    parameter tAC   = 6.0,    // clock to output valid (CL2)
    parameter tOH   = 2.5,    // output hold after clock
    parameter tDS   = 1.5,    // input data setup
    parameter tDH   = 0.8,    // input data hold
    parameter tCMS  = 1.5     // command/address setup
)(
    input         CLK,
    input         CKE,
    input         CSn,
    input         RASn,
    input         CASn,
    input         WEn,
    input  [1:0]  BA,
    input  [12:0] A,
    input  [3:0]  DQM,        // {UU, UM, LM, LL} byte masks, active low enable
    inout  [31:0] DQ
);

integer errors = 0;

reg [31:0] mem [0:(1<<19)-1];

// Per bank state
reg         bank_open [0:3];
reg [12:0]  bank_row  [0:3];
real        bank_act_time [0:3];   // time of last ACTIVATE
real        bank_ready    [0:3];   // time at which the bank is precharged and idle
reg         bank_ap       [0:3];   // auto precharge pending, no more column commands allowed
real        refresh_busy_until = 0;
real        mode_busy_until    = 0;
integer     cas_latency = 0;
integer     burst_len   = 0;
reg         configured  = 0;

// Data output pipeline (CL = 2): entries for the next few clocks
reg         out_valid [0:7];
reg [31:0]  out_data  [0:7];
reg  [3:0]  out_mask  [0:7];
integer     clk_cnt = 0;

reg         dq_drive = 0;
reg [31:0]  dq_val   = 32'hx;
assign DQ = dq_drive ? dq_val : 32'hzzzzzzzz;

// Track DQ changes for setup / hold checks on writes
real dq_last_change = -1000;
reg [31:0] dq_prev;
always @(DQ) begin
    dq_last_change = $realtime;
end

// Command/address change tracking for setup checks
real cmd_last_change = -1000;
always @(CSn or RASn or CASn or WEn or BA or A or DQM) cmd_last_change = $realtime;

integer i;
initial begin
    for (i = 0; i < 4; i = i + 1) begin
        bank_open[i] = 0; bank_row[i] = 0; bank_act_time[i] = -1000; bank_ready[i] = 0; bank_ap[i] = 0;
    end
    for (i = 0; i < 8; i = i + 1) out_valid[i] = 0;
end

task err(input [8*80-1:0] msg);
    begin
        errors = errors + 1;
        $display("%0t %s SDRAM ERROR: %0s", $realtime, NAME, msg);
    end
endtask

function [18:0] hash(input [1:0] b, input [12:0] row, input [8:0] col);
    hash = {b, row[7:0], col};
endfunction

wire [2:0] cmd = {RASn, CASn, WEn};
localparam CMD_NOP = 3'b111, CMD_PRE = 3'b010, CMD_ACT = 3'b011, CMD_RD = 3'b101,
           CMD_WR = 3'b100, CMD_REF = 3'b001, CMD_LMR = 3'b000, CMD_BST = 3'b110;

integer k, pipe_idx;
reg [31:0] wdata;
real ap_start;

always @(posedge CLK) begin
    clk_cnt = clk_cnt + 1;
    pipe_idx = clk_cnt % 8;

    if (CKE !== 1'b1) err("CKE not high (clock suspend / power down not modelled)");

    // ---- Data output for this edge (scheduled by earlier READs) ----
    fork
        begin : outp
            reg v; reg [31:0] d; reg [3:0] m;
            v = out_valid[pipe_idx]; d = out_data[pipe_idx]; m = out_mask[pipe_idx];
            out_valid[pipe_idx] = 0;
            #(tOH);
            if (!v) dq_drive = 0;
            #(tAC - tOH);
            if (v) begin
                dq_drive = 1;
                dq_val = {m[3] ? 8'hzz : d[31:24], m[2] ? 8'hzz : d[23:16], m[1] ? 8'hzz : d[15:8], m[0] ? 8'hzz : d[7:0]};
            end
        end
    join_none

`ifdef DBG
    if (CSn === 1'b0 && cmd != CMD_NOP && $realtime > 150000) $display("%0t %s sees cmd=%b BA=%0d A=%h", $realtime, NAME, cmd, BA, A);
    if (CSn !== 1'b0 && CSn !== 1'b1) $display("%0t %s CSn=%b", $realtime, NAME, CSn);
`endif
    if (CSn === 1'b0) begin
        if ($realtime - cmd_last_change < tCMS) err("command/address setup violation");
        if ($realtime < refresh_busy_until && cmd != CMD_NOP) err("command during tRFC");
        if ($realtime < mode_busy_until && cmd != CMD_NOP) err("command during tMRD");

        case (cmd)
            CMD_ACT : begin
                if (bank_open[BA]) err("ACTIVATE to open bank");
                if ($realtime < bank_ready[BA]) begin
                    $display("   bank %0d ready at %0.2f, now %0.2f", BA, bank_ready[BA], $realtime);
                    err("ACTIVATE before tRP complete");
                end
                if ($realtime - bank_act_time[BA] < tRC) err("tRC violation");
                bank_open[BA] = 1; bank_row[BA] = A; bank_act_time[BA] = $realtime; bank_ap[BA] = 0;
            end

            CMD_RD, CMD_WR : begin
                if (!configured) err("column command before mode register set");
                if (!bank_open[BA]) err("READ/WRITE to closed bank");
                if (bank_ap[BA]) err("READ/WRITE to bank with auto precharge pending");
                if ($realtime - bank_act_time[BA] < tRCD - 0.01) err("tRCD violation");
                if (cmd == CMD_RD) begin
                    out_valid[(clk_cnt + cas_latency) % 8] = 1;
                    out_data [(clk_cnt + cas_latency) % 8] = mem[hash(BA, bank_row[BA], A[8:0])];
                    out_mask [(clk_cnt + cas_latency) % 8] = DQM; // DQM read latency is 2 = CL, so sample now
                    if (dq_drive == 0 && 0) ;
                    if (A[10]) begin
                        // Precharge begins after the last data beat is launched.
                        ap_start = $realtime + cas_latency * tCK;
                        if (ap_start < bank_act_time[BA] + tRAS) ap_start = bank_act_time[BA] + tRAS;
                        bank_ready[BA] = ap_start + tRP;
                        bank_open[BA] = 0; bank_ap[BA] = 1;
                    end
                end else begin
                    // WRITE: capture data now, check setup and hold
                    if ($realtime - dq_last_change < tDS) err("write data setup violation");
                    if (dq_drive) err("WRITE while SDRAM is driving DQ");
                    wdata = mem[hash(BA, bank_row[BA], A[8:0])];
                    if (!DQM[3]) wdata[31:24] = DQ[31:24];
                    if (!DQM[2]) wdata[23:16] = DQ[23:16];
                    if (!DQM[1]) wdata[15:8]  = DQ[15:8];
                    if (!DQM[0]) wdata[7:0]   = DQ[7:0];
                    if ((!DQM[3] && ^DQ[31:24] === 1'bx) || (!DQM[2] && ^DQ[23:16] === 1'bx) ||
                        (!DQM[1] && ^DQ[15:8] === 1'bx) || (!DQM[0] && ^DQ[7:0] === 1'bx)) err("write data contains X");
                    mem[hash(BA, bank_row[BA], A[8:0])] = wdata;
                    fork
                        begin : holdchk
                            reg [31:0] snap; snap = DQ;
                            #(tDH);
                            if (DQ !== snap) err("write data hold violation");
                        end
                    join_none
                    if (A[10]) begin
                        ap_start = $realtime + tWR * tCK;
                        if (ap_start < bank_act_time[BA] + tRAS) ap_start = bank_act_time[BA] + tRAS;
                        bank_ready[BA] = ap_start + tRP;
                        bank_open[BA] = 0; bank_ap[BA] = 1;
                    end
                end
            end

            CMD_PRE : begin
                for (k = 0; k < 4; k = k + 1) begin
                    if (A[10] || BA == k) begin
                        if (bank_open[k] && $realtime - bank_act_time[k] < tRAS) err("PRECHARGE before tRAS");
                        if (bank_open[k]) bank_ready[k] = $realtime + tRP;
                        bank_open[k] = 0; bank_ap[k] = 0;
                    end
                end
            end

            CMD_REF : begin
                for (k = 0; k < 4; k = k + 1) begin
                    if (bank_open[k]) err("AUTO REFRESH with open bank");
                    if ($realtime < bank_ready[k]) err("AUTO REFRESH before precharge complete");
                end
                refresh_busy_until = $realtime + tRFC;
            end

            CMD_LMR : begin
                for (k = 0; k < 4; k = k + 1) if (bank_open[k] || $realtime < bank_ready[k]) err("LOAD MODE with active bank");
                if (BA !== 2'b00) err("LOAD MODE with non zero bank address (reserved)");
                cas_latency = A[6:4];
                burst_len   = (A[2:0] == 0) ? 1 : (1 << A[2:0]);
                if (A[3]) err("interleaved burst not modelled");
                if (burst_len != 1) err("burst length other than 1 not modelled");
                if (cas_latency != 2) err("CAS latency other than 2 not modelled");
                configured = 1;
                mode_busy_until = $realtime + tMRD * tCK;
            end

            CMD_BST : err("BURST TERMINATE not expected");
            CMD_NOP : ;
            default : err("illegal command");
        endcase
    end
end

// A row may not stay open longer than tRAS max.
reg tras_max_flagged [0:3];
initial for (i = 0; i < 4; i = i + 1) tras_max_flagged[i] = 0;
always @(posedge CLK) begin
    for (k = 0; k < 4; k = k + 1) begin
        if (bank_open[k] && !tras_max_flagged[k] && $realtime - bank_act_time[k] > tRAS_MAX) begin
            tras_max_flagged[k] = 1;
            err("row open longer than tRAS max");
        end
        if (!bank_open[k]) tras_max_flagged[k] = 0;
    end
end

// Backdoor access for the testbench
task poke(input [1:0] b, input [12:0] row, input [8:0] col, input [31:0] d);
    mem[hash(b, row, col)] = d;
endtask
function [31:0] peek(input [1:0] b, input [12:0] row, input [8:0] col);
    peek = mem[hash(b, row, col)];
endfunction

endmodule
