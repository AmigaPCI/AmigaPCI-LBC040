/*
LICENSE:

This work is released under the Creative Commons Attribution-NonCommercial 4.0 International
https://creativecommons.org/licenses/by-nc/4.0/

You are free to:
Share — copy and redistribute the material in any medium or format
Adapt — remix, transform, and build upon the material
The licensor cannot revoke these freedoms as long as you follow the license terms.

Under the following terms:
Attribution — You must give appropriate credit , provide a link to the license, and indicate if changes were made . You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
NonCommercial — You may not use the material for commercial purposes.
No additional restrictions — You may not apply legal terms or technological measures that legally restrict others from doing anything the license permits.

RTL MODULE:

Engineer: Jason Neus
Design Name: U400
Module Name: U400_SDRAM_CONTROLLER
Project Name: AmigaPCI Local Bus Card
Target Devices: iCE40-HX1K-VQ100

Description: SDRAM CONTROLLER WITH MC68040 LINE (BURST) TRANSFERS AND SNOOP SUPPORT.

Revision History:
    22-JUN-2026 : Initial Rev 6.x Release
    02-SEP-2026 : Line (burst) transfers, memory inhibit (_MI) support for
                  snooped alternate bus master cycles, refresh/precharge guards.

CLOCKING
--------
The SDRAM and this state machine run on CLK80. The MC68040 bus runs on CLK40.
Both clocks come from the same PLL in U111 (CLK40 is CLK80 divided by two), so
every rising edge of CLK40 coincides with a rising edge of CLK80. We call those
CLK80 edges "even" and the ones in between "odd". A flop clocked on the falling
edge of CLK80 samples CLK40 half a period before each rising edge, which tells
the state machine which kind of edge is coming without any race at the shared
edge (the sample point is 6.25ns away from every CLK40 transition).

Bus inputs are registered on CLK40 (TS_R, MI_R, TA_R) and are only consumed on
odd edges, 12.5ns later, so no data is ever taken across the coincident edge.
SDRAM commands are registered on CLK80 and sampled by the SDRAM one edge later.

READ DATA TIMING
----------------
The SDRAM burst length is one. A read command issued at CLK80 edge N delivers
its data after edge N+2 (CAS latency 2) for exactly one CLK80 period, which is
too short for the MC68040 to sample safely. Every read is therefore issued
twice on consecutive edges with the same column address, so the SDRAM drives
the same word for 25ns. The CPU sampling edge (even) falls in the middle of
that window: data valid tAC (6ns) after the odd edge before it, held tOH
(2.5ns) after the odd edge after it. Line reads issue four such pairs back to
back and deliver one long word per CLK40, which the MC68040 acknowledges with
_TA held asserted for four consecutive clocks.

WRITE DATA TIMING
-----------------
The write command is registered on the even edge ahead of the CPU sampling
edge, so the SDRAM captures the data one CLK80 (12.5ns) before the CPU samples
_TA, while the CPU is still driving it. During line writes the MC68040 can take
up to 27ns after each _TA to present the next long word, which is more than one
CLK40 period. Line writes therefore run at one long word every two CLK40
periods with _TA pulsed every other clock. This is what caused the rare nibble
corruption in burst writes on the Rev 5 controller.

SNOOPING / MEMORY INHIBIT
-------------------------
_MI is asserted by the MC68040 between and during alternate bus master cycles
until it has decided whether it must intervene. Memory must not respond while
_MI is asserted. When a cycle is requested and _MI is asserted we hold the
request and wait. If _MI is negated we run the cycle normally. If _TA is
asserted by somebody else while a request is pending, the MC68040 has serviced
the access from its cache (or the cycle ended some other way we cannot see) and
we drop the request without touching the SDRAM. This rule applies in every
state, because the MC68040's _TA is a single clock and can arrive while we are
refreshing. A new _TS while a request is pending replaces the request.

CYCLE TIMING (CLK40 periods from _TS to the last _TA sampled)
------------------------------------------------------------
                 FAST_READ = 1 (default)   FAST_READ = 0
Long word read : 5 (unchanged)             6
Line read      : 8  (was ~20 burst inhib.) 12
Long word write: 4 (unchanged)             4
Line write     : 10 (was ~16 burst inhib.) 10
One more clock when _TS reaches U400 after the CLK40 edge ending C1.

Simulation (sim/tb_u400.v, ISSI -7 timing, MC68040 40MHz input specs) passes
FAST_READ = 1 with up to 3ns of combined adverse skew between the CPU clock and
the SDRAM clock, and FAST_READ = 0 with more than 3.5ns.

GitHub: https://github.com/jasonsbeer/AmigaPCI
*/

module U400_SDRAM_CONTROLLER #(
    //FAST_READ = 1: one long word per CLK40 during line reads, 5 clock long word
    //reads. Read data becomes valid about 6.5ns before the CPU samples it, which
    //is the same margin the Rev 6.0 controller has (MC68040 needs 3ns at 40MHz).
    //FAST_READ = 0: two CLK40 per long word, 6 clock long word reads. Read data
    //becomes valid about 19ns before the CPU samples it. Use this if cached RAM
    //is unstable on a particular board.
    parameter FAST_READ = 1
)(
    input CLK80, CLK40, RESETn, TSn, RAM_SPACE, RnW, MIn,
    input [26:0] A,
    input [1:0] SIZ,

    inout TAn,

    output CS0n,
    output CS1n,
    output CLK_EN,
    output RASn,
    output CASn,
    output WEn,
    output [12:0] MA,
    output BANK0,
    output BANK1,
    output UUBEn, UMBEn, LMBEn, LLBEn,
    output TP
);

///////////////////////////
// CLOCK PHASE DETECTOR //
/////////////////////////

//Sample CLK40 on the falling edge of CLK80. If CLK40 is low there, the next
//rising edge of CLK80 is also a rising edge of CLK40 (an "even" edge).
reg CLK40_SMP;
always @(negedge CLK80) begin
    CLK40_SMP <= CLK40;
end
wire EVEN = ~CLK40_SMP;

//////////////////////////
// LATCHED CYCLE INFO  //
////////////////////////

reg        L_CS;
reg  [1:0] L_BANK;
reg [12:0] L_ROW;
reg  [8:0] L_COL;   //Column of the first long word. A[3:2] increment for line transfers.
reg  [1:0] L_A10;   //A[1:0] for byte masks.
reg  [1:0] L_SIZ;
reg        L_RnW;
reg        L_LINE;  //Four long word transfer.

//Column address for the current beat. Line transfers wrap within the 16 byte line.
reg [1:0] BEAT;
wire [8:0] BEAT_COL = {L_COL[8:2], L_COL[1:0] + BEAT};

////////////////////////
// TRANSFER ACK PIN  //
//////////////////////

//We drive _TA from the start of our SDRAM cycle until it is finished. Outside
//of that the pin is an input so we can see the MC68040 acknowledge a snooped
//access itself.
reg TA_DRV;
reg TA_OUT;
assign TAn = TA_DRV ? TA_OUT : 1'bz;

assign TP = TA_DRV;

///////////////////////////
// BUS INPUT REGISTERS  //
/////////////////////////

//These are sampled on the bus clock, exactly when the MC68040 expects them to
//be sampled, and are consumed by the CLK80 state machine on odd edges only.
reg TS_R;   //_TS was asserted at the last CLK40 edge.
reg TS_R_D; //...and at the one before.
reg MI_R;   //_MI was negated at the last CLK40 edge (memory may respond).
reg TA_R;   //_TA was asserted at the last CLK40 edge (by someone else).
always @(posedge CLK40) begin
    if (!RESETn) begin
        TS_R   <= 1'b0;
        TS_R_D <= 1'b0;
        MI_R   <= 1'b0;
        TA_R   <= 1'b0;
    end else begin
        TS_R   <= ~TSn;
        TS_R_D <= TS_R;
        MI_R   <= MIn;
        TA_R   <= ~TAn && !TA_DRV;
    end
end

//_TS is one clock wide but can still look asserted at the following bus clock
//edge (MC68040 output hold plus the pass through in U111), so only the first
//edge on which it is seen counts. That keeps the tail of one cycle's _TS from
//starting a cycle on the address of the next one.
wire TS_NEW = TS_R && !TS_R_D;

//_TS can also arrive at this FPGA late in the cycle (MC68040 output delay plus
//the pass through in U111), so we sample it again on the odd CLK80 edge 12.5ns
//after the bus edge, together with the address decode as it stands at that
//moment. TS_S2 holds that sample when the state machine looks at it on the
//following odd edge.
reg TS_S1, TS_S2;
always @(posedge CLK80) begin
    TS_S1 <= ~TSn && RAM_SPACE;
    TS_S2 <= TS_S1;
end

wire TS_SEEN = (TS_NEW && RAM_SPACE) || TS_S2;

////////////////////////////
// SDRAM COMMAND ENCODING //
///////////////////////////

//THE SDRAM COMMAND CONSTANTS ARE: _RAS, _CAS, _WE
localparam [2:0] NOP          = 3'b111;
localparam [2:0] PRECHARGE    = 3'b010;
localparam [2:0] BANKACTIVATE = 3'b011;
localparam [2:0] READ         = 3'b101;
localparam [2:0] WRITE        = 3'b100;
localparam [2:0] AUTOREFRESH  = 3'b001;
localparam [2:0] MODEREGISTER = 3'b000;

//8192 rows must be refreshed every 64ms, one AUTO REFRESH every 7.8125us. The
//counter is cleared when the command is issued and a refresh is due 560 clocks
//(7.0us) later. The state machine adds a few clocks and a cycle in progress can
//add up to 25 more, so the longest gap is about 7.5us.
localparam [11:0] REFRESH_DEFAULT = 12'd560;

//Power up delay before the first SDRAM command. JEDEC asks for 100us of stable clock.
localparam [13:0] POWERUP_CLOCKS = 14'd12000; //150us at 80MHz

//--- Fixed Command Addresses ---
localparam [12:0] ADD_PRECHARGE_ALL = 13'b0_0100_0000_0000; //A10 = 1
localparam [12:0] CMD_REGISTER      = 13'b000_1_00_010_0_000; //Single write, CAS latency 2, sequential, burst length 1.

//--- State machine states. ---
localparam [3:0] POWER_UP     = 4'h0;
localparam [3:0] CONFIG_PRECH = 4'h1;
localparam [3:0] CONFIG_REFR  = 4'h2;
localparam [3:0] CONFIG_REGST = 4'h3;
localparam [3:0] CONFIG_END   = 4'h4;
localparam [3:0] REFRESH_STRT = 4'h5;
localparam [3:0] REFRESH_WAIT = 4'h6;
localparam [3:0] SDRAM_IDLE   = 4'h7;
localparam [3:0] SDRAM_CYCLE  = 4'h9;
localparam [3:0] SDRAM_DONE   = 4'ha;

//////////////////////
// SDRAM I/O PINS  //
////////////////////

reg CS_EN;           //Chip select for the addressed device.
reg CS_EN_ALL;       //Chip select for both devices (init and refresh).
reg DQ_EN;           //Drive the byte masks.
reg [2:0] CMD_OUT;
reg [12:0] MA_OUT;

assign CLK_EN = 1'b1; //Never suspend the SDRAM clock.
//The bank address must be zero for LOAD MODE REGISTER, which like PRECHARGE
//ALL and AUTO REFRESH selects both devices. L_BANK may hold a request that
//arrived before configuration finished.
assign BANK0  = CS_EN_ALL ? 1'b0 : L_BANK[0];
assign BANK1  = CS_EN_ALL ? 1'b0 : L_BANK[1];
assign CS1n   = ~((CS_EN &&  L_CS) || CS_EN_ALL);
assign CS0n   = ~((CS_EN && !L_CS) || CS_EN_ALL);
assign RASn   = CMD_OUT[2];
assign CASn   = CMD_OUT[1];
assign WEn    = CMD_OUT[0];
assign MA     = MA_OUT;

//Byte masks. Line transfers (SIZ = 11) and long words (SIZ = 00) enable everything.
wire L_LONG = (L_SIZ[1] == L_SIZ[0]);
wire L_WORD = (L_SIZ[1] && !L_SIZ[0]);
assign UUBEn = DQ_EN ? ~((L_A10 == 2'b00) || L_LONG) : 1'b1;
assign UMBEn = DQ_EN ? ~((L_A10 == 2'b01) || (L_WORD && !L_A10[1]) || L_LONG) : 1'b1;
assign LMBEn = DQ_EN ? ~((L_A10 == 2'b10) || L_LONG) : 1'b1;
assign LLBEn = DQ_EN ? ~((L_A10 == 2'b11) || (L_WORD &&  L_A10[1]) || L_LONG) : 1'b1;

//////////////////////
// STATE MACHINE   //
////////////////////

reg  [3:0] SDRAM_STATE;
reg  [4:0] CNT;            //Clocks since the bank activate command.
reg  [3:0] WAIT_CNT;
reg [11:0] REFRESH_COUNT;
reg [13:0] POWERUP_COUNT;
reg        SDRAM_CONFIGURED;
reg        CONFIG_REFRESH_DONE;

//Set once the SDRAM has been configured and never cleared by RESETn. A reset
//with WARM set is a warm reset: the SDRAM clock has been running all along and
//the devices only need their rows closed and the mode register reloaded. The
//flop starts at zero when the FPGA is configured, which is the cold start.
reg        WARM = 1'b0;
always @(posedge CLK80) begin
    if (SDRAM_CONFIGURED) WARM <= 1'b1;
end
reg        REQ;            //A cycle request is waiting (refresh in progress or _MI asserted).
reg        REQ_FRESH;      //The request was captured on the last odd edge.
reg        ABORT;          //The cycle was started while _MI was asserted after all; back out.

wire REFRESH_DUE = (REFRESH_COUNT > REFRESH_DEFAULT);

//A _TA we did not drive while a request is pending means the cycle we were
//asked for has been terminated by somebody else (the MC68040 as a snoop slave,
//or a bus error), so the request is void. The MC68040 cannot respond earlier
//than two clocks after _TS, so a _TA seen on the edge the request was captured
//or the one after belongs to the previous bus cycle and is ignored.
wire REQ_CANCEL = REQ && !REQ_FRESH && TA_R;

//A new _TS while a request is pending means the pending cycle is over and a
//new one has started. The request is taken again from the current address.
wire REQ_RENEW  = REQ && !REQ_FRESH && TS_NEW && RAM_SPACE;

//Read schedule. Commands run from CNT = 2 to RD_LAST, the cycle ends at RD_DONE.
wire [4:0] RD_LAST = FAST_READ ? (L_LINE ? 5'd9  : 5'd3) : (L_LINE ? 5'd17 : 5'd5);
wire [4:0] RD_DONE = FAST_READ ? (L_LINE ? 5'd12 : 5'd6) : (L_LINE ? 5'd20 : 5'd8);

always @(posedge CLK80) begin
    if (!RESETn) begin
        CS_EN      <= 1'b0;
        CS_EN_ALL  <= 1'b0;
        DQ_EN      <= 1'b0;
        CMD_OUT    <= NOP;
        MA_OUT     <= 13'b0;
        TA_DRV     <= 1'b0;
        TA_OUT     <= 1'b1;
        REQ        <= 1'b0;
        REQ_FRESH  <= 1'b0;
        ABORT      <= 1'b0;
        BEAT       <= 2'b0;
        CNT        <= 5'b0;
        WAIT_CNT   <= 4'b0;
        L_CS       <= 1'b0;
        L_BANK     <= 2'b0;
        L_ROW      <= 13'b0;
        L_COL      <= 9'b0;
        L_A10      <= 2'b0;
        L_SIZ      <= 2'b0;
        L_RnW      <= 1'b1;
        L_LINE     <= 1'b0;
        REFRESH_COUNT       <= 12'b0;
        POWERUP_COUNT       <= 14'b0;
        SDRAM_CONFIGURED    <= 1'b0;
        CONFIG_REFRESH_DONE <= 1'b0;
        SDRAM_STATE         <= POWER_UP;
    end else begin

        //--- Defaults. Commands are one clock wide. ---
        CS_EN     <= 1'b0;
        CS_EN_ALL <= 1'b0;
        CMD_OUT   <= NOP;
        if (REFRESH_COUNT != 12'hFFF) REFRESH_COUNT <= REFRESH_COUNT + 1; //Saturate; a late refresh stays due.
        CNT <= CNT + 1;

        //--- Bus events. Looked at on odd edges only, so the CLK40 registered inputs are stable. ---
        if (!EVEN) begin
            REQ_FRESH <= 1'b0;

            //Somebody else terminated the cycle we hold a request for.
            if (REQ_CANCEL) REQ <= 1'b0;

            //Capture a request while we are busy with something other than our own
            //cycle, or replace a pending request when a new _TS arrives. In IDLE
            //the same edge may start the cycle right away, which clears REQ again.
            //Nothing is captured during our own cycle because _TS may still look
            //asserted on the edge after the one we already used.
            if (TS_SEEN && (!REQ || REQ_RENEW) && (SDRAM_STATE != SDRAM_CYCLE)) begin
                REQ       <= 1'b1;
                REQ_FRESH <= 1'b1;
                L_CS      <= A[26];
                L_BANK    <= A[25:24];
                L_ROW     <= A[23:11];
                L_COL     <= A[10:2];
                L_A10     <= A[1:0];
                L_SIZ     <= SIZ;
                L_RnW     <= RnW;
                L_LINE    <= (SIZ == 2'b11);
            end
        end

        case (SDRAM_STATE)

            //--- Power up: wait for a stable clock before the first command. ---
            //A warm reset may have interrupted a cycle with a row open, and no
            //refresh happens while we wait. Give that row tRAS and go straight to
            //the precharge; only a cold start gets the 100us of stable clock.
            POWER_UP : begin
                POWERUP_COUNT <= POWERUP_COUNT + 1;
                if (POWERUP_COUNT == (WARM ? 14'd8 : POWERUP_CLOCKS)) begin
                    SDRAM_STATE <= CONFIG_PRECH;
                end
            end

            //--- Configuration: precharge all, two refreshes, load the mode register. ---
            CONFIG_PRECH : begin
                CS_EN_ALL   <= 1'b1;
                CMD_OUT     <= PRECHARGE;
                MA_OUT      <= ADD_PRECHARGE_ALL;
                WAIT_CNT    <= 4'd2; //tRP
                SDRAM_STATE <= CONFIG_REFR;
            end
            CONFIG_REFR : begin
                if (WAIT_CNT != 0) begin
                    WAIT_CNT <= WAIT_CNT - 1;
                end else begin
                    SDRAM_STATE <= REFRESH_STRT;
                end
            end
            CONFIG_REGST : begin
                CS_EN_ALL   <= 1'b1;
                CMD_OUT     <= MODEREGISTER;
                MA_OUT      <= CMD_REGISTER;
                WAIT_CNT    <= 4'd2; //tMRD
                SDRAM_STATE <= CONFIG_END;
            end
            CONFIG_END : begin
                if (WAIT_CNT != 0) begin
                    WAIT_CNT <= WAIT_CNT - 1;
                end else begin
                    SDRAM_CONFIGURED <= 1'b1;
                    REFRESH_COUNT    <= 12'b0;
                    SDRAM_STATE      <= SDRAM_IDLE;
                end
            end

            //--- Auto refresh. Also used twice during configuration. ---
            REFRESH_STRT : begin
                CS_EN_ALL     <= 1'b1;
                CMD_OUT       <= AUTOREFRESH;
                REFRESH_COUNT <= 12'b0;
                WAIT_CNT      <= 4'd6; //The next command is sampled 8 clocks (100ns) after this one; tRFC is 63ns.
                SDRAM_STATE   <= REFRESH_WAIT;
            end
            REFRESH_WAIT : begin
                if (WAIT_CNT != 0) begin
                    WAIT_CNT <= WAIT_CNT - 1;
                end else begin
                    if (SDRAM_CONFIGURED) begin
                        SDRAM_STATE <= SDRAM_IDLE;
                    end else if (CONFIG_REFRESH_DONE) begin
                        SDRAM_STATE <= CONFIG_REGST;
                    end else begin
                        CONFIG_REFRESH_DONE <= 1'b1;
                        SDRAM_STATE <= REFRESH_STRT;
                    end
                end
            end

            //--- Idle. Cycles start on odd edges only. ---
            //A pending request whose cycle the MC68040 is still snooping (_MI
            //asserted) waits here; refresh is not held up by it.
            SDRAM_IDLE : begin
                if (REFRESH_DUE && (!REQ || (!EVEN && !MI_R))) begin
                    SDRAM_STATE <= REFRESH_STRT;
                end else if (!EVEN && !REQ_CANCEL && (REQ || TS_SEEN) && MI_R) begin
                    //Memory may respond. Activate the row now. The request capture
                    //above latches the cycle information for a new _TS on this
                    //same edge, so the row comes straight from the address bus.
                    REQ         <= 1'b0;
                    CS_EN       <= 1'b1;
                    CMD_OUT     <= BANKACTIVATE;
                    MA_OUT      <= (REQ && !REQ_RENEW) ? L_ROW : A[23:11];
                    BEAT        <= 2'b0;
                    CNT         <= 5'b0;
                    ABORT       <= 1'b0;
                    TA_DRV      <= 1'b1;
                    TA_OUT      <= 1'b1;
                    SDRAM_STATE <= SDRAM_CYCLE;
                end
            end

            //--- Data transfer. CNT = 0 on the edge after the bank activate. ---
            //Relative to the CLK40 edge on which _TS was sampled (E2, with the
            //activate registered on E3): CNT = n corresponds to edge E(4+n).
            //Even CLK40 edges are CNT = 2, 4, 6, ... (E6, E8, E10, ...).
            SDRAM_CYCLE : begin
                if (CNT == 5'd1 && !MI_R) begin
                    //_MI was asserted after the bus clock edge on which we sampled it
                    //together with _TS. The MC68040 asserts _MI from the last _TA of an
                    //alternate bus master cycle, and when that master starts its next
                    //cycle straight away the _TS is sampled before _MI has arrived.
                    //Only the activate has been sent so far: back out and hold the
                    //request until _MI is negated. Release _TA so the MC68040's own
                    //acknowledge can be seen if it services the access itself.
                    ABORT  <= 1'b1;
                    REQ    <= 1'b1;
                    TA_DRV <= 1'b0;
                end else if (ABORT) begin
                    //Close the row once tRAS is satisfied (activate sampled at CNT = 0).
                    if (CNT == 5'd3) begin
                        CS_EN       <= 1'b1;
                        CMD_OUT     <= PRECHARGE;
                        MA_OUT      <= 13'b0;
                        WAIT_CNT    <= 4'd1; //tRP
                        SDRAM_STATE <= SDRAM_DONE;
                    end
                end else if (L_RnW) begin
                    //READS: RD_PER_BEAT read commands per long word, each with
                    //the same column, so the SDRAM drives every long word for
                    //RD_PER_BEAT x 12.5ns. FAST_READ: beat k is on the bus from
                    //E(9+2k) to E(11+2k) and the CPU samples it at E(10+2k)
                    //(CNT = 6+2k). Otherwise beat k is on the bus from E(9+4k) to
                    //E(13+4k) and the CPU samples it at E(12+4k) (CNT = 8+4k).
                    if (CNT >= 5'd2 && CNT <= RD_LAST) begin
                        CS_EN   <= 1'b1;
                        CMD_OUT <= READ;
                        DQ_EN   <= 1'b1;
                        //Auto precharge on the very last read command.
                        MA_OUT  <= {2'b00, (CNT == RD_LAST), 1'b0, BEAT_COL};
                        //Advance after the last command of each beat.
                        if (FAST_READ ? CNT[0] : (CNT[1:0] == 2'b01)) BEAT <= BEAT + 1;
                    end
                    if (FAST_READ) begin
                        if (CNT == 5'd4) TA_OUT <= 1'b0;
                    end else begin
                        if (CNT[1:0] == 2'b10 && CNT >= 5'd6 && CNT < RD_DONE) TA_OUT <= 1'b0;
                        if (CNT[1:0] == 2'b00 && CNT >= 5'd8) TA_OUT <= 1'b1;
                    end
                    if (CNT == RD_DONE) begin
                        TA_OUT      <= 1'b1;
                        DQ_EN       <= 1'b0;
                        WAIT_CNT    <= 4'd1; //Precharge is complete before the next activate can be issued.
                        SDRAM_STATE <= SDRAM_DONE;
                    end
                end else begin
                    //WRITES: the write command is registered on the even edge
                    //before the CPU samples _TA, so the SDRAM captures the data
                    //12.5ns before the CPU sees the acknowledge. Line writes take
                    //two CLK40 per long word so the CPU has time to drive the
                    //next long word (up to 27ns after _TA).
                    if (CNT == 5'd2 || (L_LINE && (CNT == 5'd6 || CNT == 5'd10 || CNT == 5'd14))) begin
                        CS_EN   <= 1'b1;
                        CMD_OUT <= WRITE;
                        DQ_EN   <= 1'b1;
                        MA_OUT  <= {2'b00, (L_LINE ? (CNT == 5'd14) : 1'b1), 1'b0, BEAT_COL};
                        BEAT    <= BEAT + 1;
                        TA_OUT  <= 1'b0;
                    end
                    if (CNT == 5'd4 || CNT == 5'd8 || CNT == 5'd12 || CNT == 5'd16) begin
                        TA_OUT <= 1'b1;
                    end
                    if (CNT == (L_LINE ? 5'd16 : 5'd4)) begin
                        DQ_EN       <= 1'b0;
                        WAIT_CNT    <= 4'd1; //tWR + tRP complete before the next activate can be issued.
                        SDRAM_STATE <= SDRAM_DONE;
                    end
                end
            end

            //--- Let the auto precharge finish before another activate or refresh. ---
            SDRAM_DONE : begin
                TA_DRV <= 1'b0;
                if (WAIT_CNT != 0) begin
                    WAIT_CNT <= WAIT_CNT - 1;
                end else begin
                    SDRAM_STATE <= SDRAM_IDLE;
                end
            end

            default : SDRAM_STATE <= SDRAM_IDLE;
        endcase
    end
end

endmodule
