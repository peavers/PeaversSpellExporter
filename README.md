# PeaversSpellExporter

[![GitHub commit activity](https://img.shields.io/github/commit-activity/m/peavers/PeaversSpellExporter)](https://github.com/peavers/PeaversSpellExporter/commits/master) [![Last commit](https://img.shields.io/github/last-commit/peavers/PeaversSpellExporter)](https://github.com/peavers/PeaversSpellExporter/master) [![CurseForge](https://img.shields.io/curseforge/dt/000000?label=CurseForge&color=F16436)](https://www.curseforge.com/wow/addons/peaversspellexporter)

## Overview

PeaversSpellExporter is a World of Warcraft addon that extracts all player-castable spells for your current class and
specialization, presenting them in a simple, clean interface. This lightweight tool is perfect for addon developers,
theorycrafters, or anyone who needs a comprehensive list of their character's available spells with their corresponding
spell IDs.

## Features

- **Complete Spell Extraction**: Automatically scans your spellbook and talent tree to capture all available spells for
  your current character.
- **C_Spell API Compatible**: Uses modern WoW APIs for maximum compatibility with current and future game versions.
- **Clean CSV Format**: Presents spell data in a simple SpellID,SpellName format for easy export and use in spreadsheets
  or other tools.
- **Specialization Aware**: Detects and categorizes spells by your current specialization for more accurate spell lists.
- **Spell Name Resolution**: Advanced spell name resolution for spells that might not load immediately.
- **Movable Interface**: Simple, draggable window to view your spell data.
- **Performance Optimized**: Efficient code design that minimizes memory and CPU usage.

## How to Use

1. **Install the Addon**
	* Download and install PeaversSpellExporter via the CurseForge app or manually place it in the World of Warcraft
	  `Interface/AddOns` folder.

2. **Enable the Addon**
	* Ensure PeaversSpellExporter is enabled in your addons list on the character selection screen.

3. **Basic Commands**
	* Type `/spellexport` to scan spells and show the results window
	* Type `/spellexport scan` to scan spells without showing the window
	* Type `/spellexport show` to show the window with previously scanned spells
	* Type `/spellexport clear` to clear spell data for your current class/spec
	* Type `/spellexport clearcache` to clear the spell name cache

4. **Using the Results**
	* The spell data is presented in a simple CSV format that can be copied and pasted into a spreadsheet
	* Each spell is listed with its Spell ID and Name
	* Press ESC to close the focus on the text area

## Troubleshooting

If some spell names appear as "Spell #12345" instead of their actual names:

1. These spells may not have loaded yet - the addon will attempt to resolve them automatically
2. Try using the `/spellexport scan` command again after playing for a while
3. If issues persist, use `/spellexport clearcache` to clear the spell name cache and try scanning again

## Feedback and Support

If you encounter any issues or have suggestions for improvements, please submit them
via [GitHub Issues](https://github.com/peavers/PeaversSpellExporter/issues). Your feedback is valuable in enhancing the
addon experience for all players.

## Note for Developers

This addon was designed to be a clean, lightweight tool for extracting spell information. It uses the modern C_Spell
APIs when available for maximum compatibility.
