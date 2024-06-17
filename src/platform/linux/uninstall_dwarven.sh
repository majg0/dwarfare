#!/bin/sh

# NOTE: must match name in .desktop file
name=dwarven

# user_path=~/.local/share
# rm ${user_path}/applications/${name}.desktop
# rm ${user_path}/icons/hicolor/16x16/apps/${name}.png
# rm ${user_path}/icons/hicolor/32x32/apps/${name}.png
# rm ${user_path}/icons/hicolor/48x48/apps/${name}.png
# rm ${user_path}/icons/hicolor/64x64/apps/${name}.png
# rm ${user_path}/icons/hicolor/128x128/apps/${name}.png
# rm ${user_path}/icons/hicolor/256x256/apps/${name}.png

# NOTE: requires sudo
system_path=/usr/share
rm ${system_path}/applications/${name}.desktop
rm ${system_path}/icons/hicolor/16x16/apps/${name}.png
rm ${system_path}/icons/hicolor/32x32/apps/${name}.png
rm ${system_path}/icons/hicolor/48x48/apps/${name}.png
rm ${system_path}/icons/hicolor/64x64/apps/${name}.png
rm ${system_path}/icons/hicolor/128x128/apps/${name}.png
rm ${system_path}/icons/hicolor/256x256/apps/${name}.png
