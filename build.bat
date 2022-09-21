rem make ZIP archive
tar.exe -a -c -f FS22_CropRotation.zip modDesc.xml modIcon.dds data gui utils translations main.lua CropRotation.lua CropRotationData.lua CropRotationPlanner.lua

rem copy ZIP to FS22 mods folder
xcopy /b/v/y FS22_CropRotation.zip "%userprofile%\Documents\My Games\FarmingSimulator2022\mods"

rem make update mod as well
copy /b/v/y FS22_CropRotation.zip FS22_CropRotation_update.zip
