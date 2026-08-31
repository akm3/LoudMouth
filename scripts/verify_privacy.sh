#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
entitlements="$project_root/LoudMouth/LoudMouth.entitlements"
privacy_manifest="$project_root/LoudMouth/Resources/PrivacyInfo.xcprivacy"
source_root="$project_root/LoudMouth"

fail() {
    echo "Privacy boundary failed: $1" >&2
    exit 1
}

plist_value() {
    plutil -extract "$1" raw -o - "$2" 2>/dev/null
}

entitlement_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$entitlements" 2>/dev/null
}

[[ "$(entitlement_value 'com.apple.security.app-sandbox')" == "true" ]] \
    || fail "App Sandbox must remain enabled."
[[ "$(entitlement_value 'com.apple.security.device.audio-input')" == "true" ]] \
    || fail "Microphone access must remain explicit."

entitlement_count="$(/usr/libexec/PlistBuddy -c Print "$entitlements" | rg -c ' = ')"
[[ "$entitlement_count" == "2" ]] \
    || fail "The entitlement allowlist is exactly App Sandbox plus microphone input."

for entitlement in \
    com.apple.security.network.client \
    com.apple.security.network.server \
    com.apple.security.files.user-selected.read-only \
    com.apple.security.files.user-selected.read-write \
    com.apple.security.files.downloads.read-only \
    com.apple.security.files.downloads.read-write \
    com.apple.security.files.all; do
    if entitlement_value "$entitlement" >/dev/null; then
        fail "Forbidden entitlement present: $entitlement"
    fi
done

[[ "$(plist_value NSPrivacyTracking "$privacy_manifest")" == "false" ]] \
    || fail "Tracking must be declared false."
[[ "$(plutil -extract NSPrivacyTrackingDomains json -o - "$privacy_manifest")" == "[]" ]] \
    || fail "Tracking domains must remain empty."
[[ "$(plutil -extract NSPrivacyCollectedDataTypes json -o - "$privacy_manifest")" == "[]" ]] \
    || fail "Collected data types must remain empty."

forbidden_pattern='URLSession|NSURLConnection|CFNetwork|NWConnection|NWEndpoint|WebSocket|import[[:space:]]+(Network|WebKit|Speech)|SFSpeechRecognizer|AVAudioRecorder|AVAudioFile|AudioFileCreate|ExtAudioFile|Firebase|Sentry|Datadog|TelemetryDeck|PostHog|Mixpanel|Amplitude'

if rg -n --glob '*.swift' "$forbidden_pattern" "$source_root"; then
    fail "A networking, recording, transcription, or analytics API was introduced."
fi

echo "Privacy boundary verified: no network permission, recording APIs, tracking, or collected data."
