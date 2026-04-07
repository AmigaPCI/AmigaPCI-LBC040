module U111_PCLK(PACKAGEPIN,
                 PLLOUTCOREA,
                 PLLOUTCOREB,
                 PLLOUTGLOBALA,
                 PLLOUTGLOBALB,
                 RESET);

inout PACKAGEPIN;
input RESET;    /* To initialize the simulation properly, the RESET signal (Active Low) must be asserted at the beginning of the simulation */ 
output PLLOUTCOREA;
output PLLOUTCOREB;
output PLLOUTGLOBALA;
output PLLOUTGLOBALB;

SB_PLL40_2F_PAD U111_PCLK_inst(.PACKAGEPIN(PACKAGEPIN),
                               .PLLOUTCOREA(PLLOUTCOREA),
                               .PLLOUTCOREB(PLLOUTCOREB),
                               .PLLOUTGLOBALA(PLLOUTGLOBALA),
                               .PLLOUTGLOBALB(PLLOUTGLOBALB),
                               .EXTFEEDBACK(),
                               .DYNAMICDELAY(),
                               .RESETB(RESET),
                               .BYPASS(1'b0),
                               .LATCHINPUTVALUE(),
                               .LOCK(),
                               .SDI(),
                               .SDO(),
                               .SCLK());

//\\ Fin=80, Fout=80;
defparam U111_PCLK_inst.DIVR = 4'b0000;
defparam U111_PCLK_inst.DIVF = 7'b0000111;
defparam U111_PCLK_inst.DIVQ = 3'b011;
defparam U111_PCLK_inst.FILTER_RANGE = 3'b101;
defparam U111_PCLK_inst.FEEDBACK_PATH = "SIMPLE";
defparam U111_PCLK_inst.DELAY_ADJUSTMENT_MODE_FEEDBACK = "FIXED";
defparam U111_PCLK_inst.FDA_FEEDBACK = 4'b0000;
defparam U111_PCLK_inst.DELAY_ADJUSTMENT_MODE_RELATIVE = "FIXED";
defparam U111_PCLK_inst.FDA_RELATIVE = 4'b0000;
defparam U111_PCLK_inst.SHIFTREG_DIV_MODE = 2'b00;
defparam U111_PCLK_inst.PLLOUT_SELECT_PORTA = "GENCLK";
defparam U111_PCLK_inst.PLLOUT_SELECT_PORTB = "GENCLK_HALF";
defparam U111_PCLK_inst.ENABLE_ICEGATE_PORTA = 1'b0;
defparam U111_PCLK_inst.ENABLE_ICEGATE_PORTB = 1'b0;

endmodule
