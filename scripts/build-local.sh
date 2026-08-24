#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Lokalweb.xcodeproj \
  -scheme Lokalweb \
  -configuration Release \
  -derivedDataPath .build/ReleaseDerived \
  build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=

product="$project_root/.build/ReleaseDerived/Build/Products/Release/Lokalweb.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$product/Contents/Info.plist")"
archive="$project_root/.build/Lokalweb-$version-local.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$product" "$archive"

echo "App: $product"
echo "Local archive: $archive"
echo "This archive is ad-hoc signed for local use and is not a notarized public release."
