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
Design Name: U111
Module Name: U111_CYCLE_SM
Project Name: AmigaPCI
Target Devices: iCE40-HX4K-TQ144

Description: DATA TRANSFER CYCLE AND BUS SIZING STATE MACHINE

Date          Who  Description
-----------------------------------
19-APR-2025   JN   New bus sizing state machine.
31-MAY-2025   JN   Fixed burst cycle count value.
12-JUN-2025   JN   Fixed state machine crash when _LBEN is enabled.
13-JUN-2025   JN   Conditions most signals to support PCI DMA cycles.
13-NOV-2025   JN   Change S5 to drop burst check.
11-FEB-2026   JN   Fixed assertion of TSn_CPU during DMA cycles.
14-FEB-2026   JN   Fixed issue where CPU starts a cycle on the same edge _BG is negated by arbiter.

GitHub: https://github.com/jasonsbeer/AmigaPCI
*/

module U111_CYCLE_SM (
    input CLK80, CLK40, RESETn, RnW, PORTSIZE, BGn, LBENn, TBIn, TCIn, TEAn, CPU_BUS,
    input [1:0] SIZ,
    input A_040,

    output TBI_CPUn, TCI_CPUn, TEA_CPUn,
    output A_AMIGA,
    
    inout TSn_CPU, inout TSn,
    inout TAn, inout TACKn,

    inout [7:0] D_UU_040, //68040 DATA BUS
    inout [7:0] D_UM_040,
    inout [7:0] D_LM_040,
    inout [7:0] D_LL_040,

    inout [7:0] D_UU_AMIGA, //AMIGA DATA BUS
    inout [7:0] D_UM_AMIGA,
    inout [7:0] D_LM_AMIGA,
    inout [7:0] D_LL_AMIGA

    //,output TP0
);

//assign TP0 = TSn_DMA_EDGE[0];

/////////////////////
// TRANSFER START //
///////////////////

//Transfer start goes two directions. During CPU driven cycles,
//the CPU asserts _TS-CPU and this is then asserted to _TS one clock
//later. The opposite is true during PCI DMA driven cycles.

reg CPU_BUS_OWN;
reg TSn_CPU_DETECT, TSn_DMA_DETECT;
always @(posedge CLK40) begin
    if (!RESETn) begin
        TSn_CPU_DETECT <= 1'b0;
        TSn_DMA_DETECT <= 1'b0;
        CPU_BUS_OWN    <= 1'b0;
    end else begin
        TSn_CPU_DETECT <= ~TSn_CPU;
        TSn_DMA_DETECT <= ~TSn;
        if (CPU_BUS_OWN) begin
            if (!CPU_BUS) begin                    
                    CPU_BUS_OWN <= 0;
                end
        end else begin
            if (CPU_BUS) begin
                CPU_BUS_OWN <= 1;
            end
        end
    end
    
end

reg TSn_OUT, TSn_CPU_OUT;
always @(negedge CLK40) begin
    if (!RESETn) begin
        TSn_OUT     <= 1;
        TSn_CPU_OUT <= 1;
    end else begin
        TSn_OUT     <= ~( CPU_BUS_OWN && (TSn_CPU_DETECT || TS_EN));
        TSn_CPU_OUT <= ~(!CPU_BUS_OWN && TSn_DMA_DETECT);
    end
end

assign TSn = CPU_BUS_OWN ? TSn_OUT : 1'bz;
assign TSn_CPU = !CPU_BUS_OWN ? TSn_CPU_OUT : 1'bz;

////////////////////////
// CYCLE TERMINATION //
//////////////////////

//_TACK (_TA) AND _TEA COMPRISE THE CYCLE TERMINATION SIGNALS.
//WE PASS THE _TACK SIGNAL TO _TA FOR OFF-BOARD CYCLES.
//WE PASS THE _TA SIGNAL TO _TACK FOR ON-BOARD CYCLES.

assign TAn = !TA_DIS && LBENn ? TACKn : 1'bz;
assign TACKn = !LBENn ? TAn : 1'bz;
assign TEA_CPUn = !TA_DIS ? TEAn : 1'b1;

assign TBI_CPUn = !LBENn ? 1'b0 : TBIn; //No RAM burst.
//assign TBI_CPUn = !LBENn ? 1'b1 : TBIn;

assign TCI_CPUn = !LBENn ? 1'b0 : TCIn; //No RAM cache.
//assign TCI_CPUn = !LBENn ? 1'b1 : TCIn;


///////////////////////
// DATA BUS ENABLES //
/////////////////////

//THE BUFFERS ARE ENABLED BASED ON WHO HAS THE BUS AND THE DIRECTION OF THE DATA FLOW.

wire ONBOARD_EN = (READ_CYCLE_ACTIVE || (!CPU_BUS && !RnW));
wire OFFBOARD_EN = (WRITE_CYCLE_ACTIVE || (!CPU_BUS && RnW));

////////////////////////
// DATA PASS THROUGH //
//////////////////////

//READS
assign D_UU_040 = ONBOARD_EN ? (LATCH_EN  ? UU_LATCHED : D_UU_AMIGA) : 8'bzzzzzzzz;
assign D_UM_040 = ONBOARD_EN ? (LATCH_EN  ? UM_LATCHED : D_UM_AMIGA) : 8'bzzzzzzzz;
assign D_LM_040 = ONBOARD_EN ? (FLIP_WORD ? D_UU_AMIGA : D_LM_AMIGA) : 8'bzzzzzzzz;
assign D_LL_040 = ONBOARD_EN ? (FLIP_WORD ? D_UM_AMIGA : D_LL_AMIGA) : 8'bzzzzzzzz;

//WRITES
assign D_UU_AMIGA = OFFBOARD_EN ? (FLIP_WORD ? D_LM_040 : D_UU_040) : 8'bzzzzzzzz;
assign D_UM_AMIGA = OFFBOARD_EN ? (FLIP_WORD ? D_LL_040 : D_UM_040) : 8'bzzzzzzzz;
assign D_LM_AMIGA = OFFBOARD_EN ? D_LM_040 : 8'bzzzzzzzz;
assign D_LL_AMIGA = OFFBOARD_EN ? D_LL_040 : 8'bzzzzzzzz;

//These are for the bus sizing state machine.
wire [7:0] UU_AMIGA_IN = D_UU_AMIGA;
wire [7:0] UM_AMIGA_IN = D_UM_AMIGA;

/////////////////////////
// BUS SIZING ADDRESS //
///////////////////////

//THE ADDRESS BUS DEFAULTS TO THE CPU ASSERTED ADDRESS. WE CHANGE IT TO $2 WHEN
//IN THE SECOND CYCLE OF A LONG WORD TO WORD PORT DATA TRANSFER.

//assign A_AMIGA = A2_EN ? 2'b10 : A_040;
assign A_AMIGA = A2_EN ? 1'b1 : A_040;

////////////////////////
// TERMINATION TYPES //
//////////////////////

//wire TERMINATION = {TACKn, TEAn};
localparam [1:0] TERM_NORMAL = 2'b01;
localparam [1:0] TERM_RETRY  = 2'b00;
localparam [1:0] TERM_ERROR  = 2'b10;
localparam [1:0] TERM_WAIT   = 2'b11;

////////////////////////////////////////
// DATA TRANSFER CYCLE STATE MACHINE //
//////////////////////////////////////

//DURING LONG WORD TRANSFERS TO WORD PORTS, WE NEED TO TAKE
//OVER THE CYCLE FROM THE CPU. WE CREATE TWO LOCAL CYCLES FROM ONE CPU
//CYCLE. THE FIRST CYCLE TRANSFERS THE HIGH WORD (ADDRESS 0). THE SECOND CYCLE
//TRANSFERS THE LOWER WORD (ADDRESS 2). CYCLES AGAINST LIKE PORTS AT ADDRESS 0
//ARE SIMPLY PASSED THROUGH. CYCLES AGAINST LIKE PORTS AT ADDRESS 2 ARE "FLIPPED"
//SO THE WORD APPEARS ON THE CORRECT BYTE LANES.

//WE DO NOT RUN THIS STATE MACHINE FOR ON-BOARD CYCLES (QUALIFIED BY _LBEN).

reg TS_EN;
reg TA_DIS;
reg LATCH_EN;
reg PORT_MISMATCH;
reg READ_CYCLE_ACTIVE;
reg WRITE_CYCLE_ACTIVE;
reg FLIP_WORD;
reg A2_EN;
reg BURST;
reg LW_TRANS;

reg [3:0] CYCLE_STATE;
reg [7:0] UU_LATCHED;
reg [7:0] UM_LATCHED;
reg [1:0] BURST_COUNT;

always @(posedge CLK40) begin
    if (!RESETn) begin
        TS_EN              <= 0;                      
        A2_EN              <= 0;        
        BURST              <= 0;
        TA_DIS             <= 0; 
        LW_TRANS           <= 0;
        LATCH_EN           <= 0;
        FLIP_WORD          <= 0;
        PORT_MISMATCH      <= 0;
        READ_CYCLE_ACTIVE  <= 0;
        WRITE_CYCLE_ACTIVE <= 0;

        CYCLE_STATE <= 4'h0;
        BURST_COUNT <= 2'b0;
        UU_LATCHED  <= 8'h0;
        UM_LATCHED  <= 8'h0;
    end else begin

        case (CYCLE_STATE)            
            4'h0 : begin
                if (!TSn_OUT && LBENn) begin
                    READ_CYCLE_ACTIVE <= RnW;
                    WRITE_CYCLE_ACTIVE <= !RnW;
                    LW_TRANS <= SIZ[1] == SIZ[0];
                    BURST <= (SIZ == 2'b11);
                    BURST_COUNT <= 2'h0;
                    CYCLE_STATE <= 4'h1;
                end else begin
                    LATCH_EN <= 0;
                    FLIP_WORD <= 0;
                    READ_CYCLE_ACTIVE <= 0;
                    WRITE_CYCLE_ACTIVE <= 0;
                end
            end
            4'h1 : begin
                PORT_MISMATCH <= (PORTSIZE && LW_TRANS);
                TA_DIS <= (PORTSIZE && LW_TRANS);
                FLIP_WORD <= (PORTSIZE && A_040); //Flip the position of the words when at address $2.
                CYCLE_STATE <= 4'h2;
            end
            4'h2 : begin
                case ({TACKn, TEAn})
                    TERM_NORMAL : begin
                        CYCLE_STATE <= PORT_MISMATCH ? 4'h3 : ((!BURST || !TBIn || (BURST_COUNT == 2'h3)) ? 4'h0 : 4'h2);
                        BURST_COUNT <= BURST_COUNT + 1;
                        UU_LATCHED <= READ_CYCLE_ACTIVE ? UU_AMIGA_IN : 8'h00;
                        UM_LATCHED <= READ_CYCLE_ACTIVE ? UM_AMIGA_IN : 8'h00;
                    end
                    TERM_RETRY : begin
                        //When there is a port mismatch condition, _TA-CPU and _TEA-CPU are disabled.
                        //It will be necessary to terminate the cycle here by creating our own.
                        CYCLE_STATE <= 4'h0;
                    end
                    TERM_ERROR : begin
                        //When there is a port mismatch condition, _TEA-CPU is disabled.
                        //It will be necessary to terminate the cycle here by creating our own.
                        CYCLE_STATE <= 4'h0;
                    end
                endcase
            end
            4'h3 : begin
                LATCH_EN <= READ_CYCLE_ACTIVE;
                A2_EN <= 1;
                TS_EN <= 1;
                TA_DIS <= 0;
                FLIP_WORD <= 1;
                CYCLE_STATE <= 4'h4;
            end
            4'h4 : begin
                TS_EN <= 0;
                CYCLE_STATE <= 4'h5;
            end
            4'h5 : begin
                if ({TACKn, TEAn} != TERM_WAIT) begin
                    //No 16-bit device on the AmigaPCI supports burst cycles.
                    A2_EN <= 0;
                    CYCLE_STATE <= 4'h0;
                end
            end
        endcase
    end
end

endmodule
