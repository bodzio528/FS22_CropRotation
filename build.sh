#! /bin/env sh

zip --version

zip -r FS22_CropRotation_update.zip \
 modDesc.xml \
 modIcon.dds \
 data \
 gui \
 utils \
 translations \
 main.lua \
 CropRotation.lua \
 CropRotationData.lua
