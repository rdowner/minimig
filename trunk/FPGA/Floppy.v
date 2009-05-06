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
// This is the floppy disk controller (part of Paula)
//
// 23-10-2005		-started coding
// 24-10-2005		-done lots of work
// 13-11-2005		-modified fifo to use block ram
//				-done lots of work
// 14-11-2005		-done more work
// 19-11-2005		-added wordsync logic
// 20-11-2005		-finished core floppy disk interface
//				-added disk interrupts
//				-added floppy control signal emulation
// 21-11-2005		-cleaned up code a bit
// 27-11-2005		-den and sden are now active low (_den and _sden)
//				-fixed bug in parallel/serial converter
//				-fixed more bugs
// 02-12-2005		-removed dma abort function
// 04-12-2005		-fixed bug in fifo empty signalling
// 09-12-2005		-fixed dsksync handling	
//				-added protection against stepping beyond track limits
// 10-12-2005		-fixed some more bugs
// 11-12-2005		-added dout output enable to allow SPI bus multiplexing
// 12-12-2005		-fixed major bug, due error in statemachine, multiple interrupts were requested
//				 after a DMA transfer, this could lock up the whole machine
// 				-enable line disconnected  --> this module still needs a lot of work
// 27-12-2005		-cleaned up code, this is it for now
// 07-01-2005		-added dmas
// 15-01-2006		-added support for track 80-127 (used for loading kickstart)
// 22-01-2006		-removed support for track 80-127 again
// 06-02-2006		-added user disk control input
// 28-12-2006		-spi data out is now low when not addressed to allow multiplexing with multiple spi devices		
// JB:
// 2008-07-17		- modified floppy interface for better read handling and write support
//					- spi interface clocked by SPI clock
// 2008-09-24		- incompatibility found: _READY signal should respond to _SELx even when the motor is off
//					- added logic for four floppy drives
// 2008-10-07		- ide command request implementation
// 2008-10-28		- further hdd implementation
// 2009-04-05		- code clean-up


module floppy
(
	//bus interface
	input 	clk,		    		//bus clock
	input 	reset,			   		//reset 
	input	enable,					//dma enable
	input 	[8:1] regaddress,		//register address inputs
	input	[15:0] datain,			//bus data in
	output	[15:0] dataout,			//bus data out
	output	dmal,					//dma request output
	output	dmas,					//dma special output 
	//disk control signals from cia and user
	input	_step,					//step heads of disk
	input	direc,					//step heads direction
	input	[3:0] _sel,				//disk select 	
	input	side,					//upper/lower disk head
	input	_motor,					//disk motor control
	output	_track0,				//track zero detect
	output	_change,				//disk has been removed from drive
	output	_ready,					//disk is ready
	output	_wprot,					//disk is write-protected
	//interrupt request and misc. control
	output	reg blckint,			//disk dma has finished interrupt
	output	syncint,				//disk syncword found
	input	wordsync,				//wordsync enable
	//flash drive host controller interface	(SPI)
	input	_den,					//async. serial data enable
	input	din,					//async. serial data input
	output	dout,					//async. serial data output
	input	dclk,					//async. serial data clock
	
	output	disk_led,				//disk activity LED, active when DMA is on
	input	[1:0] floppy_drives,	//floppy drive number
	
	input	direct_sel,				//enables direct data transfer from SD card
	input	direct_din,				//data line from SD card
	input	hdd_cmd_req,			//HDD requests service (command register has been written)
	input	hdd_dat_req,			//HDD requests data tansfer
	output	[2:0] hdd_addr,			//task file register address
	output	[15:0] hdd_data_out,	//data from HDD to HDC
	input	[15:0] hdd_data_in,		//data from HDC to HDD
	output	hdd_wr,					//task file register write strobe
	output	hdd_status_wr,			//status register write strobe (MCU->HDD)
	output	hdd_data_wr,			//data write strobe
	output	hdd_data_rd				//data read strobe
);

//register names and addresses
	parameter DSKBYTR = 9'h01a;
	parameter DSKDAT  = 9'h026;		
	parameter DSKDATR = 9'h008;
	parameter DSKSYNC = 9'h07e;
	parameter DSKLEN  = 9'h024;

	//local signals
	reg		[15:0] dsksync;			//disk sync register
	reg		[15:0] dsklen;			//disk dma length, direction and enable 
	reg		[6:0] dsktrack[3:0];	//track select
	wire	[7:0] track;
	
	reg		dmaon;					//disk dma read/write enabled
	wire	lenzero;				//disk length counter is zero
	wire	spidat;					//spi data word transfer strobe
	reg		trackwr;				//write track (command to host)
	reg		trackrd;				//read track (command to host)
	
	wire	_dsktrack0;				//disk heads are over track 0
	
	wire	[15:0] bufdin;			//fifo data in
	wire	[15:0] bufdout; 		//fifo data out
	wire	bufwr;					//fifo write enable
	reg		bufwr_del;				//fifo write enable delayed
	wire	bufrd;					//fifo read enable
	wire	bufempty;				//fifo is empty
	wire	buffull;				//fifo is full

	wire	[15:0] dskbytr;			
	wire	[15:0] dskdatr;
	
	// JB:
	wire	fifo_reset;
	reg		dmaen;					//dsklen dma enable
	wire	[13:0] fifo_cnt;
	reg		[15:0] wr_fifo_status;
	
	reg		[3:0] disk_present;		//disk present status
	reg		[3:0] disk_writable;	//disk write access status
	
	wire	_selx;					//active whenever any drive is selected
	wire	[1:0] sel;				//selected drive number
	
	reg		[1:0] drives;			//number of currently connected floppy drives (1-4)

	//decoded SPI commands
	reg		cmd_fdd;				//SPI host accesses floppy drive buffer
	reg		cmd_hdd_rd;				//SPI host reads task file registers		
	reg		cmd_hdd_wr;				//SPI host writes task file registers
	reg		cmd_hdd_data_wr;		//SPI host writes data to HDD buffer
	reg		cmd_hdd_data_rd;		//SPI host reads data from HDD buffer
	
//-----------------------------------------------------------------------------------------------//
// JB: SPI interface
//-----------------------------------------------------------------------------------------------//
		
	wire sck;					//SPI clock
	wire scs;					//SPI chip select
	wire sdi;					//SPI data in
	wire sdo;					//SPI data out
	wire scs1;
	wire scs2;

	reg [3:0] spi_bit_cnt;		//received bit counter - incremented on rising edge of SCK
	wire spi_bit_15;
	wire spi_bit_0;
	reg [15:1] spi_sdi_reg;		//spi receive register
	reg [15:0] rx_data;			//spi received data
	reg [15:0] spi_sdo_reg;		//spi transmit register (shifted on SCK falling edge)

	reg spi_rx_flag;
	reg rx_flag_sync;
	reg rx_flag;
	wire spi_rx_flag_clr;

	reg spi_tx_flag;
	reg tx_flag_sync;
	reg tx_flag;
	wire spi_tx_flag_clr;

	reg [15:0] spi_tx_data;		//data to be send via SPI
	reg [15:0] spi_tx_data_0;
	reg [15:0] spi_tx_data_1;
	reg [15:0] spi_tx_data_2;
	reg [15:0] spi_tx_data_3;

	reg [1:0] spi_tx_cnt;		//transmitted SPI words counter
	reg [1:0] spi_tx_cnt_del;	//delayed transmitted SPI words counter
	reg [1:0] tx_cnt;			//transmitted SPI words counter
	reg	[2:0] tx_data_cnt;
	reg	[2:0] rx_data_cnt;

	reg	[1:0] rx_cnt;
	reg	[1:0] spi_rx_cnt;		//received SPI words counter (counts form 0 to 3 and stops there)
	reg	spi_rx_cnt_rst;			//indicates reception of the first spi word after activation of the chip select

//SPI mode 0 - high idle clock
assign sck = dclk;
assign sdi = direct_sel ? direct_din : din;
assign dout = sdo;
assign scs1 = ~_den;
assign scs2 = direct_sel;
assign scs = scs1 | scs2;

//received bits counter (0-15)
always @(posedge sck or negedge scs)
	if (~scs)
		spi_bit_cnt <= 0; //reset if chip select is not active
	else
		spi_bit_cnt <= spi_bit_cnt + 1;
		
assign spi_bit_15 = spi_bit_cnt==15 ? 1 : 0;
assign spi_bit_0 = spi_bit_cnt==0 ? 1 : 0;

//SDI input shift register
always @(posedge sck)
	spi_sdi_reg <= {spi_sdi_reg[14:1],sdi};
	
//spi rx data register
always @(posedge sck)
	if (spi_bit_15)
		rx_data <= {spi_sdi_reg[15:1],sdi};		

// rx_flag is synchronous with clk and is set after receiving the last bit of a word
assign spi_rx_flag_clr = rx_flag | reset;
always @(posedge sck or posedge spi_rx_flag_clr)
	if (spi_rx_flag_clr)
		spi_rx_flag <= 0;
	else if (spi_bit_cnt==15)
		spi_rx_flag <= 1;

always @(negedge clk)
	rx_flag_sync <= spi_rx_flag;	//double synchronization to avoid metastability

always @(posedge clk)
	rx_flag <= rx_flag_sync;		//synchronous with clk

// tx_flag is synchronous with clk and is set after sending the first bit of a word
assign spi_tx_flag_clr = tx_flag | reset;
always @(negedge sck or posedge spi_tx_flag_clr)
	if (spi_tx_flag_clr)
		spi_tx_flag <= 0;
	else if (spi_bit_cnt==0)
		spi_tx_flag <= 1;

always @(negedge clk)
	tx_flag_sync <= spi_tx_flag;	//double synchronization to avoid metastability

always @(posedge clk)
	tx_flag <= tx_flag_sync;		//synchronous with clk

//---------------------------------------------------------------------------------------------------------------------

always @(negedge sck or negedge scs)
	if (~scs)
		spi_tx_cnt <= 0;
	else if (spi_bit_0 && spi_tx_cnt!=3)
		spi_tx_cnt <= spi_tx_cnt + 1;
		
always @(negedge sck)
	if (spi_bit_0) 
		spi_tx_cnt_del <= spi_tx_cnt;

always @(posedge clk)
	tx_cnt <= spi_tx_cnt_del;		

//trnsmitted words counter (0-3) used for transfer of IDE task file registers
always @(negedge sck)
	if (spi_bit_cnt==0)
		if (spi_tx_cnt==2)
			tx_data_cnt <= 0;
		else
			tx_data_cnt <= tx_data_cnt + 1;

//received data counter, used only for transferring IDE task file register contents, count range: 0-7			
always @(posedge clk)
	if (rx_flag)
		if (rx_cnt != 3)
			rx_data_cnt <= 0;
		else
			rx_data_cnt <= rx_data_cnt + 1;			

//HDD interface			
assign hdd_addr = cmd_hdd_rd ? tx_data_cnt : cmd_hdd_wr ? rx_data_cnt : 0;
assign hdd_wr = cmd_hdd_wr && rx_flag && rx_cnt==3 ? 1 : 0;
assign hdd_data_wr = (cmd_hdd_data_wr && rx_flag && rx_cnt==3) || (scs2 && rx_flag) ? 1 : 0;	//there is a possibility that SCS2 is inactive before rx_flag is generated, depends on how fast the CS2 is deaserted after sending the last data bit
assign hdd_status_wr = rx_data[15:12]==4'b1111 && rx_flag && rx_cnt==0 ? 1 : 0;
// problem: spi_cmd1 doesn't deactivate after rising _CS line: direct transfers will be treated as command words,
// workaround: always send more than one command word
assign hdd_data_rd = cmd_hdd_data_rd && tx_flag && tx_cnt==3 ? 1 : 0;
assign hdd_data_out = rx_data[15:0];
		
always @(posedge sck or negedge scs1)
	if (~scs1)
		spi_rx_cnt_rst <= 1;
	else if (spi_bit_15)
		spi_rx_cnt_rst <= 0;
		
always @(posedge sck)
	if (scs1 && spi_bit_15)
		if (spi_rx_cnt_rst)
			spi_rx_cnt <= 0;
		else if (spi_rx_cnt!=3)
			spi_rx_cnt <= spi_rx_cnt + 1;

always @(posedge clk)
	rx_cnt <= spi_rx_cnt;
	
//spidat strobe		
assign spidat = cmd_fdd && rx_flag && rx_cnt==3 ? 1 : 0;

//------------------------------------

//SDO output shift register
always @(negedge sck)
	if (spi_bit_cnt==0)
		spi_sdo_reg <= spi_tx_data;
	else
		spi_sdo_reg <= {spi_sdo_reg[14:0],1'b0};

assign sdo = scs1 & spi_sdo_reg[15];

//spi transmit data multiplexer
always @(spi_tx_cnt or spi_tx_data_0 or spi_tx_data_1 or spi_tx_data_2 or spi_tx_data_3)
	case (spi_tx_cnt[1:0])
		0 : spi_tx_data = spi_tx_data_0;
		1 : spi_tx_data = spi_tx_data_1;
		2 : spi_tx_data = spi_tx_data_2;
		3 : spi_tx_data = spi_tx_data_3;
	endcase

always @(sel or drives or hdd_dat_req or hdd_cmd_req or trackwr or trackrd or track)
	spi_tx_data_0 = {sel[1:0],drives[1:0],hdd_dat_req,hdd_cmd_req,trackwr,trackrd,track[7:0]};

always @(dsksync)
//	if (trackrd)
		spi_tx_data_1 = dsksync[15:0]; 
//	else
//		spi_tx_data_1 = 0;

always @(trackrd or dmaen or dsklen or trackwr or wr_fifo_status)
	if (trackrd)
		spi_tx_data_2 = {dmaen,dsklen[14:0]};
	else if (trackwr)
		spi_tx_data_2 = wr_fifo_status;
	else
		spi_tx_data_2 = 0;

always @(cmd_fdd or trackrd or dmaen or dsklen or trackwr or bufdout	or cmd_hdd_rd or cmd_hdd_data_rd or hdd_data_in)	
	if (cmd_fdd)
		if (trackrd)
			spi_tx_data_3 = {dmaen,dsklen[14:0]};
		else if (trackwr)
			spi_tx_data_3 = bufdout;
		else
			spi_tx_data_3 = 0;
	else if (cmd_hdd_rd || cmd_hdd_data_rd)
		spi_tx_data_3 = hdd_data_in;	
	else
		spi_tx_data_3 = 0;			


//floppy disk write fifo status is latched when transmision of the previous spi word begins 
//it guarantees that when latching the status data into spi transmit register setup and hold times are met
always @(posedge clk)
	if (tx_flag)
		wr_fifo_status <= {dmaen&dsklen[14],1'b0,fifo_cnt[13:0]};

//-----------------------------------------------------------------------------------------------//
//active floppy drive number, updated during reset
always @(posedge clk)
	if (reset)
		drives <= floppy_drives;
		
//--------------------------------------------------------------------------------------
//data out multiplexer
assign dataout = dskbytr | dskdatr;

//--------------------------------------------------------------------------------------
//floppy control signal behaviour
reg		_stepd; 		//used to detect rising edge of _step

//active whenever any drive is selected
assign _selx = &_sel[3:0];

//active drive number (priority encoder)
assign sel = !_sel[0] ? 0 : !_sel[1] ? 1 : !_sel[2] ? 2 : !_sel[3] ? 3 : 0;

//_ready,_track0 and _change signals
assign _change = &(_sel | disk_present);

assign _wprot = &(_sel | disk_writable);

assign  _track0 =&(_selx | _dsktrack0);

//delay _step and _sel
always @(posedge clk)
	_stepd <= _step;

//track control
assign track = {dsktrack[sel],~side};
	
always @(posedge clk)
	if(!_selx && _step && !_stepd && !(!_dsktrack0 && direc))//track increment (direc=0) or decrement (direc=1) at rising edge of _step
		dsktrack[sel] <= dsktrack[sel] + {direc,direc,direc,direc,direc,direc,1'b1};

//_dsktrack0 and dsktrack79 detect
assign _dsktrack0 = (dsktrack[sel]==7'b000_0000) ? 0 : 1;

// drive _ready signal control
// Amiga DD drive activates _ready whenever _sel is active and motor is off
// or whenever _sel is active, motor is on and there is a disk inserted (not implemented - _ready is active when _sel is active)
assign _ready = (_sel[3]|~(drives[1]&drives[0])) & (_sel[2]|~drives[1]) & (_sel[1]|~(drives[1]|drives[0])) & _sel[0];

//--------------------------------------------------------------------------------------

//disk data byte and status read
assign dskbytr = (regaddress[8:1]==DSKBYTR[8:1])?{1'b0,(trackrd|trackwr),dsklen[14],13'b000000000000}:16'h0000;
	 
//disk sync register
always @(posedge clk)
	if (reset) 
		dsksync[15:0] <= 0;
	else if (regaddress[8:1]==DSKSYNC[8:1])
		dsksync[15:0] <= datain[15:0];

//disk length register
always @(posedge clk)
	if (reset)
		dsklen[14:0] <= 0;
	else if (regaddress[8:1]==DSKLEN[8:1])
		dsklen[14:0] <= datain[14:0];
	else if (bufwr)//decrement length register
		dsklen[13:0] <= dsklen[13:0] - 1;

//disk length register DMAEN
always @(posedge clk)
	if (reset)
		dsklen[15] <= 0;
	else if (blckint)
		dsklen[15] <= 0;
	else if (regaddress[8:1]==DSKLEN[8:1])
		dsklen[15] <= datain[15];
		
//dmaen - disk dma enable signal
always @(posedge clk)
	if (reset)
		dmaen <= 0;
	else if (blckint)
		dmaen <= 0;
	else if (regaddress[8:1]==DSKLEN[8:1])
		dmaen <= datain[15] & dsklen[15];//start disk dma if second write in a row with dsklen[15] set

//dsklen zero detect
assign lenzero = (dsklen[13:0]==0) ? 1 : 0;

//--------------------------------------------------------------------------------------
//disk data read path
wire	busrd;				//bus read
wire	buswr;				//bus write
reg		trackrdok;			//track read enable

//disk buffer bus read address decode
assign busrd=(regaddress[8:1]==DSKDATR[8:1])?1:0;

//disk buffer bus write address decode
assign buswr=(regaddress[8:1]==DSKDAT[8:1])?1:0;

//fifo data input multiplexer
assign bufdin[15:0] = trackrd ? rx_data[15:0] : datain[15:0];

//fifo write control
assign bufwr = (trackrdok & spidat & ~lenzero) | (buswr & dmaon);

//delayed version to allow writing of the last word to empty fifo
always @(posedge clk)
	bufwr_del <= bufwr;

//fifo read control
assign bufrd = (busrd & dmaon) | (trackwr & spidat);

//DSKSYNC interrupt
assign syncint = dsksync[15:0]==rx_data[15:0] && spidat && trackrd ? 1 : 0;
//assign syncint = 16'h4489==rx_data[15:0] && spidat && trackrd ? 1 : 0;

//track read enable / wait for syncword logic
always @(posedge clk)
	if (!trackrd)//reset
		trackrdok <= 0;
	else//wordsync is enabled, wait with reading untill syncword is found
		trackrdok <= ~wordsync | syncint | trackrdok;

assign fifo_reset = reset | ~dmaen;
		
//disk fifo / trackbuffer
fifo db1
(
	.clk(clk),
	.reset(fifo_reset),
	.din(bufdin),
	.dout(bufdout),
	.rd(bufrd),
	.wr(bufwr),
	.full(buffull),
	.cnt(fifo_cnt),
	.empty(bufempty)
);


//disk data read output gate
assign dskdatr[15:0] = busrd ? bufdout[15:0] : 16'h00_00;

//--------------------------------------------------------------------------------------
//dma request logic
assign dmal = dmaon & ((~dsklen[14] & ~bufempty) | (dsklen[14] & ~buffull));
//dmas is active during writes
assign dmas = dmaon & dsklen[14] & ~buffull;

//--------------------------------------------------------------------------------------
//main disk controller
reg		[1:0] dskstate;		//current state of disk
reg		[1:0] nextstate; 	//next state of state

//disk states
parameter DISKDMA_IDLE=2'b00;
parameter DISKDMA_ACTIVE=2'b10;
parameter DISKDMA_INT=2'b11;

//disk present and write protect status
always @(posedge clk)
	if(reset)
		{disk_writable[3:0],disk_present[3:0]} <= 8'b0000_0000;
	else if (rx_data[15:12]==4'b0001 && rx_flag && rx_cnt==0)
		{disk_writable[3:0],disk_present[3:0]} <= rx_data[7:0];

always @(posedge clk)
	if (reset)
	begin
		cmd_fdd <= 0;
		cmd_hdd_rd <= 0;
		cmd_hdd_wr <= 0;
		cmd_hdd_data_wr <= 0;
		cmd_hdd_data_rd <= 0;
	end
	else if (rx_flag && rx_cnt==0)
	begin
		cmd_fdd <= rx_data[15:13]==3'b000 ? 1 : 0;
		cmd_hdd_rd <= rx_data[15:12]==4'b1000 ? 1 : 0;
		cmd_hdd_wr <= rx_data[15:12]==4'b1001 ? 1 : 0;
		cmd_hdd_data_wr <= rx_data[15:12]==4'b1010 ? 1 : 0;
		cmd_hdd_data_rd <= rx_data[15:12]==4'b1011 ? 1 : 0;
	end

//disk activity LED
assign disk_led = dskstate!=DISKDMA_IDLE ? 1 : 0;
		
//main disk state machine
always @(posedge clk)
	if (reset)
		dskstate <= DISKDMA_IDLE;		
	else
		dskstate <= nextstate;
		
always @(dskstate or spidat or rx_data or dmaen or lenzero or enable or dsklen or bufempty or rx_flag or cmd_fdd or rx_cnt or bufwr_del)
begin
	case(dskstate)
		DISKDMA_IDLE://disk is present in flash drive
		begin
			trackrd=0;
			trackwr=0;
			dmaon=0;
			blckint=0;
			if (cmd_fdd && rx_flag && rx_cnt==1 && dmaen && !lenzero && enable)//dsklen>0 and dma enabled, do disk dma operation
				nextstate = DISKDMA_ACTIVE; 
			else
				nextstate = DISKDMA_IDLE;			
		end
		DISKDMA_ACTIVE://do disk dma operation
		begin
			trackrd=(~lenzero)&(~dsklen[14]);//track read (disk->ram)
			trackwr=dsklen[14];//track write (ram->disk)
			dmaon=(~lenzero)|(~dsklen[14]);
			blckint=0;
			if (!dmaen || !enable)
				nextstate = DISKDMA_IDLE;
			else if (lenzero && bufempty && !bufwr_del)//complete dma cycle done
				nextstate = DISKDMA_INT;
			else
				nextstate = DISKDMA_ACTIVE;			
		end
		DISKDMA_INT://generate disk dma completed (DSKBLK) interrupt
		begin
			trackrd=0;
			trackwr=0;
			dmaon=0;
			blckint=1;
			nextstate=DISKDMA_IDLE;			
		end
		default://we should never come here
		begin
			trackrd = 1'bx;
			trackwr = 1'bx;
			dmaon = 1'bx;
			blckint = 1'bx;
			nextstate = DISKDMA_IDLE;			
		end
	endcase

		
end


//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//8192 words deep, 16 bits wide, fifo
//data is written into the fifo when wr=1
//reading is more or less asynchronous if you read during the rising edge of clk
//because the output data is updated at the falling edge of the clk
//when rd=1, the next data word is selected 
module fifo
(
	input 	clk,		    	//bus clock
	input 	reset,			   	//reset 
	input	[15:0]din,		//data in
	output	reg [15:0]dout,	//data out
	input	rd,					//read from fifo
	input	wr,					//write to fifo
	output	full,				//fifo is full
	output	[13:0]cnt,
	output	reg empty			//fifo is empty
);

//local signals and registers
reg 	[15:0]mem[8191:0];	//8192 words by 16 bit wide fifo memory
reg		[13:0]inptr;			//fifo input pointer
reg		[13:0]outptr;			//fifo output pointer
wire	equal;					//lower 13 bits of inptr and outptr are equal

assign cnt = inptr - outptr;

//main fifo memory (implemented using synchronous block ram)
always @(posedge clk)
	if (wr && !full)
		mem[inptr[12:0]]<=din;
always @(posedge clk)
	dout=mem[outptr[12:0]];

//fifo write pointer control
always @(posedge clk)
	if(reset)
		inptr[13:0]<=0;
	else if(wr && !full)
		inptr[13:0]<=inptr[13:0]+1;

//fifo read pointer control
always @(posedge clk)
	if(reset)
		outptr[13:0]<=0;
	else if(rd && !empty)
		outptr[13:0]<=outptr[13:0]+1;

//check lower 13 bits of pointer to generate equal signal
assign equal=(inptr[12:0]==outptr[12:0])?1:0;

//assign output flags, empty is delayed by one clock to handle ram delay
always @(posedge clk)
	if(equal && (inptr[13]==outptr[13]))
		empty=1;
	else
		empty=0;	
assign full=(equal && (inptr[13]!=outptr[13]))?1:0;	

endmodule