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
20-JUN-2026   JN   Rev 6.x hardware release.
02-SEP-2026   SR   Line transfers of on-board RAM (needs U400 with burst support).
03-SEP-2026   JN   Cache jumper controls fast RAM only; ROM caching follows the mainboard.

GitHub: https://github.com/jasonsbeer/AmigaPCI
*/

module U111_CYCLE_SM (
    input CLK40, RESETn, RnW, PORTSIZE, BGn, LBENn, TBIn, TCIn, CPU_BUS, TSn_CPU,
    input [1:0] SIZ,
    input A_040,

    output TSn_RAM, TBI_CPUn, TCI_CPUn, TEA_CPUn,
    output A_AMIGA,
    
    inout TSn,
    inout TAn,
    inout TACKn,

    inout [7:0] D_UU_040, //68040 DATA BUS
    inout [7:0] D_UM_040,
    inout [7:0] D_LM_040,
    inout [7:0] D_LL_040,

    inout [7:0] D_UU_AMIGA, //AMIGA DATA BUS
    inout [7:0] D_UM_AMIGA,
    inout [7:0] D_LM_AMIGA,
    inout [7:0] D_LL_AMIGA

    //,output TP0
    ,input CACHE_EN
);

//assign TP0 = TSn_DMA_EDGE[0];
//assign TP0 = (OFFBOARD_EN || ONBOARD_EN);

/////////////////////
// TRANSFER START //
///////////////////

//Transfer start goes two directions. During CPU driven cycles,
//the CPU asserts _TS-CPU and this is then asserted to _TS one clock
//later. The opposite is true during PCI DMA driven cycles.

reg CPU_BUS_OWN;
reg TSn_CPU_DETECT;
//reg TSn_DMA_DETECT;
always @(posedge CLK40) begin
    if (!RESETn) begin
        TSn_CPU_DETECT <= 1'b0;
        //TSn_DMA_DETECT <= 1'b0;
        CPU_BUS_OWN    <= 1'b0;
    end else begin
        CPU_BUS_OWN    <= CPU_BUS; //Delay one clock.
        TSn_CPU_DETECT <= ~TSn_CPU;
        //TSn_DMA_DETECT <= ~TSn;
    end
    
end

reg TSn_OUT;
//reg TSn_CPU_OUT;
always @(negedge CLK40) begin
    if (!RESETn) begin
        TSn_OUT     <= 1'b1;
        //TSn_CPU_OUT <= 1'b1;
    end else begin
        TSn_OUT     <= ~( CPU_BUS_OWN && (TSn_CPU_DETECT || TS_EN));
        //TSn_CPU_OUT <= ~(!CPU_BUS_OWN && TSn_DMA_DETECT);
    end
end

assign TSn = CPU_BUS_OWN ? TSn_OUT : 1'bz;
//assign TSn_CPU = !CPU_BUS_OWN ? TSn_CPU_OUT : 1'bz; //May need to put this back for snooping.
assign TSn_RAM =  CPU_BUS ? TSn_CPU : TSn; //Drive the LBC RAM cycle. If this isn't adequately edge aligned, may need to delay a clock.

////////////////////////
// CYCLE TERMINATION //
//////////////////////

//WE PASS THE _TACK SIGNAL TO _TA FOR OFF-BOARD CYCLES.
//WE PASS THE _TA SIGNAL TO _TACK FOR ON-BOARD CYCLES.

assign TAn = !TA_DIS && LBENn ? TACKn : 1'bz;
assign TACKn = !LBENn ? TAn : 1'bz;
//assign TEA_CPUn = !TA_DIS ? TEAn : 1'b1;
assign TEA_CPUn = 1'b1;

//On-board RAM supports line (burst) transfers. The U400 SDRAM controller
//terminates line transfers with four _TA assertions, so _TBI is never asserted
//for fast RAM. Off-board cycles pass the mainboard's _TBI and _TCI through.
assign TBI_CPUn = !LBENn ? 1'b1 : TBIn;

//Caching of fast RAM is controlled by a test jumper for troubleshooting.
//CACHE_EN is U111 pin 67 (the SPI configuration data line, pulled up). A jumper
//across the GND and SDI pins of CN111 pulls it low and allows caching of fast
//RAM. Fit the jumper only after the FPGA has configured, and remove it before
//programming the card's FPGAs through the mainboard, which drives this line.
//ROM and everything else off-board follow the mainboard's _TCI.
//  LBENn = 0    : fast RAM address space
//  CACHE_EN = 0 : caching of fast RAM allowed (jumper fitted)
assign TCI_CPUn = !LBENn ? (!CACHE_EN ? 1'b1 : 1'b0) : TCIn;


///////////////////////
// DATA BUS ENABLES //
/////////////////////

//THE BUFFERS ARE ENABLED BASED ON WHO HAS THE BUS AND THE DIRECTION OF THE DATA FLOW.

wire ONBOARD_EN = (READ_CYCLE_ACTIVE || (!CPU_BUS && !RnW));
wire OFFBOARD_EN = (WRITE_CYCLE_ACTIVE || (!CPU_BUS && RnW));
//wire ONBOARD_EN = READ_CYCLE_ACTIVE;
//wire OFFBOARD_EN = WRITE_CYCLE_ACTIVE;
//wire ONBOARD_EN = LBENn && RnW && CPU_BUS;
//wire OFFBOARD_EN = LBENn && !RnW && CPU_BUS;

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

//THE ADDRESS BUS DEFAULTS TO THE CPU ASSERTED ADDRESS. WE CHANGE IT TO 0x2 WHEN
//IN THE SECOND CYCLE OF A LONG WORD TO WORD PORT DATA TRANSFER.

assign A_AMIGA = A2_EN ? 1'b1 : A_040;

////////////////////////////////////////
// DATA TRANSFER CYCLE STATE MACHINE //
//////////////////////////////////////

//DURING LONG WORD TRANSFERS TO WORD PORTS, WE NEED TO TAKE
//OVER THE CYCLE FROM THE CPU. WE CREATE TWO LOCAL CYCLES FROM ONE CPU
//CYCLE. THE FIRST CYCLE TRANSFERS THE HIGH WORD (ADDRESS 0x0). THE SECOND CYCLE
//TRANSFERS THE LOWER WORD (ADDRESS 0x2). CYCLES AGAINST LIKE PORTS AT ADDRESS 0
//ARE SIMPLY PASSED THROUGH. CYCLES AGAINST LIKE PORTS AT ADDRESS 2 ARE "FLIPPED"
//SO THE WORD APPEARS ON THE CORRECT BYTE LANES.

//WE DO NOT RUN THIS STATE MACHINE FOR ON-BOARD CYCLES (QUALIFIED BY _LBEN).

localparam [3:0] IDLE        = 4'h0;
localparam [3:0] CYCLE1_STRT = 4'h1;
localparam [3:0] CYCLE1_TERM = 4'h2;
localparam [3:0] CYCLE2_STRT = 4'h3;
localparam [3:0] CYCLE2_TERM = 4'h4;

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
        TS_EN              <= 1'b0;                      
        A2_EN              <= 1'b0;        
        BURST              <= 1'b0;
        TA_DIS             <= 1'b0; 
        LW_TRANS           <= 1'b0;
        LATCH_EN           <= 1'b0;
        FLIP_WORD          <= 1'b0;
        PORT_MISMATCH      <= 1'b0;
        READ_CYCLE_ACTIVE  <= 1'b0;
        WRITE_CYCLE_ACTIVE <= 1'b0;

        CYCLE_STATE <= IDLE;
        BURST_COUNT <= 2'b0;
        UU_LATCHED  <= 8'h0;
        UM_LATCHED  <= 8'h0;
    end else begin

        case (CYCLE_STATE)            
            IDLE : begin
                A2_EN     <= 1'b0;
                LATCH_EN  <= 1'b0;
                FLIP_WORD <= 1'b0;
                if (!TSn_OUT && LBENn) begin
                    READ_CYCLE_ACTIVE <= RnW;
                    WRITE_CYCLE_ACTIVE <= !RnW;
                    LW_TRANS <= (SIZ[1] == SIZ[0]);
                    BURST <= (SIZ == 2'b11);
                    CYCLE_STATE <= CYCLE1_STRT;
                end else begin
                    READ_CYCLE_ACTIVE  <= 1'b0;
                    WRITE_CYCLE_ACTIVE <= 1'b0;
                end
            end
            CYCLE1_STRT : begin
                if (PORTSIZE) begin
                    PORT_MISMATCH <= LW_TRANS;
                    TA_DIS        <= LW_TRANS;
                    FLIP_WORD     <= A_040; //Flip the position of the words when at address 0x2.
                end else begin
                    PORT_MISMATCH <= 1'b0;
                    TA_DIS        <= 1'b0;
                    FLIP_WORD     <= 1'b0;
                end
                CYCLE_STATE <= CYCLE1_TERM;
            end
            CYCLE1_TERM : begin
                if (!TACKn) begin
                    if (PORT_MISMATCH) begin
                        UU_LATCHED  <= UU_AMIGA_IN;
                        UM_LATCHED  <= UM_AMIGA_IN;
                        CYCLE_STATE <= CYCLE2_STRT;
                    end else begin
                        if (!BURST || !TBIn || (BURST_COUNT == 2'h3)) begin
                            BURST_COUNT <= 2'h0;
                            CYCLE_STATE <= IDLE;
                        end else begin
                            BURST_COUNT <= BURST_COUNT + 1;
                        end
                    end
                end
            end
            CYCLE2_STRT : begin
                LATCH_EN <= READ_CYCLE_ACTIVE;
                A2_EN <= 1'b1;
                TS_EN <= 1'b1;
                TA_DIS <= 1'b0;
                FLIP_WORD <= 1'b1;
                CYCLE_STATE <= CYCLE2_TERM;
            end
            CYCLE2_TERM : begin
                TS_EN <= 1'b0;
                if (!TACKn) begin
                    CYCLE_STATE <= IDLE;
                end
            end
        endcase
    end
end

endmodule
