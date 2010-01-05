/*
Copyright 2008, 2009 Jakub Bednarski

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

-- Goran Ljubojevic --
2009-11-15	- Copied from ARM Source
2009-11-16	- GetHardfileGeometry fixed signed change
			- BuildHardfileIndex removed - no memory on pic
			- HardFileSeek - removed in favor if standard (fat16.h) - FileSeek(struct fileTYPE *file, unsigned long sector)
2009-11-17	- OpenHardfile modified to current pic code
			- IdentifyDevice modified to current pic code
2009-11-18	- HandleHDD moddified to current pic code
2009-11-21	- Debug info consolidated (spport still not working)
2009-11-22	- Fixed working but slooooow
2009-11-26	- Added Direct transfer mode to FPGA
			- Changed cluster size on card to 32kb to test faster transfer, now works better
2009-12-20	- Added extension check for HD File
2009-12-30	- Added constants for detected ide commands
			- Added ideREGS structure to simplify ide handling code
*/

#include <pic18.h>
#include <stdio.h>
#include <string.h>
#include "config.h"
#include "mmc.h"
#include "fat16.h"
#include "hdd.h"
#include "hardware.h"


// hardfile structure
struct hdfTYPE hdf[2];


// helper function for byte swapping
void SwapBytes(char *ptr, unsigned long len)
{
    char x;
    len >>= 1;
    while (len--)
    {
        x = *ptr;
        *ptr++ = ptr[1];
        *ptr++ = x;
    }
}


// builds Identify Device struct
void IdentifyDevice(struct driveIdentify *id, unsigned char unit)
{
	unsigned long total_sectors = hdf[unit].cylinders * hdf[unit].heads * hdf[unit].sectors;

	// Clear identity 
	memset(id, 0, sizeof(id));

	id->general = 1 << 6;								// hard disk type
	id->noCylinders = hdf[unit].cylinders;				// cyl count
	id->noHeads  = hdf[unit].heads;						// head count
	id->noSectorsPerTrack = hdf[unit].sectors;			// sectors per track
	memcpy(&id->serialNo, "1234567890ABCDEFGHIJ", 20);	// serial number - byte swapped
	memcpy(&id->firmwareRevision, ".100    ", 8);		// firmware version - byte swapped

	// model name - byte swapped
	memcpy(&id->modelNumber,"YAQUBE                                  ", 40);
	// copy file name as model name
	memcpy(&id->modelNumber[8], hdf[unit].file.name, 11);

	SwapBytes(&id->modelNumber, 40);

	id->isValidCHS = 1;
	id->curNoCylinders = hdf[unit].cylinders;
	id->curNoHeads = hdf[unit].heads;
	id->curNoSectorsPerTrack = hdf[unit].sectors;
	id->curCapacityInSectors = total_sectors;
//	id->curCapacityInSectors = hdf[unit].cylinders * hdf[unit].heads * hdf[unit].sectors;
}


unsigned long chs2lba(unsigned short cylinder, unsigned char head, unsigned char sector, unsigned char unit)
{
	unsigned long res;

	// TODO: Optimize calculation
	res = cylinder;
	res *= (unsigned long)hdf[unit].heads;
	res += (unsigned long)head;
	res *= (unsigned long)hdf[unit].sectors;
	res += sector;
	res -= 1;
	
//	return(cylinder * hdf[unit].heads + head) * hdf[unit].sectors + sector - 1;
    return res;
}


void BeginHDDTransfer(unsigned char cmd, unsigned char status)
{
    EnableFpga();
    SPI(cmd);
    SPI(status);
    SPI(0x00);
    SPI(0x00);
    SPI(0x00);
    SPI(0x00);
}

void WriteTaskFile(unsigned char error, unsigned char sector_count, unsigned char sector_number, unsigned char cylinder_low, unsigned char cylinder_high, unsigned char drive_head)
{
	/*
	EnableFpga();
	SPI(CMD_IDE_REGS_WR);	// write task file registers command
	SPI(0x00);
	SPI(0x00);				// dummy
	SPI(0x00);
	SPI(0x00);				// dummy
	SPI(0x00);
	*/
	
	// write task file registers command
	BeginHDDTransfer(CMD_IDE_REGS_WR, 0x00);
	
	SPI(0x00);				// dummy
	SPI(0x00);
	
	SPI(0x00);
	SPI(error);				// error
    
	SPI(0x00);
    SPI(sector_count);		// sector count
    
    SPI(0x00);
    SPI(sector_number);		//sector number
    
    SPI(0x00);
    SPI(cylinder_low);		// cylinder low
    
    SPI(0x00);
    SPI(cylinder_high);		// cylinder high
    
    SPI(0x00);
    SPI(drive_head);		// drive/head

    DisableFpga();
}


void WriteStatus(unsigned char status)
{
/*
	EnableFpga();

    SPI(CMD_IDE_STATUS_WR);
    SPI(status);
    SPI(0x00);
    SPI(0x00);
    SPI(0x00);
    SPI(0x00);
*/
	BeginHDDTransfer(CMD_IDE_STATUS_WR, status);
    DisableFpga();
}


void HandleHDD(unsigned char c1, unsigned char c2)
{
	struct driveIdentify	id;
	unsigned char	*buffer;
	unsigned char	tfr[8];
	unsigned short	i;
	unsigned long	lba;
	unsigned char	sector;
	unsigned short	cylinder;
	unsigned char	head;
	unsigned char	unit;

	if (c1 & CMD_IDECMD)
	{
		DISKLED_ON;

		/*
		EnableFpga();
		SPI(CMD_IDE_REGS_RD); // read task file registers
		SPI(0x00);
		SPI(0x00);
		SPI(0x00);
		SPI(0x00);
		SPI(0x00);
		*/
		BeginHDDTransfer(CMD_IDE_REGS_RD, 0x00);
		for (i = 0; i < 8; i++)
		{
			SPI(0);
			tfr[i] = SPI(0);
		}
		DisableFpga();

		// master/slave selection
		unit = tfr[6] & IDEREGS_DRIVE_MASK ? 1 : 0;

		if ((tfr[7] & 0xF0) == ACMD_RECALIBRATE)
		{
			// Recalibrate 0x10-0x1F (class 3 command: no data)
			#ifdef HDD_DEBUG
			HDD_Debug("Recalibrate\r\n", tfr);
			#endif

			WriteTaskFile(0, 0, 1, 0, 0, tfr[6] & 0xF0);
			WriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
		}
		else if (tfr[7] == ACMD_IDENTIFY_DEVICE)
		{
			// Identify Device 0xEC
			#ifdef HDD_DEBUG
			HDD_Debug("Identify Device\r\n", tfr);
			#endif

        	IdentifyDevice(&id, unit);
        	WriteTaskFile(0, tfr[2], tfr[3], tfr[4], tfr[5], tfr[6]);
        	WriteStatus(IDE_STATUS_RDY); // pio in (class 1) command type
        	/*
        	EnableFpga();
        	SPI(CMD_IDE_DATA_WR); // write data command
        	SPI(0x00);
        	SPI(0x00);
        	SPI(0x00);
        	SPI(0x00);
        	SPI(0x00);
        	*/
    		BeginHDDTransfer(CMD_IDE_DATA_WR, 0x00);
        	buffer = (unsigned char*)&id;
        	for(i=0; i < (sizeof(id)); i++)
	        {	SPI(*(buffer++));	}
        	for(; i < 512; i++)
	        {	SPI(0);		}
        	DisableFpga();

        	WriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
        }
        else if (tfr[7] == ACMD_INITIALIZE_DEVICE_PARAMETERS)
        {
        	// Initiallize Device Parameters
			#ifdef HDD_DEBUG
			HDD_Debug("Initialize Device Parametars\r\n", tfr);
			#endif

        	WriteTaskFile(0, tfr[2], tfr[3], tfr[4], tfr[5], tfr[6]);
        	WriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
        }
        else if (tfr[7] == ACMD_READ_SECTORS)
        {
        	// Read Sectors 0x20
        	WriteStatus(IDE_STATUS_RDY); // pio in (class 1) command type

        	sector = tfr[3];
        	cylinder = tfr[4] | (tfr[5] << 8);
        	head = tfr[6] & 0x0F;
        	lba = chs2lba(cylinder, head, sector, unit);

			#ifdef HDD_DEBUG
			HDD_Debug("Read\r\n", tfr);
			printf("CHS: %d.%d.%d\r\n", cylinder, head, sector);
        	printf("Read LBA:0x%08lX/SC:0x%02X\r\n", lba, tfr[2]);
        	#endif

        	// TODO: Optimize file size check 
        	if (hdf[unit].file.len)
        	{
        		FileSeek(&hdf[unit].file, lba);
        		
				#ifdef ALOW_MMC_DIRECT_TRANSFER_MODE
        		
        			MMC_DIRECT_TRANSFER_MODE = 1;
        			FileRead(&hdf[unit].file);
        			MMC_DIRECT_TRANSFER_MODE = 0;

        		#else
        		
	        		FileRead(&hdf[unit].file);
	        		/*
	            	// write data command
	        		EnableFpga();
	            	SPI(CMD_IDE_DATA_WR);
	            	SPI(0x00);
	            	SPI(0x00);
	            	SPI(0x00);
	            	SPI(0x00);
	            	SPI(0x00);
	            	*/
	            	// write data command
	        		BeginHDDTransfer(CMD_IDE_DATA_WR, 0x00);
	            	// Send Sector
	            	for(i=0; i < 512; i++)
		            {	SPI(secbuf[i]);	}
	            	DisableFpga();

            	#endif
        	}

        	// decrease sector count
        	tfr[2]--;
        	// advance to next sector unless the last one is to be transmitted
        	if (tfr[2])
        	{
        		if (sector == hdf[unit].sectors)
        		{
        			sector = 1;
        			head++;
        			if (head == hdf[unit].heads)
        			{
        				head = 0;
        				cylinder++;
        			}
        		}
        		else
        		{	sector++;	}
        	}

        	WriteTaskFile(0, tfr[2], sector, (unsigned char)cylinder, (unsigned char)(cylinder >> 8), (tfr[6] & 0xF0) | head);
        	WriteStatus((tfr[2] ? 0 : IDE_STATUS_END) | IDE_STATUS_IRQ);
        }
        else if (tfr[7] == ACMD_WRITE_SECTORS)
        {
        	// write sectors
            sector = tfr[3];
			cylinder = tfr[4] | (tfr[5] << 8);
            head = tfr[6] & 0x0F;
            lba = chs2lba(cylinder, head, sector, unit);
            
			#ifdef HDD_DEBUG
			HDD_Debug("Write\r\n", tfr);
        	printf("Write LBA:0x%08lX/SC:0x%02X\r\n", lba, tfr[2]);
			#endif

        	// TODO: Optimize file size check
			if (hdf[unit].file.len)
			{
        		FileSeek(&hdf[unit].file, lba);
			}

            // pio out (class 2) command type
            WriteStatus(IDE_STATUS_REQ);

/*
            do
            {
                EnableFpga();
                c1 = SPI(0); // cmd request and drive number
                SPI(0x00);
                SPI(0x00);
                SPI(0x00);
                SPI(0x00);
                SPI(0x00);
                DisableFpga();
            }
            while (!(c1 & CMD_IDEDAT));
*/
            // cmd request and drive number
            while (!(GetFPGAStatus()& CMD_IDEDAT));

            /*
            EnableFpga();
            SPI(CMD_IDE_DATA_RD); // read data command
            SPI(0x00);
            SPI(0x00);
            SPI(0x00);
            SPI(0x00);
            SPI(0x00);
            */
    		BeginHDDTransfer(CMD_IDE_DATA_RD, 0x00);
            for (i = 0; i < 512; i++)
            {  	secbuf[i] = SPI(0xFF);		}
            DisableFpga();

        	// TODO: Optimize file size check
            if (hdf[unit].file.len)
            {	FileWrite(&hdf[unit].file);	}

            // decrease sector count
            tfr[2]--;
            // advance to next sector unless the last one is to be transmitted
            if (tfr[2])
            {
                if (sector == hdf[unit].sectors)
                {
                    sector = 1;
                    head++;
                    if (head == hdf[unit].heads)
                    {
                        head = 0;
                        cylinder++;
                    }
                }
                else
                {   sector++;	}
            }

            WriteTaskFile(0, tfr[2], sector, (unsigned char)cylinder, (unsigned char)(cylinder >> 8), (tfr[6] & 0xF0) | head);
            WriteStatus((tfr[2] ? 0 : IDE_STATUS_END) | IDE_STATUS_IRQ);
        }
        else
        {
			#ifdef HDD_DEBUG
			HDD_Debug("Unknown ATA command\r\nIDE:", tfr);
			#endif

            WriteTaskFile(0x04, tfr[2], tfr[3], tfr[4], tfr[5], tfr[6]);
            WriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ | IDE_STATUS_ERR);
        }

        DISKLED_OFF;
    }
}



// this function comes from WinUAE, should return the same CHS as WinUAE
void GetHardfileGeometry(struct hdfTYPE *pHDF)
{
	unsigned long total;
	unsigned long i, head, cyl, spt;
//	unsigned long sptt[] = { 63, 127, 255, -1 };
	unsigned long sptt[] = { 63, 127, 255 };

	if (0 == pHDF->file.len)
	{	return;		}

	total = pHDF->file.len >> 9;		//total = pHDF->file.len / 512

//	for (i = 0; sptt[i] >= 0; i++)
	for (i = 0; i < 3; i++)
	{
		spt = sptt[i];
		for (head = 4; head <= 16; head++)
		{
			cyl = total / (head * spt);
			//if (pHDF->file.len <= (512 * 1024 * 1024))	// Strange But not Working
			if (pHDF->file.len <= 536870912)				//(pHDF->file.len <= 512 * 1024 * 1024)
			{
				if (cyl <= 1023)
				{	break;	}
			}
			else
			{
				if (cyl < 16383)
				{	break;	}
				if (cyl < 32767 && head >= 5)
				{	break;	}
				if (cyl <= 65535)
				{	break;	}
			}
		}
		if (head <= 16)
		{	break;	}
	}

	pHDF->cylinders = (unsigned short)cyl;
	pHDF->heads = (unsigned short)head;
	pHDF->sectors = (unsigned short)spt;
}


unsigned char OpenHardfile(unsigned char unit, unsigned char *name)
{
	if (name[0] && (0 == strncmp(&name[8],defHardDiskExt,3)))
	{
		#ifdef HDD_DEBUG
		printf("\r\nTrying to open hard file: %s\r\n", name);
		#endif

		if (Open(&hdf[unit].file, name))
		{
			GetHardfileGeometry(&hdf[unit]);

			#ifdef HDD_DEBUG
			printf("HARDFILE %d:\r\n", unit);
			printf("file: \"%s\"\r\n", hdf[unit].file.name);
			printf("size: 0x%08lX (0x%08lX MB)\r\n", hdf[unit].file.len, hdf[unit].file.len >> 20);
			printf("CHS: %d.%d.%d", hdf[unit].cylinders, hdf[unit].heads, hdf[unit].sectors);
			printf(" (%lu MB)\r", ((((unsigned long) hdf[unit].cylinders) * hdf[unit].heads * hdf[unit].sectors) >> 11));
			#endif

			// Hard file found
			hdf[unit].present = 1;
			return 1;
		}
	}

	// Not Found
	hdf[unit].present = 0;
    return 0;
}

#ifdef HDD_DEBUG

void HDD_Debug(const char *msg, unsigned char *tfr)
{
	int i;
//	printf("\r\n");
	printf(msg);
	for(i=0; i < 7; i++)
	{	printf("0x%02X ", *(tfr++));	}
	printf("0x%02X\r\n", *(tfr++));
}

#endif

