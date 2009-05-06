// Copyright 2006, 2007 Dennis van Weeren
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
//
// This is Agnus 
// The copper, blitter and sprite dma have a reqdma output and an ackdma input
// if they are ready for dma they do a dma request by asserting reqdma
// the dma priority logic circuit then checks which module is granted access by 
// looking at their priorities and asserting the ackdma signal of the module that
// has the highest priority
//
// Other dma channels (bitplane, audio and disk) only have an enable input (bitplane)
// or only a dma request input from Paula (dmal input, disk and audio) 
// and an dma output to indicate that they are using their slot.
// this is because they have the highest priority in the system and cannot be hold up
//
// The bus clock runs at 7.09MHz which is twice as fast as in the original amiga and
// the same as the pixel clock / horizontal beam counter.
//
// general cycle allocation is as follows:
// (lowest 2 bits of horizontal beam counter)
//
// slot 0:	68000 (priority in that order, extra slots because of higher bus speed)
// slot 1:	disk, bitplanes, copper, blitter and 68000 (priority in that order)   	
// slot 2:	blitter and 68000 (priority in that order, extra slots because of higher bus speed)
// slot 3:	disk, bitplanes, sprites, audio and 68000 (priority in that order)
//
// because only the odd slots are used by the chipset, the chipset runs at the same 
// virtual speed as the original. The cpu gets the extra even slots allowing for
// faster cpu's without the need for an extra fastram controller
// Blitter timing is not completely accurate, it uses slot 1 and 2 instead of 1 and 3, this is to let
// the blitter not slow down too much dma contention. (most compatible solution for now)
// Blitter nasty mode activates the buspri signal to indicate to gary to stop access to the chipram/chipregisters.
// Blitter nasty mode is only activated if blitter activates bltpri cause it depends on blitter settings if blitter
// will really block the cpu.
//
// 19-03-2005		-first serious version
//				-added clock generator
// 20-03-2005		-fixed regaddress idle state
// 				-more reliable 3-state timing
// 27-03-2005		-fixed bug in regadress generator, adress was not set to idle if
//				 chip bus was idle (hwr,lwr and rd low)
// 10-04-2005		-added real clock generator
// 11-04-2005		-removed rd,hwr and lwr signals due to change in address decoder
// 24-04-2005		-adapted to new 7.09 MHz bus clock
// 				-added more complete dmaslot controller
// 25-04-2005		-continued work on beam counters
// 26-04-2005		-continued work on beam counters
// 02-05-2005		-moved beam counter to seperate module
//				-done work on bitplane dma engine
// 05-05-2005		-completed first version of bitplane dma engine (will it work ?)
//				-adapted code for bitplane dma engine
// 15-05-2005		-added horbeam reset output and start of vertical blank interrupt output
//				-fixed small bug in bpldma_engine
//				-changed horizontal sync/blank timing so image is centered on screen
//				-made some changes to interlaced vertical sync timing
//17-05-2005		-fixed bug in bpldma_engine, modulo was not added right
//18-05-2005		-fixed hires bitplane data fetch
//				-interlaced is now selected through bplcon0
//22-05-2005		-changed name of diwstrt/stop to vdiwstrt/stop to make code clearer
//29-05-2005		-added copper but its needs some more work to be integrated properly
//31-05-2005		-added support for negative modulo in bitplane dma engine
//				-integrated copper better
//06-06-2005		-started coding of sprite dma engine
//				-cleaned up code a bit (comments, spaces between lines and so on)
//07-06-2005		-done work on sprite dma engine
//08-06-2005		-done more work on sprite dma engine
//12-06-2005		-first finished version of sprite dma engine
//				-integrated sprite dma engine into agnus
//28-06-2005		-delayed horizontal sync/blanking by 2 low res pixels to compensate
//				 for pipelining delay in Denise
//19-07-2005		-changed phase of cpu clock in an attempt to solve kickstart boot problem
//20-07-2005		-changed phase of cpu clock back again, it was not the problem..
//31-07-2005		-fixed bbusy to 1 as it is not yet implemented
//07-08-2005		-added ersy bit, if enabled the beamcounters stop counting
//				-bit 11 and 12 of dmacon are now also implemented
//04-09-2005		-added blitter finished interrupt
//				-added blitter
//05-09-2005		-did some dma cycle allocation testing
//11-09-2005		-testing
//18-09-2005		-removed ersy support, this seems to cure part of the kickstart 1.2 problems
//20-09-2005		-testing
//21-09-2005		-added copper disable input for testing
//23-09-2005		-moved VPOSR/VHPOSR handling to beamcounter module
//				-added VPOS/VHPOSW registers
//19-10-2005		-removed burst clock and cck (color clock enable) outputs
//				-removed hcres,vertb and intb outputs
//				-added sol,sof and int3 outputs
//				-adapted code to use new signals
//23-10-2005		-added dmal signal
//				-added disk dma engine
//21-10-2005		-fixed bug in disk dma engine, DSKDATR and DSKDAT addresses were swapped
//04-12-2005		-added magic mystery logic to handle ddfstrt/ddfstop
//14-12-2005		-fixed some sensitivity lists
//21-12-2005		-added rd,hwr and lwr inputs
//				-added bus,buswr and buspri outputs
//26-12-2005		-fixed buspri output
//				-changed blitter nasty mode altogether, it is now not according to the HRM,
//				 but at least this solution seems to work for most games/demos
//27-12-2005		-added audio dma engine
//28-12-2005		-fixed audio dma engine
//29-12-2005		-rewritten audio dma engine
//03-01-2006		-added dmas to avoid interference with copper cycles
//07-01-2006		-also added dmas to disk dma engine
//11-01-2006		-removed ability to write beam counters
//22-01-2006		-removed composite sync output
//				-added ddfstrt/ddfstop HW limits
//23-01-2006		-added fastblitter enable input
//25-01-2006		-improved blitter nasty timing
//14-02-2006		-again improved blitter timing, this seems the most compatible solution for now..
//19-02-2006		-again improved blitter timing, this is an even more compatible solution

//JB:
//2008-07-17		- modified display dma engine to be more compatible
//					- moved beamcounters to separate module
//					- heavily modified sprite dma engine
// 2008-10-18		- fast blitter mode
// 2009-01-08		- added audio_dmal, audio_dmas
//


module Agnus
(
	output	[2:0] test,
	input 	clk,					//clock
	input	clk28m,					//28MHz clock
	output	cck,					//colour clock enable, active whenever hpos[0] is high (odd dma slots used by chipset)
	input	reset,					//reset
	input 	aen,					//bus adress enable (register bank)
	input	rd,						//bus read
	input	hwr,					//bus high write
	input	lwr,					//bus low write
	input	[15:0] datain,			//data bus in
	output	[15:0] dataout,			//data bus out
	input 	[8:1] addressin,		//256 words (512 bytes) adress input,
	output	reg [20:1] addressout,	//chip address output,
	output 	reg [8:1] regaddress,	//256 words (512 bytes) register address out,
	output	reg bus,				//agnus needs bus
	output	reg buswr,				//agnus does a write cycle
	output	buspri,					//agnus blitter has priority in chipram
	output	_hsync,					//horizontal sync
	output	_vsync,					//vertical sync
	output	_csync,					//composite sync
	output	blank,					//video blanking
	output	sol,					//start of video line (active during last pixel of previous line) 
	output	sof,					//start of video frame (active during last pixel of previous frame)
	output	strhor_denise,			//horizontal strobe for Denise (due to not cycle exact implementation of Denise it must be delayed by one CCK)
	output	strhor_paula,			//horizontal strobe for Paula 
	output	[8:0] htotal,			//video line length
	output	int3,					//blitter finished interrupt (to Paula)
	input	[3:0] audio_dmal,		//audio dma data transfer request (from Paula)
	input	[3:0] audio_dmas,		//audio dma location pointer restart (from Paula)
	input	disk_dmal,				//disk dma data transfer request (from Paula)
	input	disk_dmas,				//disk dma special request (from Paula)
	input	bls,					//blitter slowdown
	input	ntsc,					//chip is NTSC
	input	floppy_speed,			//allocates refresh slots for disk DMA
	input	fastblitter				//alows blitter to take extra DMA slots 
);

//register names and adresses		
parameter DMACON  = 9'h096;
parameter DMACONR = 9'h002;
parameter DIWSTRT = 9'h08e;
parameter DIWSTOP = 9'h090;

//local signals
reg		[15:0] dmaconr;			//dma control read register

wire	[8:0] hpos;				//alternative horizontal beam counter
//wire	[10:0] verbeam;			//vertical beam counter
wire	[10:0] vpos;			//vertical beam counter

wire	vbl;					///JB: vertical blanking
wire	vblend;					///JB: last line of vertical blanking

wire	bbusy;					//blitter busy status
wire	bzero;					//blitter zero status
wire	bblck;					//blitter blocks cpu
wire	bltpri;					//blitter nasty
wire	bplen;					//bitplane dma enable
wire	copen;					//copper dma enable
wire	blten;					//blitter dma enable
wire	spren;					//sprite dma enable

reg		[15:8] vdiwstrt;		//vertical window start position
reg		[15:8] vdiwstop;		//vertical window stop position

wire	dma_ref;				//refresh dma slots
wire	dma_bpl;				//bitplane dma engine uses it's slot
wire	dma_dsk;				//disk dma uses it's slot
wire	dma_aud;				//audio dma uses it's slot
reg		ack_cop;				//copper dma acknowledge
wire	req_cop; 				//copper dma request
reg		ack_blt;				//blitter dma acknowledge
wire	req_blt; 				//blitter dma request
reg		ack_spr;				//sprite dma acknowledge
wire	req_spr; 				//sprite dma request
wire	[15:0] data_bmc;		//beam counter data out
wire	[20:1] address_dsk;		//disk dma engine chip address out
wire	[8:1] regaddress_dsk; 	//disk dma engine register address out
wire	wr_dsk;					//disk dma engine write enable out
wire	[20:1] address_aud;		//audio dma engine chip address out
wire	[8:1] regaddress_aud; 	//audio dma engine register address out
wire	[20:1] address_bpl;		//bitplane dma engine chip address out
wire	[8:1] regaddress_bpl; 	//bitplane dma engine register address out
wire	[20:1] address_spr;		//sprite dma engine chip address out
wire	[8:1] regaddress_spr; 	//sprite dma engine register address out
wire	[20:1] address_cop;		//copper dma engine chip address out
wire	[8:1] regaddress_cop; 	//copper dma engine register address out
wire	[20:1] address_blt;		//blitter dma engine chip address out
wire	[15:0] data_blt;		//blitter dma engine data out
wire	wr_blt;					//blitter dma engine write enable out
wire	[8:1] regaddress_cpu;	//cpu register address


reg		[1:0] bls_cnt;			//blitter slowdown counter, counts memory cycles when the CPU misses the bus

parameter BLS_CNT_MAX = 3;		//when CPU misses the bus for 3 consecutive memory cycles the blitter is blocked until CPU accesses the bus

assign test = {sof,bbusy,1'b0};


//--------------------------------------------------------------------------------------

//data out multiplexer
assign dataout = data_bmc | dmaconr | data_blt;

//cpu address decoder
assign regaddress_cpu = (aen&(rd|hwr|lwr)) ? addressin : 8'hff;

//blitter nasty mode output (blocks cpu)
//(when blitter dma is active AND blitter nasty mode is on AND blitter indicates to block cpu)
//(also when fastchip is false, all even cycles are also blocked giving A500 chipram speed)
assign buspri = (blten & bltpri & bblck);

//assign buspri = blten & bltpri & bblck;
assign cck = hpos[0];

//--------------------------------------------------------------------------------------

//chip address, register address and control signal multiplexer
//AND dma priority handler
//first item in this if else if list has highest priority
always @(dma_dsk or dma_ref or address_dsk or regaddress_dsk or wr_dsk or
		dma_aud or address_aud or regaddress_aud or
		dma_bpl or address_bpl or regaddress_bpl or req_cop or 
		copen or address_cop or regaddress_cop or regaddress_cpu
		or spren or req_spr or address_spr or regaddress_spr
		or blten or req_blt or address_blt or wr_blt or bls_cnt)
begin
	if (dma_dsk)//busses allocated to disk dma engine
	begin
		bus = 1;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 0;
		addressout = address_dsk;
		regaddress = regaddress_dsk;
		buswr = wr_dsk;
	end
	else if (dma_ref) //bus allocated to refresh dma engine
	begin
		bus = 1;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 0;
		addressout = 0;
		regaddress = 8'hFF;
		buswr = 0;
	end
	else if (dma_aud)//busses allocated to audio dma engine
	begin
		bus = 1;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 0;
		addressout = address_aud;
		regaddress = regaddress_aud;
		buswr = 0;
	end
	else if (dma_bpl)//busses allocated to bitplane dma engine
	begin
		bus = 1;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 0;
		addressout = address_bpl;
		regaddress = regaddress_bpl;
		buswr = 0;
	end
	else if (req_spr && spren)//busses allocated to sprite dma engine
	begin
		bus = 1;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 1;
		addressout = address_spr;
		regaddress = regaddress_spr;
		buswr = 0;
	end
	else if (req_cop && copen)//busses allocated to copper
	begin
		bus = 1;
		ack_cop = 1;
		ack_blt = 0;
		ack_spr = 0;
		addressout = address_cop;
		regaddress = regaddress_cop;
		buswr = 0;
	end
	else if (req_blt && blten && bls_cnt!=BLS_CNT_MAX)//busses allocated to blitter
	begin
		bus = 1;
		ack_cop = 0;
		ack_blt = 1;
		ack_spr = 0;
		addressout = address_blt;
		regaddress = 8'hff;
		buswr = wr_blt;
	end
	else//busses not allocated by agnus
	begin
		bus = 0;
		ack_cop = 0;
		ack_blt = 0;
		ack_spr = 0;
		addressout = 0;
		regaddress = regaddress_cpu;//pass register addresses from cpu address bus
		buswr = 0;
	end
end

//--------------------------------------------------------------------------------------

reg	[12:0]dmacon;

//dma control register read
always @(regaddress or bbusy or bzero or dmacon)
	if (regaddress[8:1]==DMACONR[8:1])
		dmaconr[15:0] <= {1'b0,bbusy,bzero,dmacon[12:0]};
	else
		dmaconr <= 0;

//dma control register write
always @(posedge clk)
	if (reset)
		dmacon <= 0;
	else if (regaddress[8:1]==DMACON[8:1])
	begin
		if (datain[15])
			dmacon[12:0] <= dmacon[12:0]|datain[12:0];
		else
			dmacon[12:0] <= dmacon[12:0]&(~datain[12:0]);	
	end

//assign dma enable bits
assign	bltpri = dmacon[10];
assign	bplen = dmacon[8]&dmacon[9];
assign	copen = dmacon[7]&dmacon[9];
assign	blten = dmacon[6]&dmacon[9];
assign	spren = dmacon[5]&dmacon[9];
										
//--------------------------------------------------------------------------------------

//write diwstart and diwstop registers
always @(posedge clk)
	if (regaddress[8:1]==DIWSTRT[8:1])
		vdiwstrt[15:8] <= datain[15:8];
always @(posedge clk)
	if (regaddress[8:1]==DIWSTOP[8:1])
		vdiwstop[15:8] <= datain[15:8];

//--------------------------------------------------------------------------------------

refresh ref1
(
	.hpos(hpos),
	.dma(dma_ref)
);

//instantiate disk dma engine
dskdma_engine dsk1
(
	.clk(clk),
	.dma(dma_dsk),
	.dmal(disk_dmal),
	.dmas(disk_dmas),
	.speed(floppy_speed),
	.hpos(hpos),
	.wr(wr_dsk),
	.regaddressin(regaddress),
	.regaddressout(regaddress_dsk),
	.datain(datain),
	.addressout(address_dsk)	
);

//--------------------------------------------------------------------------------------

//instantiate audio dma engine
auddma_engine aud1
(
	.clk(clk),
	.dma(dma_aud),
	.audio_dmal(audio_dmal),
	.audio_dmas(audio_dmas),
	.hpos(hpos),
	.regaddressin(regaddress),
	.regaddressout(regaddress_aud),
	.datain(datain),
	.addressout(address_aud)
);

//--------------------------------------------------------------------------------------

//instantiate bitplane dma
// display data fetches can take place during blanking (when vdiestrt is set to 0 the display is distorted)
// diw vstop/vstart conditiotions are continuously checked
// first visible line $1A
// vstop forced by vbl
// last visible line is displayed in colour 0
// vdiwstop = N (M>N)
// wait vpos N-1 hpos $d7, move vdiwstop M : efffective 
// wait vpos N-1 hpos $d9, move vdiwstop M : non efffective 

// display non active
// wait vpos N hpos $dd, move vdiwstrt N : display starts
// wait vpos N hpos $df, move vdiwstrt N : display doesn't start

// if vdiwstrt==vdiwstop : no display
// if vdiwstrt>vdiwstop : display from vdiwstrt till screen bottom 

// display dma can be started in the middle of a scanline by setting vdiwstrt to the current line number
// display dma can be stopped in the middle of a scanline by setting vdiwstop to the current line number
// if display starts all enabled planes are fetched
// if vstop is set 4 CCKs after vstart to the same line no display occurs
// if vstop is set 8 CCKs after vstart one 16 pixel chunk is displayed (lowres)

//vertical display window enable		
reg	vdiwena;
always @(posedge clk)
	if (reset || sof || vpos[8:0]=={~vdiwstop[15],vdiwstop[15:8]})
		vdiwena <= 0;
	else if (vpos[8:0] == {1'b0,vdiwstrt[15:8]})	
		vdiwena <= 1;

bpldma_engine bpd1
(
	.clk(clk),
	.reset(reset),
	.dmaena(bplen),
	.diwena(vdiwena),
	.hpos(hpos),
	.dma(dma_bpl),
	.regaddressin(regaddress),
	.regaddressout(regaddress_bpl),
	.datain(datain),
	.addressout(address_bpl)	
);

//--------------------------------------------------------------------------------------

//instantiate sprite dma engine
sprdma_engine spr1
(
	.clk(clk),
	.clk28m(clk28m),
	.reqdma(req_spr),
	.ackdma(ack_spr),
	.hpos(hpos),
	.vpos(vpos),
	.vbl(vbl),
	.vblend(vblend),
	.regaddressin(regaddress),
	.regaddressout(regaddress_spr),
	.datain(datain),
	.addressout(address_spr)	
);

//--------------------------------------------------------------------------------------

//instantiate copper
copper cp1
(
	.clk(clk),
	.reset(reset),
	.reqdma(req_cop),
	.ackdma(ack_cop),
	.dma_bpl(dma_bpl),
	.sof(sof),
	.bbusy(bbusy),
	.vpos(vpos[7:0]),
	.hpos(hpos),
	.datain(datain),
	.regaddressin(regaddress),
	.regaddressout(regaddress_cop),
	.addressout(address_cop)	
);

//--------------------------------------------------------------------------------------

always @(posedge clk)
	if (!cck)
		if (!bls || bltpri)
			bls_cnt <= 0;
		else if (bls_cnt[1:0] != BLS_CNT_MAX)
			bls_cnt <= bls_cnt + 1;


//instantiate blitter
blitter bl1
(
	.clk(clk),
	.reset(reset),
	.reqdma(req_blt),
	.ackdma(ack_blt),
	.bzero(bzero),
	.bbusy(bbusy),
	.bblck(bblck),
	.bltena(cck|fastblitter),
	.wr(wr_blt),
	.datain(datain),
	.dataout(data_blt),
	.regaddressin(regaddress),
	.addressout(address_blt)	
);

//generate blitter finished intterupt (int3)
reg bbusyd;

always @(posedge clk)
	bbusyd <= bbusy;
	
assign int3 = (~bbusy) & bbusyd;

//--------------------------------------------------------------------------------------

//instantiate beam counters
beamcounter	bc1
(	
	.clk(clk),
	.reset(reset),
	.ntsc(ntsc),
	.datain(datain),
	.dataout(data_bmc),
	.regaddressin(regaddress),
	.hpos(hpos),
	.vpos(vpos),
	._hsync(_hsync),
	._vsync(_vsync),
	._csync(_csync),
	.blank(blank),
	.vbl(vbl),
	.vblend(vblend),
	.eol(sol),
	.eof(sof),
	.htotal(htotal)
);

//horizontal strobe for Denise
//in real Amiga Denise's hpos counter seems to be advanced by 4 CCKs in regards to Agnus' one
//Minimig isn't cycle exact and compensation for different data delay in implemented Denise's video pipeline is required 
assign strhor_denise = hpos==11 ? 1 : 0;
assign strhor_paula = hpos==(6*2+1) ? 1 : 0; //hack

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// refresh dma channel (for compatibility)
module refresh
(
	input	[8:0] hpos,
	output	reg dma
);

//dma request
always @(hpos)
	case (hpos)
		9'b0000_0100_1 : dma = 1;
		9'b0000_0110_1 : dma = 1;
		9'b0000_1000_1 : dma = 1;
		9'b0000_1010_1 : dma = 1;
		default        : dma = 0;
	endcase

endmodule



//bit plane dma engine
module bpldma_engine
(
	input 	clk,		    			//bus clock
	input	reset,						//reset
	input	dmaena,						//enable dma input
	input	diwena,						//display window enable (vertical)
	input	[8:0] hpos,					//agnus internal horizontal position counter (advanced by 4 CCK)
	output	reg dma,					//true if bitplane dma engine uses it's cycle
	input 	[8:1] regaddressin,			//register address inputs
	output 	reg [8:1] regaddressout,	//register address outputs
	input	[15:0] datain,				//bus data in
	output	[20:1] addressout			//chip address out
);

//register names and adresses		
parameter BPLPTBASE = 9'h0e0;	//bitplane pointers base address
parameter DDFSTRT   = 9'h092;		
parameter DDFSTOP   = 9'h094;
parameter BPL1MOD   = 9'h108;
parameter BPL2MOD   = 9'h10a;
parameter BPLCON0   = 9'h100;

//local signals
reg		[8:2] ddfstrt;				//display data fetch start //JB: added bit #2
reg 	[8:2] ddfstop; 				//display data fetch stop //JB: added bit #2
reg		[15:1] bpl1mod;				//modulo for odd bitplanes
reg		[15:1] bpl2mod;				//modulo for even bitplanes
reg		[5:0] bplcon0;				//bitplane control (SHRES, HIRES and BPU bits)
reg		[5:0] bplcon0_delay [1:0];

wire 	hires;
wire	shres;
wire	[3:0] bpu;

reg		[20:1] newpt;				//new pointer				
reg 	[20:16] bplpth [7:0];		//upper 5 bits bitplane pointers
reg 	[15:1] bplptl [7:0];		//lower 16 bits bitplane pointers
reg		[2:0] plane;				//plane pointer select

wire	mod;						//end of data fetch, add modulo

reg		hardena;					//hardware display data fetch enable ($18-$D8)
reg 	softena;					//software display data fetch enable
wire	ddfena;						//combined display data fetch

reg 	[2:0] ddfseq;				//bitplane DMA fetch cycle sequencer
reg 	ddfrun;						//set when display dma fetches data
reg		ddfend;						//indicates the last display data fetch sequence

reg		[8:2] d_hpos;				//delayed hpos by 2 CCK's (compensation for DMA arbiter delay)
reg		d_stop;						//delayed ddfstop condition 

//--------------------------------------------------------------------------------------

//register bank address multiplexer
wire [2:0] select;

assign select = dma ? plane : regaddressin[4:2];

//high word pointer register bank (implemented using distributed ram)
wire [20:16] bplpth_in;

assign bplpth_in = dma ? newpt[20:16] : datain[4:0];

always @(posedge clk)
	if (dma || ((regaddressin[8:5]==BPLPTBASE[8:5]) && !regaddressin[1]))//if bitplane dma cycle or bus write
		bplpth[select] <= bplpth_in;
		
assign addressout[20:16] = bplpth[plane];

//low word pointer register bank (implemented using distributed ram)
wire [15:1] bplptl_in;

assign bplptl_in = dma ? newpt[15:1] : datain[15:1];

always @(posedge clk)
	if (dma || ((regaddressin[8:5]==BPLPTBASE[8:5]) && regaddressin[1]))//if bitplane dma cycle or bus write
		bplptl[select] <= bplptl_in;
		
assign addressout[15:1] = bplptl[plane];

//--------------------------------------------------------------------------------------

//write ddfstrt and ddfstop registers
always @(posedge clk)
	if (regaddressin[8:1]==DDFSTRT[8:1])
		ddfstrt[8:2] <= datain[7:1];
		
always @(posedge clk)
	if (regaddressin[8:1]==DDFSTOP[8:1])
		ddfstop[8:2] <= datain[7:1];

//write modulo registers
always @(posedge clk)
	if (regaddressin[8:1]==BPL1MOD[8:1])
		bpl1mod[15:1] <= datain[15:1];
		
always @(posedge clk)
	if (regaddressin[8:1]==BPL2MOD[8:1])
		bpl2mod[15:1] <= datain[15:1];

//write those parts of bplcon0 register that are relevant to bitplane DMA sequencer
always @(posedge clk)
	if (reset)
		bplcon0 <= 6'b00_0000;
	else if (regaddressin[8:1]==BPLCON0[8:1])
		bplcon0 <= {datain[6],datain[15],datain[4],datain[14:12]}; //SHRES,HIRES,BPU3,BPU2,BPU1,BPU0

//delay by 8 clocks (in real Amiga DMA sequencer is pipelined and features a delay of 4 CCKs)
always @(posedge clk)
	if (hpos[1:0]==2'b01)
	begin
		bplcon0_delay[0] <= bplcon0;
		bplcon0_delay[1] <= bplcon0_delay[0];
	end

assign shres = bplcon0_delay[1][5];
assign hires = bplcon0_delay[1][4];
assign bpu = bplcon0_delay[1][3:0];

//--------------------------------------------------------------------------------------
/*
	Display DMA can start and stop on any (within hardware limits) 2-CCK boundary regardless of a choosen resolution.
	Non-aligned start position causes addition of extra shift value to horizontal scroll. 
	This values depends on which horizontal position BPL0DAT register is written.
	One full display DMA sequence lasts 8 CCKs. When sequence restarts finish condition is checked (ddfstop position passed).
	The last DMA sequence adds modulo to bitplane pointers.
	The state of BPLCON0 is delayed by 4 CCKs (real Agnus has pipelinng in DMA engine).
	
	ddf start condition is checked 2 CCKs before actual position, ddf stop is checked 4 CKCs in advance
*/ 

//delayed hpos by 2 CCKs
always @(posedge clk)
	if (hpos[1:0]==2'b11)
		d_hpos <= hpos[8:2];

//delayed ddfstop condition by 2 CCKs
always @(posedge clk)
	if (hpos[1:0]==2'b01)
		d_stop <= hpos[8:2]==ddfstop[8:2] ? 1 : 0;

//softena : software display data fetch window
always @(posedge clk)
	if (d_hpos[8:2]==ddfstrt[8:2] && hpos[1:0]==2'b01)
		softena <= 1;
	else if (d_stop && hpos[1:0]==2'b01)
		softena <= 0;
		 
//hardena : hardware limits of display data fetch
always @(posedge clk)
	if ({d_hpos[8:2],hpos[1]}==8'h18 && hpos[0])
		hardena <= 1;
	else if ({d_hpos[8:2],hpos[1]}==8'hD8 && hpos[0])
		hardena <= 0;

// ddfena signal is set and cleared 2 CCKs before actual transfer should start or stop
assign ddfena = hardena & softena;

//bitplane fetch dma sequence counter (1 bitplane DMA sequence lasts 8 CCK cycles)
always @(posedge clk)
	if (hpos[0]) //cycle alligment
		if (ddfrun) //if enabled go to the next state
			ddfseq <= ddfseq + 1;
		else
			ddfseq <= 0;

//this signal enables bitplane DMA sequence
always @(posedge clk)
	if (hpos[0]) //cycle alligment
		if (ddfena && diwena && !hpos[1]) //bitplane DMA starts at odd timeslot
			ddfrun <= 1;
		else if ((ddfend || !diwena) && ddfseq==7) //cleared at the end of last bitplane DMA cycle
			ddfrun <= 0;

//the last cycle of the bitplane DMA (time to add modulo)
always @(posedge clk)
	if (hpos[0])
		if (ddfseq==7 && ddfend) //cleared at the end of the last DMA cycle
			ddfend <= 0;
		else if (ddfseq==7 && !ddfena) //set at the end of a previous DMA cycle
			ddfend <= 1;


//signal for adding modulo to the bitplane pointers
assign mod = shres ? ddfend & ddfseq[2] & ddfseq[1] : hires ? ddfend & ddfseq[2] : ddfend;

//plane number encoder
always @(shres or hires or ddfseq)
	if (shres) //super high resolution (35ns pixel clock)
		plane = {2'b00,~ddfseq[0]};
	else if (hires) //high resolution (70ns pixel clock)
		plane = {1'b0,~ddfseq[0],~ddfseq[1]};
	else //low resolution (140ns pixel clock)
		plane = {~ddfseq[0],~ddfseq[1],~ddfseq[2]};
		
//generate dma signal
//for a dma to happen plane must be less than BPU (bplcon0), dma must be enabled
//(enable) and datafetch compares must be true (ddfenable)
//because invalid slots are coded as plane = 7, the compare with BPU is
//automatically false
always @(plane or bpu or hpos[0] or dmaena or ddfrun)
begin
	if (ddfrun && dmaena && hpos[0]) //if dma enabled and within ddf limits and dma slot
	begin
		if ({1'b0,plane[2:0]}<bpu[3:0]) //if valid plane
			dma = 1;
		else
			dma = 0;
	end
	else
		dma = 0;
end

//--------------------------------------------------------------------------------------

//dma pointer arithmetic unit
always @(addressout or bpl1mod or bpl2mod or plane[0] or mod)
	if (mod)
	begin
		if (plane[0])//even plane	modulo
			newpt[20:1] = addressout[20:1]+{{5{bpl2mod[15]}},bpl2mod[15:1]}+1;
		else//odd plane modulo
			newpt[20:1] = addressout[20:1]+{{5{bpl1mod[15]}},bpl1mod[15:1]}+1;
	end
	else
		newpt[20:1] = addressout[20:1]+1;

//Denise bitplane shift registers address lookup table
always @(plane)
begin
	case (plane)
		3'b000 : regaddressout[8:1] = 8'h88;
		3'b001 : regaddressout[8:1] = 8'h89;
		3'b010 : regaddressout[8:1] = 8'h8A;
		3'b011 : regaddressout[8:1] = 8'h8B;
		3'b100 : regaddressout[8:1] = 8'h8C;
		3'b101 : regaddressout[8:1] = 8'h8D;
		3'b110 : regaddressout[8:1] = 8'h8E;	//this is required for AGA only
		3'b111 : regaddressout[8:1] = 8'h8F;	//this is required for AGA only
	endcase
end

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
/*
JB: some conclusions of sprite engine investigation, it seems to be as follows:
- during vblank sprite dma is disabled by hardware, no automatic fetches occur but copper or cpu
can write to any sprite register, and all SPRxPTR pointers should be refreshed
- during the last line of vblank (PAL: $19, NTSC: $14) if sprite dma is enabled
it fetches SPRxPOS/SPRxCTL registers according to current SPRxPTR pointers
	This is the only chance for DMA to fetch new values of SPRxPOS/SPRxCTL. If DMA isn't enabled
during this line new values won't be placed into SPRxPOS/SPRxCTL registers.
	Enabling DMA after this line can have two results depending on current value of SPRxPOS/SPRxCTL.
- if VSTOP value is matched first with VERBEAM, data from memory is fetched and placed into SPRxPOS/SPRxCTL
- or if VSTART value is matched with VERBEAM, data from memory is fetched and placed into SPRxDATA/SPRxDATB 
  and the situation repeats with every new line until VSTOP condition is met.
The VSTOP condition takes precedence.
	If you set VSTART to value lower or the same (remember that VSTOP takes precedence) as the current VERBEAM
this condition will never be met and sprite engine will wait till VSTOP matches VERBEAM. If it happens then it
fetches another two words into SPRxPOS/SPRxCTL. And again if new VSTART is lower or the same as VERBEAM
it will fetch another new SPRxPOS/SPRxCTL when VSTOP is met (or will wait till next vbl).
	To disable further sprite list processing it's enough to set VSTART and VSTOP to values which are outside
of the screen or has been already achieved.

	When waiting for VSTART condition any write to SPRxDATA (write to SPRxDATB takes no effect) makes the written value
visible on the screen but it doesn't start DMA although it's enabled. The same value is displayed in every subsequent 
line until DMA starts and delivers new data to SPRxDAT or SPRxCTL is written (by DMA, copper or cpu).
It seems like only VSTART condition starts DMA transfer.
	Any write to SPRxCTL while DMA is active doesn't stop display but new value of VSTOP takes effect. Actually 
display is reenabled by DMA write to SPRxDATA in next line.
	The same applies to SPRxPOS writes when sprite is beeing displayed - only HSTART position changes (if new VSTART
is specified to be met before VSTOP nothing interesting happens).

	The DMA engine sees VSTART condition as true even if DMA is dissabled. Enabling DMA after VSTART and before VSTOP
starts sprite display in enabled line (if it's enabled early enough).
	Dissabling DMA in the line when new SPRxPOS/SPRxCTL is fetched and enabling it in the next one results in stopped
DMA transfer but the last line of sprite is displayed till the end of the screen.

VSTART and VSTOP specified within vbl are not met.
vbl stops dma transfer.
The first possible line to display a sprite is line $1A (PAL).
During vbl SPRxPOS/SPRxCTL are not automatically modified, values written before vbl are still present when vbl ends.

algo:
	if vbl or VSTOP : disable data dma
	else if VSTART: start data dma
	
	if vblend or (VSTOP and not vbl): dma transfer to sprxpos/sprxctl
	else if data dma active: transfer to sprxdata/sprcdatb

It doesn't seem to be complicated :)

Sprite which has been triggered by write to SPRxDATA is not disabled by vbl.
It seems that vstop and vstart conditions are checked every cycle. 
Dma doesn't fetch new pos/ctl if vstop is not equal to the current line number.

Feature:
If new vstart is specified to be the same as the line during which it's fetched, display starts in the next line
but is one line shorter.
*/

//sprite dma engine
module sprdma_engine
(
	input 	clk,		    			//bus clock
	input	clk28m,						//JB: 28MHz system clock
	output	reg reqdma,					//sprite dma engine requests dma cycle
	input	ackdma,						//agnus dma priority logic grants dma cycle
	input	[8:0] hpos,					//JB: agnus internal horizontal position counter (advanced by 4 CCKs)
	input	[10:0] vpos,				//vertical beam counter
	input	vbl,						//JB: vertical blanking
	input	vblend,						//JB: last line of vertical blanking
	input	[8:1] regaddressin,			//register address inputs
	output 	reg [8:1] regaddressout,	//register address outputs
	input	[15:0] datain,				//bus data in
	output	[20:1] addressout			//chip address out
);
//register names and adresses		
parameter SPRPTBASE     = 9'h120;		//sprite pointers base address
parameter SPRPOSCTLBASE = 9'h140;		//sprite data, position and control register base address

//local signals
reg 	[20:16] sprpth [7:0];		//upper 5 bits sprite pointers register bank
reg 	[15:1]  sprptl [7:0];		//lower 16 bits sprite pointers register bank
reg		[15:8]  sprpos [7:0];		//sprite vertical start position register bank
reg		[15:4]  sprctl [7:0];		//sprite vertical stop position register bank
									//JB: implementing ECS extended vertical sprite position

wire	[9:0] vstart;				//vertical start of selected sprite
wire	[9:0] vstop;				//vertical stop of selected sprite
reg		[2:0] sprite;				//sprite select signal
wire	[20:1] newptr;				//new sprite pointer value

reg 	enable;						//horizontal position in sprite region

//the following signals change their value during cycle 0 of 4-cycle dma sprite window
reg		sprvstop;					//current line is sprite's vstop
reg		sprdmastate;				//sprite dma state (sprite image data cycles)

reg		dmastate_mem [7:0];			//dma state for every sprite
wire	dmastate;					//output from memory
reg		dmastate_in;				//input to memory

reg		[2:0] sprsel;				//memory selection

//sprite selection signal (in real amiga sprites are evaluated concurently,
//in our solution to save resources they are evaluated sequencially but 8 times faster (28MHz clock)
always @(posedge clk28m)
	if (sprsel[2]==hpos[0])		//sprsel[2] is synced with hpos[0]
		sprsel <= sprsel + 1;

//--------------------------------------------------------------------------------------

//register bank address multiplexer
wire	[2:0] ptsel;			//sprite pointer and state registers select
wire	[2:0] pcsel;			//sprite position and control registers select

assign ptsel = (ackdma) ? sprite : regaddressin[4:2];
assign pcsel = (ackdma) ? sprite : regaddressin[5:3];

//sprite pointer arithmetic unit
assign newptr = addressout[20:1] + 1;

//sprite pointer high word register bank (implemented using distributed ram)
wire [20:16] sprpth_in;
assign sprpth_in = ackdma ? newptr[20:16] : datain[4:0];
always @(posedge clk)
	if (ackdma || ((regaddressin[8:5]==SPRPTBASE[8:5]) && !regaddressin[1]))//if dma cycle or bus write
		sprpth[ptsel] <= sprpth_in;

assign addressout[20:16] = sprpth[sprite];

//sprite pointer low word register bank (implemented using distributed ram)
wire [15:1]sprptl_in;
assign sprptl_in = ackdma ? newptr[15:1] : datain[15:1];
always @(posedge clk)
	if (ackdma || ((regaddressin[8:5]==SPRPTBASE[8:5]) && regaddressin[1]))//if dma cycle or bus write
		sprptl[ptsel] <= sprptl_in;

assign addressout[15:1] = sprptl[sprite];

//sprite vertical start position register bank (implemented using distributed ram)
always @(posedge clk)
	if ((regaddressin[8:6]==SPRPOSCTLBASE[8:6]) && (regaddressin[2:1]==2'b00))//if bus write
		sprpos[pcsel] <= datain[15:8];

assign vstart[7:0] = sprpos[sprsel];

//sprite vertical stop position register bank (implemented using distributed ram)
always @(posedge clk)
	if ((regaddressin[8:6]==SPRPOSCTLBASE[8:6]) && (regaddressin[2:1]==2'b01))//if bus write
		sprctl[pcsel] <= {datain[15:8],datain[6],datain[5],datain[2],datain[1]};
		
assign {vstop[7:0],vstart[9],vstop[9],vstart[8],vstop[8]} = sprctl[sprsel];

//sprite dma channel state register bank
//update dmastate when hpos is in sprite fetch region
//every sprite has allocated 8 system clock cycles with two active dma slots:
//the first during cycle #3 and the second during cycle #7
//first slot transfers data to sprxpos register during vstop or vblend or to sprxdata when dma is active
//second slot transfers data to sprxctl register during vstop or vblend or to sprxdatb when dma is active
//current dmastate is valid after cycle #1 for given sprite and it's needed during cycle #3 and #7
always @(posedge clk28m)
	dmastate_mem[sprsel] <= dmastate_in;

assign dmastate = dmastate_mem[sprsel];

//evaluating sprite image dma data state
always @(vbl or vpos or vstop or vstart or dmastate) 
	if (vbl || (vstop[9:0]==vpos[9:0]))
		dmastate_in = 0;
	else if (vstart[9:0]==vpos[9:0])
		dmastate_in = 1;
	else
		dmastate_in = dmastate;

always @(posedge clk28m)
	if (sprite==sprsel && hpos[2:1]==2'b01)
		sprdmastate <= dmastate;

always @(posedge clk28m)
	if (sprite==sprsel && hpos[2:1]==2'b01)
		sprvstop <= vstop[9:0]==vpos[9:0] ? 1 : 0;

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//check if we are allowed to allocate dma slots for sprites
//dma slots for sprites: even cycles from 1A to 38 (inclusive)
always @(posedge clk)
	if (hpos[8:1]==8'h18 && hpos[0])
		enable <= 1;
	else if (hpos[8:1]==8'h38 && hpos[0])
		enable <= 0;
		
//get sprite number for which we are going to do dma
always @(posedge clk)
	if (hpos[2:0]==3'b001)
		sprite[2:0] <= {hpos[5]^hpos[4],~hpos[4],hpos[3]};

//generate reqdma signal
always @(vpos or vbl or vblend or hpos or enable or sprite or sprvstop or sprdmastate)
	if (enable && hpos[1:0]==2'b01)
	begin
		if (vblend || (sprvstop && ~vbl))
		begin
			reqdma = 1;
			if (hpos[2])
				regaddressout[8:1] = {SPRPOSCTLBASE[8:6],sprite,2'b00};	//SPRxPOS
			else
				regaddressout[8:1] = {SPRPOSCTLBASE[8:6],sprite,2'b01};	//SPRxCTL
		end
		else if (sprdmastate)
		begin
			reqdma = 1;
			if (hpos[2])
				regaddressout[8:1] = {SPRPOSCTLBASE[8:6],sprite,2'b10};	//SPRxDATA
			else
				regaddressout[8:1] = {SPRPOSCTLBASE[8:6],sprite,2'b11};	//SPRxDATB
		end
		else
		begin
			reqdma = 0;
			regaddressout[8:1] = 8'hFF;
		end
	end
	else
	begin
		reqdma = 0;
		regaddressout[8:1] = 8'hFF;
	end

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//disk dma engine
//DMA cycle allocation is as specified in the HRM
//optionally 4 refresh slots are used for higher transfer speed

module dskdma_engine
(
	input 	clk,		    		//bus clock
	output	dma,					//true if disk dma engine uses it's cycle
	input	dmal,					//Paula requests dma
	input	dmas,					//Paula special dma
	input	speed,
	input	[8:0] hpos,				//horizontal beam counter (advanced by 4 CCKs)
	output	wr,						//write (disk dma writes to memory)
	input 	[8:1] regaddressin,		//register address inputs
	output 	[8:1] regaddressout,	//register address outputs
	input	[15:0] datain,			//bus data in
	output	reg [20:1] addressout	//chip address out current disk dma pointer
);
//register names and adresses		
parameter DSKPTH  = 9'h020;			
parameter DSKPTL  = 9'h022;			
parameter DSKDAT  = 9'h026;			
parameter DSKDATR = 9'h008;		

//local signals
wire	[20:1] addressoutnew;	//new disk dma pointer
reg		dmaslot;				//indicates if the current slot can be used to transfer data

//--------------------------------------------------------------------------------------

//dma cycle allocation
//nominally disk DMA uses 3 slots: 08, 0A and 0C
//refresh slots: 00, 02, 04 and 06 are used for higher transfer speed
//hint: Agnus hpos counter is advanced by 4 CCK cycles
always @(hpos or speed)
	case (hpos[8:1])
		8'h04:	 dmaslot = speed;
		8'h06:	 dmaslot = speed;
		8'h08:	 dmaslot = speed;
		8'h0A:	 dmaslot = speed;
		8'h0C:	 dmaslot = 1;
		8'h0E:	 dmaslot = 1;
		8'h10:	 dmaslot = 1;
		default: dmaslot = 0;
	endcase

//dma request
assign dma = dmal & dmaslot & hpos[0];
//write signal
assign wr = ~dmas;

//--------------------------------------------------------------------------------------

//addressout input multiplexer and ALU
assign addressoutnew[20:1] = dma ? addressout[20:1]+1 : {datain[4:0],datain[15:1]}; 

//disk pointer control
always @(posedge clk)
	if (dma || (regaddressin[8:1] == DSKPTH[8:1]))
		addressout[20:16] <= addressoutnew[20:16];//high 5 bits
always @(posedge clk)
	if (dma || (regaddressin[8:1] == DSKPTL[8:1]))
		addressout[15:1] <= addressoutnew[15:1];//low 15 bits

//--------------------------------------------------------------------------------------

//register address output
assign regaddressout[8:1] = wr ? DSKDATR[8:1] : DSKDAT[8:1];

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//
// >>> Audio DMA Engine <<<
//
// 2 dma cycle types are defined:
// - restart pointer (go back to the beginning of the sample): dmas active 
// - advance pointer to the next word of the sample: dmas inactive
//
// dma slot allocation: 
// channel #0 : $0E
// channel #1 : $10
// channel #2 : $12
// channel #3 : $14

module auddma_engine
(
	input 	clk,		    			//bus clock
	output	dma,						//true if audio dma engine uses it's cycle
	input	[3:0] audio_dmal,			//audio dma data transfer request (from Paula)
	input	[3:0] audio_dmas,			//audio dma location pointer restart (from Paula)
	input	[8:0] hpos,					//horizontal beam counter
	input 	[8:1] regaddressin,			//register address inputs
	output 	reg [8:1] regaddressout,	//register address outputs
	input	[15:0] datain,				//bus data in
	output	[20:1] addressout			//chip address out
);

//register names and adresses		
parameter AUD0DAT = 9'h0AA;			
parameter AUD1DAT = 9'h0BA;			
parameter AUD2DAT = 9'h0CA;			
parameter AUD3DAT = 9'h0DA;			

//local signals
wire	audlcena;				//audio dma location pointer register address enable
wire	[1:0] audlcsel;			//audio dma location pointer select
reg		[20:16] audlch [3:0];	//audio dma location pointer bank (high word)
reg		[15:1] audlcl [3:0];	//audio dma location pointer bank (low word)
wire	[20:1] audlcout;		//audio dma location pointer bank output
reg		[20:1] audpt [3:0];		//audio dma pointer bank
wire	[20:1] audptout;		//audio dma pointer bank output
reg		[1:0]  channel;			//audio dma channel select
reg		dmal;
reg		dmas;

//--------------------------------------------------------------------------------------
// location registers address enable
// active when any of the location registers is addressed
// $A0-$A3, $B0-$B3, $C0-$C3, $D0-$D3, 
assign audlcena = ~regaddressin[8] & regaddressin[7] & (regaddressin[6]^regaddressin[5]) & ~regaddressin[3] & ~regaddressin[2];

//location register channel select
assign audlcsel = {~regaddressin[5],regaddressin[4]};

//audio location register bank
always @(posedge clk)
	if (audlcena & ~regaddressin[1]) // AUDxLCH
		audlch[audlcsel] <= datain[4:0];
			
always @(posedge clk)
	if (audlcena & regaddressin[1]) // AUDxLCL			
		audlcl[audlcsel] <= datain[15:1];

//get audio location pointer
assign audlcout = {audlch[channel],audlcl[channel]};

//--------------------------------------------------------------------------------------
//dma cycle allocation
always @(hpos or audio_dmal)
	case (hpos)
		9'b0001_0010_1 : dmal = audio_dmal[0]; //$0E
		9'b0001_0100_1 : dmal = audio_dmal[1]; //$10
		9'b0001_0110_1 : dmal = audio_dmal[2]; //$12
		9'b0001_1000_1 : dmal = audio_dmal[3]; //$14
		default        : dmal = 0; 
	endcase

//dma cycle request	
assign dma = dmal;

//channel dmas encoding	
always @(hpos or audio_dmas)
	case (hpos)
		9'b0001_0010_1 : dmas = audio_dmas[0]; //$0E
		9'b0001_0100_1 : dmas = audio_dmas[1]; //$10
		9'b0001_0110_1 : dmas = audio_dmas[2]; //$12
		9'b0001_1000_1 : dmas = audio_dmas[3]; //$14
		default        : dmas = 0; 
	endcase

//dma channel select 
always @(hpos)
	case (hpos[3:2])
		2'b01 : channel = 0; //$0E
		2'b10 : channel = 1; //$10
		2'b11 : channel = 2; //$12
		2'b00 : channel = 3; //$14
	endcase

//addressout output multiplexer
assign addressout[20:1] = dmas ? audlcout[20:1] : audptout[20:1]; 

//audio location register bank (implemented using distributed ram)
//and ALU
always @(posedge clk)
	if (dma)
		audpt[channel] <= addressout[20:1] + 1;
		
assign audptout[20:1] = audpt[channel];

//register address output multiplexer
always @(channel)
	case (channel)
		0 : regaddressout[8:1] = AUD0DAT[8:1];
		1 : regaddressout[8:1] = AUD1DAT[8:1];
		2 : regaddressout[8:1] = AUD2DAT[8:1];
		3 : regaddressout[8:1] = AUD3DAT[8:1];
	endcase

//--------------------------------------------------------------------------------------

endmodule