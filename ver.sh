#!/bin/bash
set +x
content=$(cat pubspec.yaml)
version_line=$(echo "$content" | grep '^version:')
version_string=$(echo "$version_line" | cut -d ':' -f 2 | tr -d ' ')
IFS='+' read -r version build_number <<< "$version_string"
IFS='.' read -r major minor patch <<< "$version"
if [ -n "$build_number" ]; then
  build_number=$(echo "$build_number" | sed 's/^0*//')
  result="${major}_${minor}_${patch}_${build_number: -2}"
else
  result="${major}_${minor}_${patch}"
fi
set -x
echo "$result"