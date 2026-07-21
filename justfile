# JDK 17 is required for this project's Gradle/AGP version — newer JDKs fail dexing.
# See AGENTS.md. Adjust if your JDK 17 lives elsewhere.
java_home := "~/.local/share/mise/installs/java/temurin-17.0.19+10"

# Build a debug APK and install it on a device/emulator. Stamps the version as
# today's date + "-local" (matching the release tag format, e.g. 2026.07.21-local),
# shown in Settings -> About FLauncher.
build-install device:
    #!/usr/bin/env bash
    set -euo pipefail
    export JAVA_HOME={{java_home}}
    export PATH="$JAVA_HOME/bin:$PATH"
    build_name="$(date +%Y.%m.%d)-local"
    fvm flutter build apk --debug --build-name="$build_name"
    adb -s {{device}} install -r build/app/outputs/flutter-apk/app-debug.apk

# Build a signed release APK and install it on a device/emulator, for testing a release
# build locally before cutting a tag. Same date + "-local" version stamp as build-install.
# build_number is the current unix timestamp -- always higher than the last build, so
# Android never refuses the install as a downgrade, no manual bumping needed. Requires
# SIGNING_KEYSTORE_PASSWORD, SIGNING_KEY_PASSWORD and SIGNING_KEY_ALIAS to already be
# exported, and android/app/upload-keystore.jks to be in place (see release.yml).
build-install-release device:
    #!/usr/bin/env bash
    set -euo pipefail
    export JAVA_HOME={{java_home}}
    export PATH="$JAVA_HOME/bin:$PATH"
    build_name="$(date +%Y.%m.%d)-local"
    build_number="$(date +%s)"
    fvm flutter build apk --release --build-name="$build_name" --build-number="$build_number"
    adb -s {{device}} install -r build/app/outputs/flutter-apk/app-release.apk

# README "Option A: make it the real default launcher" - disables the stock Google TV
# launcher (and the setup wizard, which would otherwise become the new fallback)
# so pressing Home prompts you to pick PitchforkLauncher instead.

# Disable the stock launcher so PitchforkLauncher can be set as Home.
disable-default-launcher device:
    adb -s {{device}} shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
    adb -s {{device}} shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
    @echo "Stock launcher disabled on {{device}}. Press Home on the remote and choose FLauncher when prompted."

# Undo: re-enable the stock launcher and setup wizard.
restore-default-launcher device:
    adb -s {{device}} shell pm enable com.google.android.apps.tv.launcherx
    adb -s {{device}} shell pm enable com.google.android.tungsten.setupwraith
    @echo "Stock launcher restored on {{device}}."