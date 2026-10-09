#!/bin/zsh
# Prüft den Kern (Sensiplan-Auswertung, Speicherung, Backups) und – falls Xcode installiert ist – baut die App.
set -e
cd "$(dirname "$0")/.."

echo "▶ Kernlogik prüfen (NFPCore)…"
(cd NFPCore && swift run -c debug NFPCoreChecks)

if xcodebuild -version >/dev/null 2>&1; then
  echo "▶ App für den iOS-Simulator bauen…"
  xcodebuild -project MyNFP.xcodeproj -scheme MyNFP -destination 'generic/platform=iOS Simulator' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build | tail -5
else
  echo "ℹ︎ Xcode nicht gefunden – App-Build übersprungen."
fi
