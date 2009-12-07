#ifndef MENU_H_
#define MENU_H_

// menu states
enum MENU
{
	MENU_NONE1,
	MENU_NONE2,
	MENU_MAIN1,
	MENU_MAIN2,
	MENU_MAIN_EXT1,
	MENU_MAIN_EXT2,
	MENU_FILE1,
	MENU_FILE2,
	MENU_FLOPPY_SELECTED,
	MENU_RESET1,
	MENU_RESET2,
	MENU_SETTINGS1,
	MENU_SETTINGS2,
	MENU_ROMFILESELECTED1,
	MENU_ROMFILESELECTED2,
	MENU_SETTINGS_VIDEO1,
	MENU_SETTINGS_VIDEO2,
	MENU_SETTINGS_MEMORY1,
	MENU_SETTINGS_MEMORY2,
	MENU_SETTINGS_CHIPSET1,
	MENU_SETTINGS_CHIPSET2,
	MENU_SETTINGS_DRIVES1,
	MENU_SETTINGS_DRIVES2,
	MENU_ERROR,
	MENU_SETTINGS_HARDFILE1,
	MENU_SETTINGS_HARDFILE2,
	MENU_HARDFILE_SELECTED,
};

// Extern exposed variables
extern const char * const config_memory_chip_msg[];
extern const char * const config_memory_slow_msg[];

void HandleUI(void);
void HandleUpDown(unsigned char state, unsigned char max);
void SelectFile(const char* extension, unsigned char selectedState, unsigned char exitState, unsigned char allowDirectorySelect);

void ErrorMessage(const char* message, unsigned char code);


#endif /*MENU_H_*/
