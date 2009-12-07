/*
Copyright 2005, 2006, 2007 Dennis van Weeren

This file is part of Minimig

Minimig is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

Minimig is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

Minimig boot controller / floppy emulator / on screen display

27-11-2005	- started coding
29-01-2005	- done a lot of work
06-02-2006	- it start to look like something!
19-02-2006	- improved floppy dma offset code
02-01-2007	- added osd support
11-02-2007	- added insert floppy progress bar
01-07-2007	- added filetype filtering for directory routines

JB:
2008-02-09	- added error handling
			number of blinks:
			1: neither mmc nor sd card detected
			2: fat16 filesystem not detected
			3: FPGA configuration error (INIT low or DONE high before config)
			4: no MINIMIG1.BIN file found
			5: FPGA configuration error (DONE is low after config)
			6: no kickstart file found

2008-07-18	- better read support (sector loaders are now less confused)
			- write support added (strict sector format checking - may not work with non DOS games)
			- removed bug in filename filtering (initial directory fill didn't filter)
			- communication interface with new bootloader
			- OSD control of reset, ram configuration, interpolation filters and kickstart

WriteTrack errors:
	#20 : unexpected dma transfer end (sector header)
	#21 : no second sync word found
	#22 : first header byte not 0xFF
	#23 : second header byte (track number) not within 0..159 range
	#24 : third header byte (sector number) not within 0..10 range
	#25 : fourth header byte (sectors to gap number) not within 1..11 range
	#26 : header checksum error
	#27 : track number in sector header not the same as drive head position
	#28 : unexpected dma transfer end (sector data)
	#29 : data checksum error
	#30 : write attempt to protected disk

2008-07-25	- update of write sector header format checking
			- disk led active during writes to disk

2009-03-01	- porting of ARM firmware features
2009-03-13	- forcing of PAL/NTSC mode with F1/F2 key after uploading FPGA configuration
2009-03-22	- fixed disabling of Action Replay ROM loading
			- changed cursor position after ADF file selection
			- now ESC allows to exit OSD menu
2009-04-05	- Action Replay may be disabled by pressing MENU button while its ROM upload should start

-- Goran Ljubojevic ---
2009-08-30	- separated fileBrowser.c to overcome compiler ram issues
2009-09-10	- Directory selection
2009-09-20	- Supporty for new FPGA bin 090911 by yaqube
2009-11-13	- Max Floppy Drives added
 			- Floppy selection reworked
2009-11-14	- HandleFDD moved to adf.c
			- UpdateDriveStatus to adf.c
			- Added extra menu for settigns and reset
2009-11-21	- menu moved to separate files
2009-11-30	- Code cleaned a bit, string replaced with constants 
2009-12-04	- HDD Detection added
2009-12-05	- Boot Wait before key read replaced with wait function
*/

#include <pic18.h>
#include <stdio.h>
#include <string.h>
#include "boot.h"
#include "hardware.h"
#include "osd.h"
#include "mmc.h"
#include "fat16.h"
#include "adf.h"
#include "fileBrowser.h"
#include "hdd.h"
#include "menu.h"
#include "config.h"

// Enable / Disable debug output
//#define DEBUG_MAIN

const char version[] = { "$VER:" DEF_TO_STRING(FPGA_REV) "\0" };

void HandleFpga(void);

//global temporary buffer for strings
unsigned char s[25];


/* This is where it all starts after reset */
void main(void)
{
	unsigned short time;
	unsigned char tmp;
//	unsigned long t;

	// Reset Floppy status
	memset(df,0,sizeof(df));
	// Reset HD status
	memset(hdf,0,sizeof(hdf));

	// initialize hardware
	HardwareInit();

	printf("Minimig by Dennis van Weeren\r\n");
	printf("Bug fixes, mods and extensions by Jakub Bednarski\r\n");
	printf("SDHC, FAT16/32, Dir, LFN, HDD support by Goran Ljubojevic\r\n\r\n");
	printf("Version %s\r\n\r\n", version+5);

	// Load Config form eeprom
	LoadConfiguration();

	// intialize mmc card
	if (!MMC_Init())
	{	FatalError(1);	}

	// initalize FAT partition
	if (!FindDrive())
	{
		#ifdef MAIN_DEBUG
		printf("No FAT16/32 filesystem!\r\n");
		#endif
		FatalError(2);
	}

//	if (DONE) //FPGA has not been configured yet
//	{		printf("FPGA already configured\r\n");		}
	else
	{
		/*configure FPGA*/
		if (ConfigureFpga())
		{	printf("\r\nFPGA configured\r\n");	}
		else
		{
			#ifdef MAIN_DEBUG
			printf("\r\nFPGA configuration failed\r\n");
			#endif
			FatalError(3);
		}
	}

	//let's wait some time till reset is inactive so we can get a valid keycode
//	t = 38000;
//	while (--t)
//	{	DISKLED_OFF;	}

	DISKLED_OFF;
	WaitTimer(50);
	
	//get key code
	tmp = OsdGetCtrl();

	if (tmp == KEY_F1)	{	config.chipset |= 0x04;	}		//force NTSC mode
	if (tmp == KEY_F2)	{	config.chipset &= ~0x04;	}	//force PAL mode

	ConfigChipset(config.chipset|0x01);	//force CPU turbo mode

	if (config.chipset & 0x04)			//reset if NTSC mode requested because FPGA boots in PAL mode by default
	{	OsdReset(1);	}

	ConfigFloppy(1, 1);					//high speed mode for ROM loading

	sprintf(s, "PIC firmware %s\n", version+5);
	BootPrint(s);

	sprintf(s, "CPU clock     : %s MHz", config.chipset & 0x01 ? "28.36": "7.09");
	BootPrint(s);

	sprintf(s, "Blitter speed : %s", config.chipset & 0x02 ? "fast": "normal");
	BootPrint(s);
	
	sprintf(s, "Chip RAM size : %s", config_memory_chip_msg[config.memory&3]);
	BootPrint(s);
	
	sprintf(s, "Slow RAM size : %s", config_memory_slow_msg[config.memory>>2&3]);
	BootPrint(s);

	sprintf(s, "Floppy drives : %d", config.floppy_drives + 1);
	BootPrint(s);

	sprintf(s, "Floppy speed  : %s\n", config.floppy_speed ? "2x": "1x");
	BootPrint(s);

	// Load Kickstart
	if (UploadKickstart(config.kickname))
	{
		strcpy(config.kickname, defKickName);
		if (UploadKickstart(config.kickname))
		{	FatalError(6);	}
	}

	//load Action Replay ROM if not disabled
	if (config.ar3 && !CheckButton())
	{	
		if(UploadActionReplay(defARName))
		{	FatalError(7);		}
	}


	#ifdef HDD_SUPPORT_ENABLE

	// Hard drives config 
    sprintf(s, "\nA600 IDE HDC is %s.", config.ide ? "enabled" : "disabled");
    BootPrint(s);
	
    tmp=0;
	do
	{
		// Copy config file name to temp string for HD File open search
		strncpy(s, hdf[tmp].file.name, 12);
		if (!OpenHardfile(tmp, s))
	    {
			// Not Found, try default name
			sprintf(s, defHDFileName, tmp);
			OpenHardfile(tmp, s);
	    }

	    // Display Info
	    sprintf(s, "%s HDD is %s.\n", tmp ? "Slave" : "Master",
	    	hdf[tmp].present ? (hdf[tmp].enabled ? "enabled" : "disabled") : "not present"
	    );
	    BootPrint(s);

	    // Display Present HDD file info
	    if(hdf[tmp].present)
	    {
	    	sprintf(s, "File: %s", hdf[tmp].file.name);
	    	BootPrint(s);

	    	sprintf(s, "CHS: %d.%d.%d", hdf[tmp].cylinders, hdf[tmp].heads, hdf[tmp].sectors);
	    	BootPrint(s);
	    	
	    	sprintf(s, "Size: %ld MB\n", ((((unsigned long) hdf[tmp].cylinders) * hdf[tmp].heads * hdf[tmp].sectors) >> 11));
	    	BootPrint(s);
	    }

	    // Next HD File
	}
	while ((++tmp) < 2);

	/*
    if (selectedPartiton.clusterSize < 64)
    {
        BootPrint("\n***************************************************");
        BootPrint(  "*  It's recommended to reformat your memory card  *");
        BootPrint(  "*   using 32 KB clusters to improve performance   *");
        BootPrint(  "***************************************************");
    }
	*/

	// Finally Config IDE
	ConfigIDE(config.ide, hdf[0].present & hdf[0].enabled, hdf[1].present & hdf[1].enabled);
	#endif

	
	#ifdef MAIN_DEBUG
	printf("Bootloading is complete.\r\n");
	#endif

	BootPrint("Exiting bootloader...\n");

	// Wait 2 sec for OSD show just to be able to see on screen stuff
	WaitTimer(200);
	
	//config memory and chipset features
	ConfigMemory(config.memory);
	ConfigChipset(config.chipset);
	ConfigFloppy(config.floppy_drives, config.floppy_speed);

	BootExit();

	ConfigFilter(config.filter_lores, config.filter_hires);	//set interpolation filters
	ConfigScanline(config.scanline);						//set scanline effect

	/******************************************************************************/
	/*  System is up now                                                          */
	/******************************************************************************/

	// get initial timer for checking user interface
	time = GetTimer(5);

	while (1)
	{
		// handle command
		HandleFpga();

		// handle user interface
		if (CheckTimer(time))
		{
			time = GetTimer(2);
			HandleUI();
		}
	}
}


// Handle an FPGA command
void HandleFpga(void)
{
	unsigned char  c1, c2;

	EnableFpga();
	c1 = SPI(0);	//cmd request and drive number
	c2 = SPI(0);	//track number
	SPI(0);
	SPI(0);
	SPI(0);
	SPI(0);
	DisableFpga();

	HandleFDD(c1,c2);
	
	#ifdef HDD_SUPPORT_ENABLE
	HandleHDD(c1,c2);
	#endif

	UpdateDriveStatus();
}



