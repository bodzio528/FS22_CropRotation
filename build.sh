#! /bin/env sh

zip --version

zip -r FS22_CropRotation_update.zip \
 modDesc.xml \
 modIcon.dds \
 gui \
 utils \
 translations \
 main.lua \
 CropRotation.lua \
 CropRotationData.lua
