rem make ZIP archive
tar.exe -a -c -f FS22_CropRotation.zip^
 data^
 gui^
 utils^
 maps^
 translations^
 CropRotation.lua^
 CropRotation.xml^
 CropRotationData.lua^
 CropRotationPlanner.lua^
 CropRotationSettings.lua^
 icon_cropRotation.dds^
 modDesc.xml


rem copy ZIP to FS22 mods folder
rem xcopy /b/v/y FS22_CropRotation.zip "D:\Users\Bodzio\Documents\My Games\FarmingSimulator2022\mods"

rem make update mod as well
rem copy /b/v/y FS22_CropRotation.zip FS22_CropRotation_update.zip
