#!/bin/sh
# Script to compile Appium.app and release it onto GitHub

# The below token definition should be performed by Jenkins using the credentials plugin
# GITHUB_OAUTH_TOKEN=""

# The below release name should be provided by injected variables from the Jenkins build configuration
# RELEASE_NAME=""

# The below file removals should not need to be used, if Jenkins is set to clean the workspace
# rm -rf release
# rm -rf Appium.xcarchive
# rm -f Appium.dmg

# The below clone should be performed by Jenkins using the Git plugin
# git clone --recursive https://github.com/appium/appium-dot-app.git

# Compile and archive the project
echo "compiling project"
xcodebuild -project Appium.xcodeproj -scheme Appium -archivePath Appium archive | grep -A 5 "(error|FAILED)"

# Evaluate the status of the build
if [ ! -d Appium.xcarchive ]; then
	echo "export failed"
	exit 1
fi

# Create release directory
mkdir -p "release"

# Evaluate the status of the directory creation
if [ $? != 0 ]; then
	echo "release directory creation failed"
	exit 1
fi

# Export the xcarchive file to an app
echo "exporting app"
xcodebuild -exportArchive -exportFormat APP -archivePath Appium.xcarchive -exportPath release/Appium | grep -A 5 "(error|FAILED)"

# Evaluate the status of the export
if [ ! -d release/Appium.app ]; then
	echo "export failed"
	exit 1
fi

# Create a DMG with a size of the app plus 1 whole unit (MB|KB)
echo "creating dmg"
APP_SIZE=$(du -hs release/Appium.app/ | cut -f -1)
hdiutil create -srcfolder release -volname Appium -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size $(echo $APP_SIZE | sed s/./$((${APP_SIZE%.*} + 1))/1) -quiet Appium.dmg

# Evaluate the status of the DMG creation
if [ $? != 0 ]; then
	echo "dmg creation failed"
	exit 1
fi

# Create a new release
echo "creating release"
GITHUB_UPLOAD_URL=$(curl -s -u $GITHUB_OAUTH_TOKEN:x-oauth-basic -X POST -H "Content-Type: application/json" -d '{"tag_name": "'"$RELEASE_NAME"'", "target_commitish": "master", "name": "'"$RELEASE_NAME"'", "body": "Automation build", "draft": false, "prerelease": true}' "https://api.github.com/repos/appium/appium-dot-app/releases" | \
	python -c 'import json, sys; data = json.load(sys.stdin); print str(data["upload_url"]).replace("{?name}", "") if "upload_url" in data else "";')"?name=Appium.dmg"

# Evaluate status of the release creation
if [ "$GITHUB_UPLOAD_URL" == "" ]; then
	echo "release creation failed"
	exit 1
fi

# Upload the DMG
echo "uploading artifact"
GITHUB_RELEASE_URL=$(curl -s -u $GITHUB_OAUTH_TOKEN:x-oauth-basic -X POST -H "Content-Type: application/x-apple-diskimage" --data-binary @Appium.dmg "$GITHUB_UPLOAD_URL" | \
	python -c 'import json, sys; data = json.load(sys.stdin); print str(data["browser_download_url"]) if "browser_download_url" in data else "";')

# Evaluate status of the upload
if [ "$GITHUB_RELEASE_URL" != "" ]; then
	echo "artifact published at $GITHUB_RELEASE_URL"
	exit 0
else
	echo "artifact upload failed"
	exit 1
fi
