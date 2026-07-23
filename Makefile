.PHONY: project build test run

project:
	xcodegen generate

build: project
	xcodebuild -project TokenScope.xcodeproj -scheme TokenScope -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

test: project
	xcodebuild -project TokenScope.xcodeproj -scheme TokenScope -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO test

run: project
	xcodebuild -project TokenScope.xcodeproj -scheme TokenScope -configuration Debug -derivedDataPath build-signed CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES build
	open build-signed/Build/Products/Debug/TokenScope.app
