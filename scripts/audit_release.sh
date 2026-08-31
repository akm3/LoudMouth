#!/bin/bash

set -euo pipefail

app_bundle="${1:-}"
[[ -n "$app_bundle" && -d "$app_bundle" ]] || {
    echo "Usage: $0 /path/to/LoudMouth.app" >&2
    exit 2
}

fail() {
    echo "Release privacy audit failed: $1" >&2
    exit 1
}

codesign --verify --deep --strict "$app_bundle" \
    || fail "The app signature is invalid."

entitlements="$(codesign -d --entitlements - "$app_bundle" 2>/dev/null)"
[[ "$(printf '%s\n' "$entitlements" | rg -c '\[Key\]')" == "2" ]] \
    || fail "The signed app must contain exactly two entitlements."
printf '%s\n' "$entitlements" | rg -q 'com\.apple\.security\.app-sandbox' \
    || fail "The signed app is missing App Sandbox."
printf '%s\n' "$entitlements" | rg -q 'com\.apple\.security\.device\.audio-input' \
    || fail "The signed app is missing microphone input."
if printf '%s\n' "$entitlements" | rg -q 'network|files\.|downloads|assets|automation|temporary-exception'; then
    fail "The signed app contains a network, file, automation, or exception entitlement."
fi

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_bundle/Contents/Info.plist")"
executable="$app_bundle/Contents/MacOS/$executable_name"
privacy_manifest="$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"

[[ -f "$privacy_manifest" ]] || fail "PrivacyInfo.xcprivacy is missing."
[[ "$(plutil -extract NSPrivacyTracking raw -o - "$privacy_manifest")" == "false" ]] \
    || fail "The release declares tracking."
[[ "$(plutil -extract NSPrivacyTrackingDomains json -o - "$privacy_manifest")" == "[]" ]] \
    || fail "The release contains tracking domains."
[[ "$(plutil -extract NSPrivacyCollectedDataTypes json -o - "$privacy_manifest")" == "[]" ]] \
    || fail "The release declares collected data."

if otool -L "$executable" | rg -q 'CFNetwork|Network\.framework|WebKit|Speech\.framework'; then
    fail "The executable directly links a networking, web, or transcription framework."
fi

if nm -u "$executable" | rg -q 'URLSession|NSURLConnection|NWConnection|_socket|WebSocket|SFSpeech|AVAudioRecorder|AVAudioFile'; then
    fail "The executable references a forbidden network, recording, or transcription symbol."
fi

echo "Release privacy audit passed: signed sandbox, microphone-only entitlement, no network-linked code, zero tracking, and zero collected data."
