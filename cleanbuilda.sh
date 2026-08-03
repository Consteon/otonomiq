#!/bin/bash
echo Android Cleanup builds
cp -f lib/part/android_part/channel_android.dart_ lib/part/build_part/channel.dart
flutter clean
echo appbundle build
flutter build appbundle --release
echo copying to FrontezReleases
cp -f build/app/outputs/bundle/release/app-release.aab "/Users/harryhuang/Library/CloudStorage/GoogleDrive-hsangkanparan@consteon.com/Shared drives/authenium/Main/01_Authenium/Dev/apps/frontez-engine/frontez-releases/autsorzmobile_0_9_new.aab"
echo Done!
