#!/bin/sh
set -eu
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$app_dir"
device="${1:-macos}"
if [ "$device" = macos ]; then
  host=127.0.0.1
else
  host="${MUCAP_HOST:-$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || true)}"
  if [ -z "$host" ]; then
    echo 'Mac의 Wi-Fi IP를 찾을 수 없습니다. MUCAP_HOST=주소를 지정하세요.' >&2
    exit 1
  fi
fi
endpoint="http://$host:${MUCAP_PORT:-8765}"
curl --fail --silent --show-error --max-time 3 "$endpoint/health"
printf '\nMuCap: %s\n' "$endpoint"
if [ "$device" = macos ]; then
  exec flutter run -d "$device" --dart-define="MUCAP_API_URL=$endpoint/analyze"
else
  exec flutter run --release -d "$device" --dart-define="MUCAP_API_URL=$endpoint/analyze"
fi
