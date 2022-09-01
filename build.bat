rem make ZIP archive
tar.exe -a -c -f FS22_CropRotation_update.zip modDesc.xml modIcon.dds gui misc translations main.lua CropRotation.lua CropRotationData.lua

rem copy ZIP to FS22 mods folder
xcopy /b/v/y FS22_CropRotation_update.zip "%userprofile%\Documents\My Games\FarmingSimulator2022\mods"

rem make mod update
rem xcopy /b/v/y FS22_CropRotation.zip FS22_CropRotation_update.zip
