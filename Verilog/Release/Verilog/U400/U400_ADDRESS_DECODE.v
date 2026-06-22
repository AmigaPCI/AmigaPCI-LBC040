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
Module Name: U400_ADDRESS_DECODE
Project Name: AmigaPCI Local Bus Card
Target Devices: iCE40-HX1K-VQ100

Description: ADDRESS DECODE FOR MOTHERBOARD MEMORY SPACE.

Revision History:
    22-JUN-2026 : Initial Rev 6.x Release

GitHub: https://github.com/jasonsbeer/AmigaPCI
*/

module U400_ADDRESS_DECODE (

    input RESETn,
    input [31:27] A,
    //input [31:21] A,
    output RAM_SPACE

);

//MOTHERBOARD FAST RAM IS HARD CODED AT ADDRESS RANGE $0400 0000 TO $07FF FFFF (64MB).
//COPROCESSOR SLOT RAM EXPANSION IS HARD CODED AT ADDRESS RANGE $0800 0000 - $0FFF FFFF (128MB).
//THIS IS NOT PART OF THE AUTOCONFIG SPACE.

//assign RAM_SPACE = RESETn && A == 6'b000001; //Motherboard RAM.

assign RAM_SPACE = RESETn && A[31:27] == 5'b0000_1; //Coprocessor slot RAM. 128MB
//assign RAM_SPACE = RESETn && A[31:26] == 6'b0000_10; //64MB
//assign RAM_SPACE = RESETn && A[31:25] == 7'b0000_100; //32MB
//assign RAM_SPACE = RESETn && A[31:24] == 8'b0000_1000; //16MB
//assign RAM_SPACE = RESETn && A[31:23] == 9'b0000_1000_0; //8MB
//assign RAM_SPACE = RESETn && A[31:22] == 10'b0000_1000_00; //4MB
//assign RAM_SPACE = RESETn && A[31:21] == 11'b0000_1000_000; //2MB
endmodule