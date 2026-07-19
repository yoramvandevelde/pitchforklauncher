# README "Method 2: disable the default launcher" — disables the stock Google TV
# launcher (and the setup wizard, which would otherwise become the new fallback)
# so pressing Home prompts you to pick FLauncher instead.

# Disable the stock launcher so FLauncher can be set as Home.
disable-default-launcher device:
    adb -s {{device}} shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
    adb -s {{device}} shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
    @echo "Stock launcher disabled on {{device}}. Press Home on the remote and choose FLauncher when prompted."

# Undo: re-enable the stock launcher and setup wizard.
restore-default-launcher device:
    adb -s {{device}} shell pm enable com.google.android.apps.tv.launcherx
    adb -s {{device}} shell pm enable com.google.android.tungsten.setupwraith
    @echo "Stock launcher restored on {{device}}."