# source tools/env.sh — toolchain installed on the Grok Bot box for D0 (2026-10-10)
[ -d "$HOME/jdk" ] && export JAVA_HOME=$HOME/jdk   # Temurin 17.0.20.1 on the bot box; containers set JAVA_HOME themselves
[ -d "$HOME/android-sdk" ] && export ANDROID_HOME=$HOME/android-sdk   # cmdline-tools latest, platforms;android-35, build-tools;35.0.0, platform-tools
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=${JAVA_HOME:+$JAVA_HOME/bin:}$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/kotlin/kotlinc/bin:$HOME/gradle-8.14.3/bin:$PATH
export ADB=$ANDROID_HOME/platform-tools/adb
