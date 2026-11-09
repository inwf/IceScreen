on run argv
    set diskFolder to (POSIX file (item 1 of argv)) as alias
    set backgroundPath to item 2 of argv
    tell application "Finder"
        tell folder diskFolder
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {100, 100, 760, 522}
            set iconOptions to icon view options of container window
            set arrangement of iconOptions to not arranged
            set icon size of iconOptions to 128
            set text size of iconOptions to 13
            set background picture of iconOptions to ((POSIX file backgroundPath) as alias)
            set position of item "IceScreen.app" to {180, 205}
            set position of item "Applications" to {480, 205}
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
