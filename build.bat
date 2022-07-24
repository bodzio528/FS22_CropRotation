rem make ZIP archive
tar.exe -a -c -f FS22_CropRotation.zip main.lua CropRotation.lua CropRotationData.lua modDesc.xml modIcon.dds

rem copy ZIP to FS22 mods folder
xcopy /b/v/y FS22_CropRotation.zip "%userprofile%\Documents\My Games\FarmingSimulator2022\mods"
