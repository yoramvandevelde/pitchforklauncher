# JDK 17 is required for this project's Gradle/AGP version — newer JDKs fail dexing.
# See AGENTS.md. Adjust if your JDK 17 lives elsewhere.
java_home := "~/.local/share/mise/installs/java/temurin-17.0.19+10"

# Build a debug APK and install it on a device/emulator.
build-install device:
    #!/usr/bin/env bash
    set -euo pipefail
    export JAVA_HOME={{java_home}}
    export PATH="$JAVA_HOME/bin:$PATH"
    fvm flutter build apk --debug
    adb -s {{device}} install -r build/app/outputs/flutter-apk/app-debug.apk

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