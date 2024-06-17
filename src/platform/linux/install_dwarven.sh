#!/bin/sh

# NOTE: must match name in .desktop file
name=dwarven

# user_path=~/.local/share
# mkdir -p ${user_path}/applications
# cp ${name}.desktop ${user_path}/applications/${name}.desktop
# mkdir -p ${user_path}/icons/hicolor/16x16/apps
# mkdir -p ${user_path}/icons/hicolor/32x32/apps
# mkdir -p ${user_path}/icons/hicolor/48x48/apps
# mkdir -p ${user_path}/icons/hicolor/64x64/apps
# mkdir -p ${user_path}/icons/hicolor/128x128/apps
# mkdir -p ${user_path}/icons/hicolor/256x256/apps
# cp ../../../assets/icon_16.png ${user_path}/icons/hicolor/16x16/apps/${name}.png
# cp ../../../assets/icon_32.png ${user_path}/icons/hicolor/32x32/apps/${name}.png
# cp ../../../assets/icon_48.png ${user_path}/icons/hicolor/48x48/apps/${name}.png
# cp ../../../assets/icon_64.png ${user_path}/icons/hicolor/64x64/apps/${name}.png
# cp ../../../assets/icon_128.png ${user_path}/icons/hicolor/128x128/apps/${name}.png
# cp ../../../assets/icon_256.png ${user_path}/icons/hicolor/256x256/apps/${name}.png

# NOTE: requires sudo
system_path=/usr/share
mkdir -p ${system_path}/applications
sudo cp -r ${name}.desktop ${system_path}/applications/${name}.desktop
mkdir -p ${system_path}/icons/hicolor/16x16/apps
mkdir -p ${system_path}/icons/hicolor/32x32/apps
mkdir -p ${system_path}/icons/hicolor/48x48/apps
mkdir -p ${system_path}/icons/hicolor/64x64/apps
mkdir -p ${system_path}/icons/hicolor/128x128/apps
mkdir -p ${system_path}/icons/hicolor/256x256/apps
sudo cp -r ../../../assets/icon_16.png ${system_path}/icons/hicolor/16x16/apps/${name}.png
sudo cp -r ../../../assets/icon_32.png ${system_path}/icons/hicolor/32x32/apps/${name}.png
sudo cp -r ../../../assets/icon_48.png ${system_path}/icons/hicolor/48x48/apps/${name}.png
sudo cp -r ../../../assets/icon_64.png ${system_path}/icons/hicolor/64x64/apps/${name}.png
sudo cp -r ../../../assets/icon_128.png ${system_path}/icons/hicolor/128x128/apps/${name}.png
sudo cp -r ../../../assets/icon_256.png ${system_path}/icons/hicolor/256x256/apps/${name}.png
