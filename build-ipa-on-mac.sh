#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

npm ci
npx cap sync ios

echo "Открываю проект в Xcode."
echo "Выберите Team в Signing & Capabilities, затем Product > Archive > Distribute App."
npx cap open ios
