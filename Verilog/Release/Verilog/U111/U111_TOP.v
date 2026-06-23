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
Module Name: U111_TOP
Project Name: AmigaPCI
Target Devices: iCE40-HX4K-TQ144

Description: U111 AMIGA PCI LOCAL BUS CARD BUS SIZING FPGA

See individual modules for revision history.

GitHub: https://github.com/jasonsbeer/AmigaPCI

iceprog D:\LocalBus68040\U111\U111_icecube\U111_icecube_Implmnt\sbt\outputs\bitmap\U111_TOP_bitmap.bin
*/

module U111_TOP (
    input A_040,
    input [1:0] SIZ,
    input CLK80_IN, RESETn, RnW, BGn, BBn, PORTSIZE, LBENn, TBIn, TCIn, TSn_CPU,

    output A_AMIGA,
    output CLK40A, CLK40B, CLK40C, CLK80_OUT, CLKRAMA, CLKRAMB,
    output TBI_CPUn, TCI_CPUn, TEA_CPUn, CPUBGn, BUFENn, BUFDIR, DMAAn, TSn_RAM,

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

///////////////////////////////
// BUS AND PROCESSOR CLOCKS //
/////////////////////////////

//Clock distribution.
wire CLK40;

wire   PCLK_PAD  = CLK80_IN;
assign CLK40A    = CLK40;
assign CLK40B    = CLK40;
assign CLK40C    = CLK40;

//assign CLKRAMA   = CLK40;
assign CLKRAMA   = CLK80_OUT; //80MHz

//assign CLKRAMB   = CLK40;
assign CLKRAMB   = CLK80_OUT; //80MHz

////////////////
// BUS OWNER //
//////////////

 //Identfiy when the CPU is actively using the bus.
reg CPU_BUS;
always @(posedge CLK40) begin
    if (!RESETn) begin
        CPU_BUS <= 1;
    end else begin
        if (!BGn) begin
            CPU_BUS <= 1;
        end else if (BBn) begin
            CPU_BUS <= 0;
        end
    end
end

//////////////
// BUFFERS //
////////////

U111_BUFFERS U111_BUFFERS (
    //INPUTS
    .RnW (RnW),
    .LBENn (LBENn),
    .CPU_BUS (CPU_BUS),

    //OUTPUTS
    .CPUBGn (CPUBGn),
    .BUFENn (BUFENn),
    .BUFDIR (BUFDIR),
    .DMAAn (DMAAn)
);

//////////////////////////////////
// DATA TRANSFER STATE MACHINE //
////////////////////////////////

U111_CYCLE_SM U111_CYCLE_SM (
    //INPUTS
    .CLK40 (CLK40),
    .RESETn (RESETn),
    .TSn_CPU (TSn_CPU),
    .RnW (RnW),
    .PORTSIZE (PORTSIZE),
    .TACKn (TACKn),
    .BGn (BGn),
    .LBENn (LBENn),
    .TBIn (TBIn),
    .TCIn (TCIn),
    .CPU_BUS (CPU_BUS),
    .SIZ (SIZ),
    .A_040 (A_040),

    //OUTPUTS
    .TAn (TAn),
    .TBI_CPUn (TBI_CPUn),
    .TCI_CPUn (TCI_CPUn),
    .TEA_CPUn (TEA_CPUn),
    .A_AMIGA (A_AMIGA),
    .TSn (TSn),
    .TSn_RAM (TSn_RAM),

    //INOUT
    .D_UU_040 (D_UU_040),
    .D_UM_040 (D_UM_040),
    .D_LM_040 (D_LM_040),
    .D_LL_040 (D_LL_040),
    .D_UU_AMIGA (D_UU_AMIGA),
    .D_UM_AMIGA (D_UM_AMIGA),
    .D_LM_AMIGA (D_LM_AMIGA),
    .D_LL_AMIGA (D_LL_AMIGA)

    //,.TP0 (TP0)
    ,.CACHE_EN (CACHE_EN)
);

//////////
// PLL //
////////

//THIS IS FOR A 80MHz INPUT CLOCK
U111_PCLK U111_PCLK     (.PACKAGEPIN(PCLK_PAD),
                         .PLLOUTCOREA(),
                         .PLLOUTCOREB(),
                         .PLLOUTGLOBALA(CLK80_OUT),
                         .PLLOUTGLOBALB(CLK40),
                         .RESET(1'b1));

//THIS IS FOR A 40MHz INPUT CLOCK
/*SB_PLL40_2F_PAD #(
    .DIVR (4'b0000),
    .DIVF (7'b0001111),
    .DIVQ (3'b011),
    .FILTER_RANGE (3'b011),
    .FEEDBACK_PATH ("SIMPLE"),
    .PLLOUT_SELECT_PORTA ("GENCLK"),
    .PLLOUT_SELECT_PORTB ("GENCLK_HALF")
) pll (
    .LOCK           (),
    .RESETB         (1'b1),
    .PACKAGEPIN     (PCLK_PAD),
    .PLLOUTGLOBALA  (CLK80),
    .PLLOUTGLOBALB  (CLK40),

    .EXTFEEDBACK       (1'b0),
    .DYNAMICDELAY      (8'b00000000),
    .BYPASS            (1'b0),
    .SDI               (1'b0),
    .SCLK              (1'b0),
    .LATCHINPUTVALUE   (1'b0)
);*/

endmodule
