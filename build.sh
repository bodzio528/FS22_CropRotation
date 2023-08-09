#! /bin/sh

# make ZIP archive
rm -f FS22_CropRotation.zip FS22_CropRotation_update.zip
zip FS22_CropRotation.zip \
 data/* \
 gui/guiProfiles.xml \
 gui/helplineImages01.dds \
 gui/helplineImages02.dds \
 gui/helpLine.xml \
 gui/InGameMenuCropRotationPlanner.lua \
 gui/InGameMenuCropRotationPlanner.xml \
 gui/menuIcon.dds \
 utils/* \
 maps/* \
 translations/* \
 utils/* \
 CropRotation.lua \
 CropRotation.xml \
 CropRotationData.lua \
 CropRotationPlanner.lua \
 CropRotationSettings.lua \
 icon_cropRotation.dds \
 modDesc.xml

# make update mod as well
cp -f FS22_CropRotation.zip FS22_CropRotation_update.zip

