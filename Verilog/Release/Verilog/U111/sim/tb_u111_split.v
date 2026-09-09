`timescale 1ns/1ps
//------------------------------------------------------------------------------
// U111 bus sizing testbench: long word reads from a 16 bit off-board port.
//
// The mainboard answers every _TS with a one clock _TACK pulse launched from
// the rising edge (U409, U712) or the falling edge (U110, ATA) of its copy of
// the bus clock, TCO_MB after that edge plus TRACE to reach U111. The CPU model
// starts its cycles back to back and recognizes _TA only when it is low from
// CPU_TA_SU before to CPU_TA_HOLD after a clock edge (MC68040 specs 22a/23 at
// 40MHz: 8ns and 2ns), sampling from the end of C2 on. A long word read must
// produce its first recognized _TA after the second half has been acknowledged,
// and the assembled data must hold through the CPU's data setup and hold
// window. The second half of the run puts an on-board (U400) read in front of
// every off-board read, since the on-board acknowledge travels over _TACK as
// well.
//
// Run: iverilog -g2012 -o tb tb_u111_split.v ../U111_CYCLE_SM.v && vvp tb
// Sweep the acknowledge timing with ./run_sweep.sh.
//------------------------------------------------------------------------------
module tb_u111_split;

parameter real T40      = 25.0;
parameter real CPU_TCO  = 15.0;   // BCLK to _TS/address valid at the CPU
parameter real U111_IN  = 2.0;    // trace CPU to U111
parameter real TCO_MB   = 6.0;    // mainboard FPGA clock to _TACK
parameter real TRACE    = 2.0;    // mainboard to U111
parameter real TA_PATH  = 8.0;    // U111 pad to pad on the way to the CPU
parameter integer RESP  = 3;      // bus clocks from _TS to the acknowledge launch edge
parameter integer NEGEDGE = 0;    // 1: launch _TACK from the falling edge like U110
parameter real PULSE    = 0.0;    // extra width of the acknowledge pulse (rise slower than fall)
parameter real U400_TCO = 7.0;    // bus clock to _TA from the on-board RAM controller
parameter real LBEN_DELAY = 30.0; // CPU clock edge to LBENn valid at U111 (address, level shifter, decode)
parameter integer TA_PULLUP = 0;  // 1: pull-up on the card's _TA net (Rev 6.0 has none)

reg CLK40 = 0;
always #(T40/2) CLK40 = ~CLK40;
reg RESETn = 0;

// ---------------------------------------------------------------- DUT wiring
reg  TS_CPU_raw = 1;
wire TSn_CPU;
assign #(U111_IN) TSn_CPU = TS_CPU_raw;
wire TSn, TACKn, TSn_RAM, TBI_CPUn, TCI_CPUn, TEA_CPUn, A_AMIGA;
wire TAn;
pullup (TSn); pullup (TACKn);     // the mainboard has 2k7 pull-ups on these
// The card's _TA net has no pull-up (Rev 6.0): when nobody drives it, the
// trace capacitance keeps the last level. Modelled as a weak keeper that
// follows whatever was driven last; a pull-up (pull strength) beats it.
reg ta_keep = 1;
always @(TAn) if (TAn === 1'b0 || TAn === 1'b1) ta_keep = TAn;
assign (weak1, weak0) TAn = ta_keep;
generate if (TA_PULLUP) begin : ta_pu
    pullup (TAn);
end endgenerate
reg  portsize = 1;                // 1: 16 bit port (chipset registers), 0: 32 bit port (chip RAM)
reg  RnW = 1;
reg  [1:0] SIZ = 2'b00;
reg  A_040 = 0;
wire [7:0] D_UU_040, D_UM_040, D_LM_040, D_LL_040;
wire [7:0] D_UU_AMIGA, D_UM_AMIGA, D_LM_AMIGA, D_LL_AMIGA;

// Mainboard drives the Amiga side during reads: the requested word on the
// upper lanes for a 16 bit port, the whole long word for a 32 bit port.
reg mb_drive = 0;
reg [15:0] mb_word = 16'h0000;
assign D_UU_AMIGA = mb_drive ? mb_word[15:8] : 8'hzz;
assign D_UM_AMIGA = mb_drive ? mb_word[7:0]  : 8'hzz;
assign D_LM_AMIGA = mb_drive && !portsize ? 8'hBE : 8'hzz;
assign D_LL_AMIGA = mb_drive && !portsize ? 8'hEF : 8'hzz;

// Mainboard acknowledge driver.
reg tack_drv = 0, tack_val = 1;
assign TACKn = tack_drv ? tack_val : 1'bz;

// Address decode: LBENn low while the CPU addresses on-board RAM, whose
// controller (U400) answers with a one clock _TA pulse of its own.
reg lben_n = 1;
reg ta_u400_drv = 0, ta_u400_val = 1;
assign TAn = ta_u400_drv ? ta_u400_val : 1'bz;

U111_CYCLE_SM dut (
    .CLK40(CLK40), .RESETn(RESETn), .RnW(RnW), .PORTSIZE(portsize), .BGn(1'b1), .LBENn(lben_n),
    .TBIn(1'b1), .TCIn(1'b1), .CPU_BUS(1'b1), .TSn_CPU(TSn_CPU), .SIZ(SIZ), .A_040(A_040),
    .TSn_RAM(TSn_RAM), .TBI_CPUn(TBI_CPUn), .TCI_CPUn(TCI_CPUn), .TEA_CPUn(TEA_CPUn), .A_AMIGA(A_AMIGA),
    .TSn(TSn), .TAn(TAn), .TACKn(TACKn),
    .D_UU_040(D_UU_040), .D_UM_040(D_UM_040), .D_LM_040(D_LM_040), .D_LL_040(D_LL_040),
    .D_UU_AMIGA(D_UU_AMIGA), .D_UM_AMIGA(D_UM_AMIGA), .D_LM_AMIGA(D_LM_AMIGA), .D_LL_AMIGA(D_LL_AMIGA),
    .CACHE_EN(1'b1));

// What the CPU sees: U111 outputs reach it after the FPGA's clock-to-pad
// (enables) or pad-to-pad (pass through) delay.
parameter real U111_TCO = 6.0;    // buffer enable register to pad
parameter real CPU_TA_SU = 8.0;   // _TA setup the CPU model demands (spec 22a: 8ns)
parameter real CPU_TA_HOLD = 2.0; // and hold (spec 23: 2ns)
parameter real CPU_D_SU = 3.0;    // data setup (spec 15: 3ns)
parameter real CPU_D_HOLD = 3.0;  // data hold (spec 16: 3ns)
wire TA_CPU;
assign #(TA_PATH) TA_CPU = TAn;
wire [31:0] D_CPU;
assign #(U111_TCO) D_CPU = {D_UU_040, D_UM_040, D_LM_040, D_LL_040};

// ---------------------------------------------------------------- monitors
integer errors = 0;
task err(input [8*96-1:0] msg);
    begin errors = errors + 1; $display("%0t TB ERROR: %0s", $realtime, msg); end
endtask

// Mainboard: respond to each _TS on the bus with one acknowledge pulse,
// driven low from the launch edge, driven high one clock later and released
// after another clock, the way U110 does it.
integer halves_acked = 0;
always @(negedge TSn) if (lben_n) begin
    fork begin : respond
        reg [15:0] w;
        w = (A_AMIGA && portsize) ? 16'hBEEF : 16'hCAFE;  // A1 selects the word on a 16 bit port
        @(posedge CLK40);                        // the edge that samples _TS
        repeat (RESP - 1) @(posedge CLK40);
        if (NEGEDGE) @(negedge CLK40);
        #(TCO_MB + TRACE);
        mb_drive = 1; mb_word = w;
        tack_val = 0; tack_drv = 1;               // _TACK asserted
        halves_acked = halves_acked + 1;
        #(T40 + PULSE) tack_val = 1;              // driven high one clock later
        #(T40 - PULSE) tack_drv = 0; mb_drive = 0; // released
    end join_none
end

// Shifted samplers: value of _TA and data CPU_x_SU before every clock edge.
reg ta_pre = 1;
reg [31:0] d_pre;
always begin @(posedge CLK40); #(T40 - CPU_TA_SU) ta_pre = TA_CPU; end
always begin @(posedge CLK40); #(T40 - CPU_D_SU) d_pre = D_CPU; end
real ta_fall = -1000;
always @(negedge TA_CPU) ta_fall = $realtime;
real min_ta_setup = 1000;

// ---------------------------------------------------------------- CPU model
// One long word read from the 16 bit port, started right at a clock edge
// (back to back with the previous cycle: since_edge says how far past that
// edge we already are). _TA is sampled from the end of C2 on; it counts when
// low CPU_TA_SU before and CPU_TA_HOLD after the edge.
real since_edge = 0;
task cpu_read(output integer clocks);
    integer k; reg done; reg [31:0] d_hold; real edge_t;
    begin
        halves_acked = 0;
        #(CPU_TCO - since_edge) begin TS_CPU_raw = 0; lben_n = 1; end  // C1
        @(posedge CLK40); #(CPU_TCO) TS_CPU_raw = 1;  // C2 begins
        done = 0; k = 1;
        while (!done) begin
            @(posedge CLK40);                         // end of C2, C3, ...
            edge_t = $realtime;
            k = k + 1;
            #(CPU_TA_HOLD);
            since_edge = CPU_TA_HOLD;
            if (ta_pre === 1'b0 && TA_CPU === 1'b0) begin
                done = 1;
                if (edge_t - ta_fall < min_ta_setup) min_ta_setup = edge_t - ta_fall;
                if (halves_acked < (portsize ? 2 : 1)) err("_TA recognized before the mainboard acknowledged");
                #(CPU_D_HOLD - CPU_TA_HOLD) d_hold = D_CPU;
                since_edge = CPU_D_HOLD;
                if (d_pre !== 32'hCAFEBEEF || d_hold !== 32'hCAFEBEEF) begin
                    $display("   data at setup %08h, at hold %08h", d_pre, d_hold);
                    err("long word data not valid through the CPU's setup/hold window");
                end
            end else if (k > 40) begin
                done = 1; err("no _TA within 40 clocks");
            end
        end
        clocks = k;
    end
endtask

// An on-board long word read right after an off-board cycle. The CPU puts
// the new address out CPU_TCO after the recognition edge; U111 sees LBENn
// fall LBEN_DELAY after that edge (address buffers and its own decode). The
// RAM controller samples _TS at the end of C1 and drives _TA high from the
// odd 80MHz edge after that, then pulls it low for one clock at the end of
// its access. The CPU samples _TA at the end of C2: it must not see it low.
integer false_ta = 0;
task onboard_read;
    real edge_t;
    begin
        fork
            begin #(LBEN_DELAY - since_edge) lben_n = 0; end
            begin #(CPU_TCO - since_edge) TS_CPU_raw = 0; end
        join
        @(posedge CLK40);                                   // end of C1: U400 samples _TS
        edge_t = $realtime;
        #(CPU_TCO) TS_CPU_raw = 1;
        #(T40/2 + U400_TCO - CPU_TCO) begin ta_u400_drv = 1; ta_u400_val = 1; end
        @(posedge CLK40);                                   // end of C2
        #(CPU_TA_HOLD);
        if (ta_pre === 1'b0 && TA_CPU === 1'b0) begin
            false_ta = false_ta + 1;
            err("false _TA on the on-board cycle right after an off-board acknowledge");
        end
        repeat (3) @(posedge CLK40);                        // U400 access time
        #(U400_TCO) ta_u400_val = 0;                        // one clock _TA
        #(T40 - U400_TCO);                                  // recognition edge
        since_edge = 0;
        fork begin
            #(U400_TCO) ta_u400_val = 1;
            #(T40) ta_u400_drv = 0;
        end join_none
    end
endtask

// ---------------------------------------------------------------- stimulus
integer n, clk;
initial begin
    $display("=== U111 bench: NEGEDGE=%0d RESP=%0d TCO_MB=%0.1f TRACE=%0.1f PULSE=%0.1f U111_TCO=%0.1f TA_PATH=%0.1f LBEN_DELAY=%0.1f TA_PULLUP=%0d ===", NEGEDGE, RESP, TCO_MB, TRACE, PULSE, U111_TCO, TA_PATH, LBEN_DELAY, TA_PULLUP);
    repeat (4) @(posedge CLK40);
    RESETn = 1;
    repeat (4) @(posedge CLK40);
    A_040 = 0;
    @(posedge CLK40);
    // 1. Long word reads from a 16 bit port, back to back.
    portsize = 1;
    for (n = 0; n < 40; n = n + 1) begin
        cpu_read(clk);
        if (n == 0) $display("long word read from a 16 bit port: %0d clocks", clk);
    end
    // 2. The same with an on-board read in front of every one: the on-board
    // acknowledge travels over _TACK too and must not leak into the next cycle.
    for (n = 0; n < 40; n = n + 1) begin
        onboard_read;
        cpu_read(clk);
    end
    // 3. Long word reads from a 32 bit port (chip RAM), each followed by an
    // on-board read: the mainboard's acknowledge must be off _TA before U111
    // lets go of the line for the on-board cycle.
    portsize = 0;
    for (n = 0; n < 40; n = n + 1) begin
        cpu_read(clk);
        if (n == 0) $display("long word read from a 32 bit port: %0d clocks", clk);
        onboard_read;
    end
    $display("false acknowledges on on-board cycles: %0d", false_ta);
    $display("min _TA setup seen at the CPU: %0.1fns (needs %0.1f)", min_ta_setup, CPU_TA_SU);
    $display("=== %0d errors ===", errors);
    if (errors == 0) $display("PASS"); else $display("FAIL");
    $finish;
end

endmodule
