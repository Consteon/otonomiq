#!/bin/bash
echo Android Cleanup builds
cp -f lib/part/android_part/channel_android.dart_ lib/part/build_part/channel.dart
flutter clean
echo appbundle build
flutter build appbundle --release
echo copying to FrontezReleases
cp -f ~/Frontez/autsorz/build/app/outputs/bundle/release/app-release.aab ~/"hsangkanparan@vertesc.com - Google Drive"/"My Drive"/FrontezReleases/autsorzmobile_0_9_new.aab
echo Done!
