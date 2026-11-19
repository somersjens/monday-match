#!/bin/zsh
# Copies the app's sound palette into Android resource form, so the future
# Android app plays the same sounds. Run after generate_sounds.py.
#
# Android plays AAC (.m4a) as is, but not Core Audio (.caf): the notification
# chime becomes 16-bit WAV (notification channels need WAV, OGG or MP3) and
# the 24-second ambience bed becomes AAC, which stays small. Android resource
# names allow only lowercase letters, digits and underscores, so "-" becomes
# "_". The notification chime becomes the sound of the "Matches & messages"
# notification channel (res/raw/notification_chime.wav).
set -euo pipefail
root="${0:A:h}/../.."
source="$root/Stop Swiping/Resources/Sounds"
target="$root/platform-assets/android/res/raw"
rm -rf "$target"
mkdir -p "$target"
for file in "$source"/*; do
  name="${${file:t:r}//-/_}"
  case "$file" in
    *notification-chime.caf) afconvert -f WAVE -d LEI16 "$file" "$target/$name.wav" ;;
    *.caf) afconvert -f m4af -d aac -b 160000 "$file" "$target/$name.m4a" ;;
    *.m4a) cp "$file" "$target/$name.m4a" ;;
  esac
done
ls "$target" | wc -l | xargs echo "Android sounds written:"
