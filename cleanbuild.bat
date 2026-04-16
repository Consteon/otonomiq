(
cls
rem flutter build appbundle --release --no-tree-shake-icons
rem flutter build apk --split-per-abi
flutter clean
flutter build appbundle --release
)