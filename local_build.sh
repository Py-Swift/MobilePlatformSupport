xcodebuild -scheme mobile-wheels-checker -configuration Release -destination 'platform=macOS' -derivedDataPath .build
mkdir -p .build/Build/Products/lib
cp -rf .build/Build/Products/Release/PackageFrameworks/RealmSwift.framework .build/Build/Products/lib/