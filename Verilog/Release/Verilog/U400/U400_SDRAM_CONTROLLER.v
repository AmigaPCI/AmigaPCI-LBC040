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
Module Name: U400_SDRAM
Project Name: AmigaPCI Local Bus Card
Target Devices: iCE40-HX1K-VQ100

Description: SDRAM CONTROLLER.

Revision History:
    22-JUN-2026 : Initial Rev 6.x Release

GitHub: https://github.com/jasonsbeer/AmigaPCI
*/

module U400_SDRAM_CONTROLLER (

    input CLK80, CLK40, RESETn, TSn, RAM_SPACE, RnW,
    input [26:0] A,
    input [1:0] SIZ,

    output TAn,
    output CS0n,
    output CS1n,
    output reg CLK_EN,
    output RASn,
    output CASn,
    output WEn,
    output [12:0] MA,
    output BANK0,
    output BANK1,
    output UUBEn, UMBEn, LMBEn, LLBEn

    ,output TP

);

assign TP = RAM_CYCLE_START;

//////////////////
// CYCLE START //
////////////////

//Capture the start of a RAM cycle.
wire RAM_RST = (RAM_CYCLE_ACK || !RESETn);
reg RAM_CYCLE_START;
always @(posedge CLK40, posedge RAM_RST) begin
    if (RAM_RST) begin
        RAM_CYCLE_START <= 0;
    end else begin
        RAM_CYCLE_START <= RAM_CYCLE_START ? 1'b1 : (!TSn && RAM_SPACE);
    end
end

///////////////////////
// SDRAM CONTROLLER //
/////////////////////

//THE SDRAM COMMAND CONSTANTS ARE: _RAS, _CAS, _WE
localparam [2:0]  NOP             = 3'b111;
localparam [2:0]  BURST_STOP      = 3'b110;
localparam [2:0]  PRECHARGE       = 3'b010;
localparam [2:0]  BANKACTIVATE    = 3'b011;
localparam [2:0]  READ            = 3'b101;
localparam [2:0]  WRITE           = 3'b100;
localparam [2:0]  AUTOREFRESH     = 3'b001;
localparam [2:0]  MODEREGISTER    = 3'b000;
localparam [11:0] REFRESH_DEFAULT = 12'h258; //600 clocks.

//--- Fixed Command Addresses ---
localparam [12:0] ADD_PRECHARGE = 13'b0010000000000;
localparam [12:0] CMD_REGISTER  = 13'b000_1_00_010_0_000;

//--- State machine states. ---
localparam [3:0] CONFIG_PRECH = 4'h0;
localparam [3:0] CONFIG_REFR1 = 4'h1;
localparam [3:0] CONFIG_REFR2 = 4'h2;
localparam [3:0] CONFIG_REGST = 4'h3;
localparam [3:0] CONFIG_END   = 4'h4;
localparam [3:0] REFRESH_STRT = 4'h5;
localparam [3:0] REFRESH_WAT1 = 4'h6;
localparam [3:0] REFRESH_WAT2 = 4'h7;
localparam [3:0] REFRESH_WAT3 = 4'h8;
localparam [3:0] REFRESH_END  = 4'h9;
localparam [3:0] SDRAM_IDLE   = 4'ha;
localparam [3:0] SDRAM_BNKACT = 4'hb;
localparam [3:0] SDRAM_CAS    = 4'hc;
localparam [3:0] SDRAM_STD    = 4'hd;
//localparam [3:0] SDRAM_STD_LT = 4'he;

//--- Helper signals. ---
wire BURST     = (SIZ[1] &&  SIZ[0]);
wire LONG_WORD = (SIZ[1] ==  SIZ[0]);
wire SHRT_WORD = (SIZ[1] && !SIZ[0]);

//--- The SDRAM command signals. ---
assign BANK0 = A[24];
assign BANK1 = A[25];
assign CS1n  = ((CS_EN &&  A[26]) || CS_EN_PROGRAM) ? 1'b0 : 1'b1; 
assign CS0n  = ((CS_EN && !A[26]) || CS_EN_PROGRAM) ? 1'b0 : 1'b1; 
assign RASn  = CMD_OUT[2];
assign CASn  = CMD_OUT[1];
assign WEn   = CMD_OUT[0];
assign MA    = MA_OUT;
assign UUBEn = DQ_EN ? ~((A[1:0] == 2'b00) || LONG_WORD) : 1'b1;
assign UMBEn = DQ_EN ? ~((A[1:0] == 2'b01) || (SHRT_WORD && !A[1]) || LONG_WORD) : 1'b1;
assign LMBEn = DQ_EN ? ~((A[1:0] == 2'b10) || LONG_WORD) : 1'b1;
assign LLBEn = DQ_EN ? ~((A[1:0] == 2'b11) || (SHRT_WORD &&  A[1]) || LONG_WORD) : 1'b1;

//--- The state machine. ---
reg CS_EN;
reg CS_EN_PROGRAM;
reg SDRAM_CONFIGURED;
reg CONFIG_REFRESH_COUNT;
reg SDRAM_TACK;
reg RAM_CYCLE_ACK;
reg DQ_EN;
//reg RAM_CYCLE_ACTIVE;
reg [3:0] SDRAM_STATE;
reg [2:0] CMD_OUT;
reg [12:0] MA_OUT;
reg [11:0] REFRESH_COUNT;
reg [1:0] RAM_CYCLE_START_SYNC;
reg [1:0] TACK_EN_SYNC;

always @(posedge CLK80) begin
    if (!RESETn) begin
        //RAM_CYCLE_ACTIVE <= 1'b1;
        RAM_CYCLE_ACK <= 1'b0;
        SDRAM_TACK <= 1'b0;
        CS_EN <= 1'b0;
        CS_EN_PROGRAM <= 1'b0;
        CMD_OUT <= NOP;
        CLK_EN  <= 1'b1;
        DQ_EN   <= 1'b0;
        SDRAM_STATE <= CONFIG_PRECH;
        CONFIG_REFRESH_COUNT <= 1'b0;
        REFRESH_COUNT <= 12'b0;
        SDRAM_CONFIGURED <= 1'b0;
        MA_OUT <= 13'b0;
        RAM_CYCLE_START_SYNC <= 2'b0;
    end else begin

        //--- Incement the refresh counter each clock. ---
        REFRESH_COUNT <= REFRESH_COUNT + 1;

        //Syncronize the start signal from the 40MHz domain.
        RAM_CYCLE_START_SYNC <= {RAM_CYCLE_START_SYNC[0], RAM_CYCLE_START};

        //Synchronize the cycle terminatin signal from the 40MHz domain.
        TACK_EN_SYNC <= {TACK_EN_SYNC[0], TACK_EN};

        //--- SDRAM command signal defaults. ---
        CS_EN <= 1'b0;
        CS_EN_PROGRAM <= 1'b0;
        CMD_OUT <= NOP;
        CLK_EN  <= 1'b1;
        DQ_EN   <= 1'b0;
        RAM_CYCLE_ACK <= 1'b0;

        //--- The SDRAM state machine. ---
        case (SDRAM_STATE)

            //--- Configuration cycle. ---
            //--- Executes first after each reset. ---
            CONFIG_PRECH : begin
                CS_EN_PROGRAM <= 1'b1;
                CMD_OUT <= PRECHARGE; //Wait 20ns to first refresh.
                MA_OUT  <= ADD_PRECHARGE;
                SDRAM_STATE <= CONFIG_REFR1;
            end
            CONFIG_REFR1 : begin
                SDRAM_STATE <= REFRESH_STRT;
            end
            CONFIG_REFR2 : begin
                CONFIG_REFRESH_COUNT <= 1'b1;
                SDRAM_STATE <= REFRESH_STRT;
            end
            CONFIG_REGST : begin
                CS_EN_PROGRAM <= 1'b1;
                MA_OUT <= CMD_REGISTER;
                CMD_OUT <= MODEREGISTER;
                SDRAM_STATE <= CONFIG_END;
            end
            CONFIG_END : begin
                SDRAM_CONFIGURED <= 1'b1;
                SDRAM_STATE <= SDRAM_IDLE;
            end

            //--- Refresh cycle. ---
            //--- We must refresh at least once every 7812ns. ---
            //--- We currently refresh once every 7562ns. ---
            REFRESH_STRT : begin
                CS_EN_PROGRAM <= 1'b1;
                CMD_OUT <= AUTOREFRESH; //Wait 63ns before next command
                SDRAM_STATE <= REFRESH_WAT1;
            end
            REFRESH_WAT1 : begin
                SDRAM_STATE <= REFRESH_WAT2;
            end
            REFRESH_WAT2 : begin
                SDRAM_STATE <= REFRESH_WAT3;
            end
            REFRESH_WAT3 : begin
                REFRESH_COUNT <= 12'b0;
                SDRAM_STATE <= REFRESH_END;
            end
            REFRESH_END : begin //62.5ns
                if (SDRAM_CONFIGURED) begin
                    SDRAM_STATE <= SDRAM_IDLE;
                end else begin
                    if (CONFIG_REFRESH_COUNT) begin
                        SDRAM_STATE <= CONFIG_REGST;
                    end else begin
                        SDRAM_STATE <= CONFIG_REFR2;
                    end
                end
            end

            //--- Idle state. ---
            SDRAM_IDLE : begin
                if (REFRESH_COUNT > REFRESH_DEFAULT) begin
                    SDRAM_STATE <= REFRESH_STRT;
                //end else if (RAM_CYCLE_START) begin
                end else if (RAM_CYCLE_START_SYNC[1] || RAM_CYCLE_START_SYNC[0]) begin
                    CS_EN <= 1'b1;
                    CMD_OUT <= BANKACTIVATE;
                    MA_OUT  <= A[23:11]; //SDRAM A[12:0]
                    SDRAM_STATE <= SDRAM_BNKACT;
                    SDRAM_TACK <= RnW ? 1'b0 : 1'b1;
                end
            end

            //--- Common to all SDRAM cycles. ---
            SDRAM_BNKACT : begin
                RAM_CYCLE_ACK <= 1'b1;
                SDRAM_STATE <= SDRAM_CAS;
            end
            SDRAM_CAS : begin
                CS_EN <= 1'b1;
                DQ_EN   <= 1'b1;
                MA_OUT  <= {4'b0010, A[10:2]}; //SDRAM A[8:0] w/auto precharge.
                CMD_OUT <= RnW ? READ : WRITE;
                //SDRAM_STATE   <= BURST ? SDRAM_BURST : SDRAM_STD;
                SDRAM_STATE <= SDRAM_STD;
                SDRAM_TACK <= 1'b1;
            end

            //--- Non-burst cycle process. ---
            SDRAM_STD : begin             
                if (TACK_EN_SYNC[1] || TACK_EN_SYNC[0]) begin
                    SDRAM_STATE <= SDRAM_IDLE;
                    SDRAM_TACK <= 1'b0;
                end else begin
                    SDRAM_TACK <= 1'b1;
                    CLK_EN <= RnW ? 1'b0 : 1'b1;
                end
            end

            //--- Burst cycle process. ---
            //To be done.

        endcase
    end
end

////////////////////////
// CYCLE TERMINATION //
//////////////////////

localparam [3:0] TACK_STATE_IDLE = 4'h0;
localparam [3:0] TACK_STATE_NEG  = 4'h1;
localparam [3:0] TACK_STATE_END  = 4'h2;

assign TAn = (SDRAM_TACK || TACK_EN) ? TACK_OUT : 1'bz;

reg TACK_EN;
reg TACK_OUT;
reg [3:0] TACK_STATE;
always @(posedge CLK40) begin
    if (!RESETn) begin
        TACK_EN <= 1'b0;
        TACK_STATE <= TACK_STATE_IDLE;
        TACK_OUT <= 1'b1;
    end else begin
        case (TACK_STATE)
            TACK_STATE_IDLE : begin
                if (SDRAM_TACK) begin
                    TACK_OUT <= 1'b0;
                    TACK_EN  <= 1'b1;
                    TACK_STATE <= TACK_STATE_NEG;
                end
            end
            TACK_STATE_NEG : begin
                TACK_OUT <= 1'b1;
                TACK_STATE <= TACK_STATE_END;
            end
            TACK_STATE_END : begin
                TACK_EN <= 1'b0;
                TACK_STATE <= TACK_STATE_IDLE;
            end
        endcase
    end
end

endmodule