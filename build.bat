rem make ZIP archive
tar.exe -a -c -f FS22_CropRotation.zip data translations CropRotation.lua CropRotationData.lua main.lua modDesc.xml modIcon.dds

rem copy ZIP to FS22 mods folder
xcopy /b/v/y FS22_CropRotation.zip "%userprofile%\Documents\My Games\FarmingSimulator2022\mods"
