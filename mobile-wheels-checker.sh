xcodebuild -scheme mobile-wheels-checker -configuration Release -destination 'platform=macOS' -derivedDataPath .build
.build/Build/Products/Release/mobile-wheels-checker $@