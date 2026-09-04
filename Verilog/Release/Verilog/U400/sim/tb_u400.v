`timescale 1ns/1ps
//------------------------------------------------------------------------------
// Testbench for the U400 SDRAM controller.
//
// Models: the CLK80/CLK40 PLL relationship (with adjustable skew), the U111
// _TS pass through delay, an MC68040 bus master (long word, byte, word and line
// transfers with the 40MHz output delays from the MC68040 user's manual), an
// alternate bus master with _MI snooping, and two ISSI IS42S32160F SDRAMs.
//
// Run:  iverilog -g2012 -o tb_u400 -I.. tb_u400.v sdram_model.v ../U400_TOP.v \
//          ../U400_ADDRESS_DECODE.v ../U400_SDRAM_CONTROLLER.v && vvp tb_u400
//------------------------------------------------------------------------------
module tb_u400;

// ---------------------------------------------------------------- parameters
parameter real T80        = 12.5;
parameter real CLK40_SKEW = 0.7;   // CLK40 edge relative to CLK80 edge at U400 (+ = later)
parameter real RAMCLK_SKEW= 0.0;   // SDRAM clock relative to U400 CLK80
parameter real BCLK_SKEW  = 0.0;   // CPU clock relative to U400 CLK40
parameter real CPU_TCO    = 20.0;  // BCLK to output valid (max 25 at 40MHz)
parameter real CPU_TDATA  = 27.0;  // BCLK to data out valid (max 27 at 40MHz)
parameter real CPU_THOLD  = 6.5;   // output hold (min 6.5)
parameter real CPU_TSU    = 3.0;   // data-in setup required (MC68040 40MHz spec 15)
parameter real CPU_TH     = 3.0;   // data-in hold required (spec 16)
parameter real U111_DELAY = 6.0;   // _TS pass through delay in U111
parameter real FPGA_TCO   = 5.0;   // U400 clock to output delay (pad)
parameter integer RAND_CYCLES = 1500;
parameter integer FAST_READ = 1;

// ---------------------------------------------------------------- clocks
// All clocks are delayed copies of CLK80_SRC so that skews of either sign are positive delays.
parameter real BASE_DELAY = 2.5;  // keep BASE_DELAY + skew below half a CLK80 period (inertial delay)
reg CLK80_SRC = 0;
always #(T80/2) CLK80_SRC = ~CLK80_SRC;

reg CLK40_RAW = 0;
always @(posedge CLK80_SRC) CLK40_RAW <= ~CLK40_RAW;

wire CLK80, CLK40, RAMCLK, BCLK;
assign #(BASE_DELAY)                          CLK80  = CLK80_SRC;    // at U400
assign #(BASE_DELAY + CLK40_SKEW)             CLK40  = CLK40_RAW;    // at U400
assign #(BASE_DELAY + RAMCLK_SKEW)            RAMCLK = CLK80_SRC;    // at the SDRAM
assign #(BASE_DELAY + CLK40_SKEW + BCLK_SKEW) BCLK   = CLK40_RAW;    // at the CPU

// ---------------------------------------------------------------- bus
reg         RESETn = 0;
reg         TS_CPU = 1;       // _TS driven by the bus master
wire        TSn_RAM;
assign #(U111_DELAY) TSn_RAM = TS_CPU;
reg  [31:0] ADDR = 0;
reg  [1:0]  SIZ = 0;
reg         RnW = 1;
reg         MIn = 1;
wire        TAn;              // _TA at the CPU
wire        TA_DUT;           // _TA at the U400 pad
pullup (TAn);
pullup (TA_DUT);
assign #(FPGA_TCO) TAn = TA_DUT;
reg         TA_CPU_DRV = 0;   // the CPU driving _TA as a snoop slave
assign TA_DUT = TA_CPU_DRV ? 1'b0 : 1'bz;
wire [31:0] DQ;
reg  [31:0] DQ_OUT = 32'hz;
assign DQ = DQ_OUT;

// ---------------------------------------------------------------- SDRAM pins
wire UUBEn, UMBEn, LMBEn, LLBEn, CS0n, CS1n, CLK_EN, RASn, CASn, WEn, LBENn, BANK0, BANK1, TP;
wire [12:0] MA;
// Signals as seen by the SDRAM after the FPGA output delay
wire UUBEn_d, UMBEn_d, LMBEn_d, LLBEn_d, CS0n_d, CS1n_d, RASn_d, CASn_d, WEn_d, BANK0_d, BANK1_d;
wire [12:0] MA_d;
assign #(FPGA_TCO) {UUBEn_d, UMBEn_d, LMBEn_d, LLBEn_d, CS0n_d, CS1n_d, RASn_d, CASn_d, WEn_d, BANK0_d, BANK1_d, MA_d} =
                   {UUBEn, UMBEn, LMBEn, LLBEn, CS0n, CS1n, RASn, CASn, WEn, BANK0, BANK1, MA};

U400_TOP #(.FAST_READ(FAST_READ)) dut (
    .CLK80(CLK80), .CLK40(CLK40), .RESETn(RESETn),
    .TSn(TSn_RAM), .RnW(RnW), .MIn(MIn), .A(ADDR), .SIZ(SIZ),
    .TAn(TA_DUT),
    .UUBEn(UUBEn), .UMBEn(UMBEn), .LMBEn(LMBEn), .LLBEn(LLBEn),
    .CS0n(CS0n), .CS1n(CS1n), .CLK_EN(CLK_EN), .RASn(RASn), .CASn(CASn), .WEn(WEn),
    .LBENn(LBENn), .BANK0(BANK0), .BANK1(BANK1), .MA(MA), .TP(TP)
);

sdram_model #(.NAME("SDRAM0")) ram0 (
    .CLK(RAMCLK), .CKE(CLK_EN), .CSn(CS0n_d), .RASn(RASn_d), .CASn(CASn_d), .WEn(WEn_d),
    .BA({BANK1_d, BANK0_d}), .A(MA_d), .DQM({UUBEn_d, UMBEn_d, LMBEn_d, LLBEn_d}), .DQ(DQ)
);
sdram_model #(.NAME("SDRAM1")) ram1 (
    .CLK(RAMCLK), .CKE(CLK_EN), .CSn(CS1n_d), .RASn(RASn_d), .CASn(CASn_d), .WEn(WEn_d),
    .BA({BANK1_d, BANK0_d}), .A(MA_d), .DQM({UUBEn_d, UMBEn_d, LMBEn_d, LLBEn_d}), .DQ(DQ)
);

// ---------------------------------------------------------------- monitors
integer errors = 0;
integer cycles = 0;
task err(input [8*100-1:0] msg);
    begin
        errors = errors + 1;
        $display("%0t TB ERROR: %0s", $realtime, msg);
    end
endtask

// _TA setup check: TA must be stable for CPU_TSU before a BCLK edge on which it is sampled.
real ta_last_change = -1000;
always @(TAn) ta_last_change = $realtime;

// Data setup snapshot CPU_TSU before every BCLK rising edge
reg [31:0] dq_setup_snap;
always @(posedge BCLK) begin
    #(2*T80 - CPU_TSU) dq_setup_snap = DQ;
end

// Any SDRAM activity while _MI is asserted and the CPU did not start the cycle is an error.
reg mi_guard = 0;
always @(posedge RAMCLK) begin
    if (mi_guard && (CS0n_d === 1'b0 || CS1n_d === 1'b0) && {RASn_d, CASn_d, WEn_d} != 3'b111 && {RASn_d, CASn_d, WEn_d} != 3'b001)
        err("SDRAM command issued while _MI asserted");
    if (mi_guard && TP) err("U400 drives _TA while _MI asserted");
end

// ---------------------------------------------------------------- 68040 bus master model
// Address helpers for the SDRAM backdoor: A[26] chip, A[25:24] bank, A[23:11] row, A[10:2] column.
function [31:0] ram_peek(input [31:0] a);
    ram_peek = a[26] ? ram1.peek(a[25:24], a[23:11], a[10:2]) : ram0.peek(a[25:24], a[23:11], a[10:2]);
endfunction
task ram_poke(input [31:0] a, input [31:0] d);
    if (a[26]) ram1.poke(a[25:24], a[23:11], a[10:2], d); else ram0.poke(a[25:24], a[23:11], a[10:2], d);
endtask

// Start a bus cycle right after a BCLK rising edge.
task start_cycle(input [31:0] a, input [1:0] s, input rw, input [31:0] wdata);
    begin
        @(posedge BCLK);
        if (!rw) begin
            fork
                begin #(CPU_TDATA) DQ_OUT = wdata; end
            join_none
        end
        #(CPU_TCO);
        ADDR = a; SIZ = s; RnW = rw; TS_CPU = 0;
        @(posedge BCLK);
        #(CPU_TCO) TS_CPU = 1;
    end
endtask

// Wait for _TA at a BCLK rising edge. Returns the number of clocks waited.
task wait_ta(output integer clocks);
    integer n;
    begin
        n = 0;
        forever begin
            @(posedge BCLK);
            n = n + 1;
            if (TAn === 1'b0) begin
                if ($realtime - ta_last_change < 8.0) err("_TA setup violation at CPU");
                clocks = n;
                disable wait_ta;
            end
            if (n > 16000) begin
                err("timeout waiting for _TA");
                clocks = n;
                disable wait_ta;
            end
        end
    end
endtask

// Check read data at the sampling edge: value CPU_TSU before, and CPU_TH after must both equal expected.
task check_read_data(input [31:0] expected, input [3:0] lanes);
    reg [31:0] v_su, v_h;
    integer b;
    begin
        v_su = dq_setup_snap;
        #(CPU_TH) v_h = DQ;
        for (b = 0; b < 4; b = b + 1) begin
            if (lanes[b]) begin
                if (v_su[b*8 +: 8] !== expected[b*8 +: 8]) begin
                    $display("   lane %0d setup value %h expected %h", b, v_su[b*8 +: 8], expected[b*8 +: 8]);
                    err("read data wrong / not valid at setup time");
                end
                if (v_h[b*8 +: 8] !== expected[b*8 +: 8]) begin
                    $display("   lane %0d hold value %h expected %h", b, v_h[b*8 +: 8], expected[b*8 +: 8]);
                    err("read data wrong / not held at hold time");
                end
            end
        end
    end
endtask

// After a write beat is acknowledged, the CPU changes the data bus: hold for CPU_THOLD then invalid, then next value.
task next_write_data(input [31:0] d, input last);
    begin
        #(CPU_THOLD) DQ_OUT = last ? 32'hz : 32'hxxxxxxxx;
        if (!last) #(CPU_TDATA - CPU_THOLD) DQ_OUT = d;
    end
endtask

integer ta_clocks;

// Long word / word / byte read
task cpu_read(input [31:0] a, input [1:0] s, input [31:0] expected, input [3:0] lanes);
    begin
        cycles = cycles + 1;
        start_cycle(a, s, 1, 0);
        wait_ta(ta_clocks);
        check_read_data(expected, lanes);
    end
endtask

task cpu_write(input [31:0] a, input [1:0] s, input [31:0] d);
    begin
        cycles = cycles + 1;
        start_cycle(a, s, 0, d);
        wait_ta(ta_clocks);
        next_write_data(0, 1);
    end
endtask

// Line read: four long words, wrap within the 16 byte line starting at a[3:2].
task cpu_line_read(input [31:0] a);
    integer k; reg [31:0] wa; integer n;
    begin
        cycles = cycles + 1;
        start_cycle(a, 2'b11, 1, 0);
        for (k = 0; k < 4; k = k + 1) begin
            wa = {a[31:4], a[3:2] + k[1:0], 2'b00};
            if (k == 0) wait_ta(ta_clocks);
            else if (FAST_READ) begin
                @(posedge BCLK);
                if (TAn !== 1'b0) err("line read: _TA not asserted on consecutive clock");
                if ($realtime - ta_last_change < 8.0 && TAn === 1'b0) err("_TA setup violation at CPU");
            end else begin
                wait_ta(n);
                if (n != 2) err("line read: expected _TA every second clock");
            end
            check_read_data(ram_peek(wa), 4'hf);
        end
        @(posedge BCLK);
        if (TAn === 1'b0) err("line read: _TA asserted after fourth beat");
    end
endtask

// Line write: four long words. The CPU drives beat k+1 after _TA for beat k.
task cpu_line_write(input [31:0] a, input [31:0] d0, d1, d2, d3);
    integer k, n; reg [31:0] wa; reg [31:0] dv [0:3];
    begin
        cycles = cycles + 1;
        dv[0] = d0; dv[1] = d1; dv[2] = d2; dv[3] = d3;
        start_cycle(a, 2'b11, 0, d0);
        for (k = 0; k < 4; k = k + 1) begin
            if (k == 0) wait_ta(ta_clocks); else wait_ta(n);
            if (k < 3) next_write_data(dv[k+1], 0); else next_write_data(0, 1);
        end
        @(posedge BCLK);
        if (TAn === 1'b0) err("line write: _TA asserted after fourth beat");
        for (k = 0; k < 4; k = k + 1) begin
            wa = {a[31:4], a[3:2] + k[1:0], 2'b00};
            if (ram_peek(wa) !== dv[k]) begin
                $display("   beat %0d addr %h got %h expected %h", k, wa, ram_peek(wa), dv[k]);
                err("line write data mismatch in SDRAM");
            end
        end
    end
endtask

// Alternate bus master cycle with _MI handling.
// mode 0: snoop inhibited, _MI negated one clock after _TS.
// mode 1: snoop lookup, _MI negated three clocks after _TS, memory responds.
// mode 2: snoop hit, CPU asserts _TA itself with _MI kept asserted, memory must stay quiet.
task dma_cycle(input [31:0] a, input rw, input [31:0] d, input integer mode, input [31:0] expected);
    integer n;
    begin
        cycles = cycles + 1;
        @(posedge BCLK); @(posedge BCLK);
        MIn = 0; mi_guard = 1;
        @(posedge BCLK); @(posedge BCLK);
        start_cycle(a, 2'b00, rw, d);
        // start_cycle returns CPU_TCO after the edge ending C1
        case (mode)
            0 : begin @(posedge BCLK); #(CPU_TCO) mi_guard = 0; MIn = 1; end
            1 : begin @(posedge BCLK); @(posedge BCLK); @(posedge BCLK); #(CPU_TCO) mi_guard = 0; MIn = 1; end
            2 : begin
                    @(posedge BCLK); @(posedge BCLK); @(posedge BCLK); #(CPU_TCO) TA_CPU_DRV = 1;
                    @(posedge BCLK); #(CPU_TCO) TA_CPU_DRV = 0;
                end
        endcase
        if (mode != 2) begin
            wait_ta(ta_clocks);
            if (rw) check_read_data(expected, 4'hf); else next_write_data(0, 1);
        end else begin
            if (!rw) next_write_data(0, 1);
            repeat (6) @(posedge BCLK);
            if (TP) err("U400 became active after a snoop hit");
        end
        // Bus returns to the CPU: _MI negated.
        @(posedge BCLK); #(CPU_TCO) MIn = 1; mi_guard = 0;
        @(posedge BCLK);
    end
endtask

// ---------------------------------------------------------------- stimulus
integer k, n, r;
reg [31:0] a, d;
reg [31:0] shadow [0:4095];   // shadow of a small region for random tests
reg [11:0] idx;

initial begin
    $display("=== U400 SDRAM controller testbench ===");
    $display("CLK40_SKEW=%0.2f RAMCLK_SKEW=%0.2f BCLK_SKEW=%0.2f CPU_TCO=%0.1f CPU_TDATA=%0.1f U111_DELAY=%0.1f FPGA_TCO=%0.1f",
             CLK40_SKEW, RAMCLK_SKEW, BCLK_SKEW, CPU_TCO, CPU_TDATA, U111_DELAY, FPGA_TCO);
    repeat (5) @(posedge CLK40);
    RESETn = 1;

    // ---- a cycle requested during power up must be served after configuration ----
    ram_poke(32'h0800_0000, 32'hCAFE_0001);
    #1000;
    cpu_read(32'h0800_0000, 2'b00, 32'hCAFE_0001, 4'hf);
    $display("%0t read during power-up served after %0d clocks", $realtime, ta_clocks);

    // ---- single reads: long word, byte lanes, word ----
    ram_poke(32'h0800_1000, 32'h1122_3344);
    cpu_read(32'h0800_1000, 2'b00, 32'h1122_3344, 4'hf);
    $display("long word read: _TA sampled %0d clocks after _TS (expect 5, or 6 when _TS arrives late)", ta_clocks + 1);
    if (ta_clocks != 4 + !FAST_READ && ta_clocks != 5 + !FAST_READ) err("long word read latency");
    cpu_read(32'h0800_1001, 2'b01, 32'h1122_3344, 4'b0100);
    cpu_read(32'h0800_1002, 2'b10, 32'h1122_3344, 4'b0011);
    cpu_read(32'h0800_1003, 2'b01, 32'h1122_3344, 4'b0001);

    // ---- single writes ----
    cpu_write(32'h0800_2000, 2'b00, 32'hA5A5_5A5A);
    $display("long word write: _TA sampled %0d clocks after _TS (expect 4, or 5 when _TS arrives late)", ta_clocks + 1);
    if (ta_clocks != 3 && ta_clocks != 4) err("long word write latency");
    if (ram_peek(32'h0800_2000) !== 32'hA5A5_5A5A) err("long word write data");
    cpu_write(32'h0800_2001, 2'b01, 32'h0077_0000);       // byte 1 lane UM (D23-D16)
    if (ram_peek(32'h0800_2000) !== 32'hA577_5A5A) err("byte write data");
    cpu_write(32'h0800_2002, 2'b10, 32'h0000_BEEF);       // low word
    if (ram_peek(32'h0800_2000) !== 32'hA577_BEEF) err("word write data");
    cpu_read(32'h0800_2000, 2'b00, 32'hA577_BEEF, 4'hf);

    // ---- second chip / other banks ----
    cpu_write(32'h0C12_3450, 2'b00, 32'h0C0C_0C0C);
    cpu_read (32'h0C12_3450, 2'b00, 32'h0C0C_0C0C, 4'hf);
    cpu_write(32'h0B00_0010, 2'b00, 32'h0B0B_0B0B);
    cpu_read (32'h0B00_0010, 2'b00, 32'h0B0B_0B0B, 4'hf);

    // ---- line reads from each starting long word ----
    ram_poke(32'h0800_3000, 32'h0000_0000); ram_poke(32'h0800_3004, 32'h1111_1111);
    ram_poke(32'h0800_3008, 32'h2222_2222); ram_poke(32'h0800_300C, 32'h3333_3333);
    cpu_line_read(32'h0800_3000);
    $display("line read: first _TA sampled %0d clocks after _TS, four beats", ta_clocks + 1);
    if (ta_clocks != 4 + !FAST_READ && ta_clocks != 5 + !FAST_READ) err("line read latency");
    cpu_line_read(32'h0800_3004);
    cpu_line_read(32'h0800_3008);
    cpu_line_read(32'h0800_300C);
    cpu_line_read(32'h0800_3001);   // A[1:0] copied from the operand address

    // ---- line writes ----
    cpu_line_write(32'h0800_4000, 32'h4000_0000, 32'h4000_0001, 32'h4000_0002, 32'h4000_0003);
    $display("line write: first _TA sampled %0d clocks after _TS", ta_clocks + 1);
    cpu_line_write(32'h0800_4018, 32'h4018_0000, 32'h4018_0001, 32'h4018_0002, 32'h4018_0003);
    cpu_line_read(32'h0800_4000);
    cpu_line_read(32'h0800_4010);

    // ---- back to back mix ----
    for (k = 0; k < 8; k = k + 1) begin
        cpu_line_write(32'h0800_5000 + k*16, k, k+1, k+2, k+3);
        cpu_line_read(32'h0800_5000 + k*16);
        cpu_write(32'h0800_6000 + k*4, 2'b00, ~k);
        cpu_read(32'h0800_6000 + k*4, 2'b00, ~k, 4'hf);
    end

    // ---- alternate bus master cycles with _MI ----
    ram_poke(32'h0800_7000, 32'hD0D0_0000);
    dma_cycle(32'h0800_7000, 1, 0, 0, 32'hD0D0_0000);
    $display("DMA read, snoop inhibited: _TA after %0d clocks", ta_clocks);
    dma_cycle(32'h0800_7000, 1, 0, 1, 32'hD0D0_0000);
    $display("DMA read, snoop lookup: _TA after %0d clocks", ta_clocks);
    dma_cycle(32'h0800_7004, 0, 32'hD0D0_0004, 0, 0);
    if (ram_peek(32'h0800_7004) !== 32'hD0D0_0004) err("DMA write data");
    dma_cycle(32'h0800_7008, 0, 32'hBAD0_0000, 2, 0);   // snoop hit on write: memory must not change
    if (ram_peek(32'h0800_7008) === 32'hBAD0_0000) err("memory updated during snoop hit");
    dma_cycle(32'h0800_7000, 1, 0, 2, 0);               // snoop hit on read: memory must stay quiet
    cpu_read(32'h0800_7000, 2'b00, 32'hD0D0_0000, 4'hf); // CPU resumes normally
    cpu_line_read(32'h0800_7000);

    // ---- random traffic long enough to hit several refresh cycles (7.5us each) ----
    for (k = 0; k < 4096; k = k + 1) shadow[k] = 32'h0;
    for (k = 0; k < 4096; k = k + 1) ram_poke(32'h0900_0000 + k*4, 0);
    r = 1;
    for (n = 0; n < RAND_CYCLES; n = n + 1) begin
        r = $urandom;
        idx = r[11:0] & 12'hFFC;  // line aligned
        a = 32'h0900_0000 + idx*4;
        case (r[15:13])
            0, 1 : begin d = $urandom; cpu_write(a + r[17:16]*4, 2'b00, d); shadow[idx + r[17:16]] = d; end
            2    : begin cpu_read(a + r[17:16]*4, 2'b00, shadow[idx + r[17:16]], 4'hf); end
            3, 4 : begin cpu_line_read(a + r[17:16]*4); end
            5    : begin
                       cpu_line_write(a, $urandom, $urandom, $urandom, $urandom);
                       for (k = 0; k < 4; k = k + 1) shadow[idx + k] = ram_peek(a + k*4);
                   end
            6    : begin d = $urandom; cpu_write(a + r[17:16]*4 + r[19:18], 2'b01, d);
                       shadow[idx + r[17:16]] = ram_peek(a + r[17:16]*4); end
            7    : begin repeat (r[19:17]) @(posedge BCLK); end
        endcase
        if (n % 300 == 0) $display("%0t random traffic %0d cycles, %0d errors so far", $realtime, n, errors);
    end
    for (k = 0; k < 4096; k = k + 1) begin
        if (ram_peek(32'h0900_0000 + k*4) !== shadow[k]) err("random test memory mismatch");
    end

    repeat (20) @(posedge BCLK);
    errors = errors + ram0.errors + ram1.errors;
    $display("=== %0d bus cycles, %0d errors ===", cycles, errors);
    if (errors == 0) $display("PASS"); else $display("FAIL");
    $finish;
end

// Line read data check needs the sampled value: cpu_line_read compares against SDRAM contents at check time.

endmodule
`ifdef DBG
module dbg;
    always @(tb_u400.dut.U400_SDRAM_CONTROLLER.SDRAM_STATE or tb_u400.dut.U400_SDRAM_CONTROLLER.REQ)
        $display("%0t state=%h REQ=%b EVEN=%b TS_R=%b TS_S2=%b RAM_SPACE=%b POWERUP=%0d", $realtime,
            tb_u400.dut.U400_SDRAM_CONTROLLER.SDRAM_STATE, tb_u400.dut.U400_SDRAM_CONTROLLER.REQ,
            tb_u400.dut.U400_SDRAM_CONTROLLER.EVEN, tb_u400.dut.U400_SDRAM_CONTROLLER.TS_R,
            tb_u400.dut.U400_SDRAM_CONTROLLER.TS_S2, tb_u400.dut.U400_SDRAM_CONTROLLER.RAM_SPACE,
            tb_u400.dut.U400_SDRAM_CONTROLLER.POWERUP_COUNT);
    always @(negedge tb_u400.TS_CPU) $display("%0t TS asserted A=%h", $realtime, tb_u400.ADDR);
    always @(posedge tb_u400.RAMCLK) if (tb_u400.CS0n === 1'b0 && {tb_u400.RASn,tb_u400.CASn,tb_u400.WEn} != 3'b111 && $realtime > 150000)
        $display("%0t   SDRAM cmd RAS/CAS/WE=%b%b%b MA=%h CNT=%0d EVEN=%b", $realtime, tb_u400.RASn, tb_u400.CASn, tb_u400.WEn, tb_u400.MA,
                 tb_u400.dut.U400_SDRAM_CONTROLLER.CNT, tb_u400.dut.U400_SDRAM_CONTROLLER.EVEN);
    always @(tb_u400.TAn) if ($realtime > 150000) $display("%0t   TAn=%b", $realtime, tb_u400.TAn);
    always @(tb_u400.DQ) if ($realtime > 150000) $display("%0t   DQ=%h", $realtime, tb_u400.DQ);
    always @(posedge tb_u400.BCLK) if ($realtime > 150000) $display("%0t BCLK edge  TAn=%b DQ=%h", $realtime, tb_u400.TAn, tb_u400.DQ);
endmodule
`endif
