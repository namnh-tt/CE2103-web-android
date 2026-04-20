#!/usr/bin/env bash
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
JAVA_HOME="${JAVA_HOME:-$HOME/android-studio/jbr}"
AVD_NAME="${AVD_NAME:-alert_phone_api24}"
ADB_BIN="$ANDROID_SDK_ROOT/platform-tools/adb"
EMULATOR_BIN="$ANDROID_SDK_ROOT/emulator/emulator"
EMULATOR_LOG="${TMPDIR:-/tmp}/${AVD_NAME}.log"
EMULATOR_MEMORY="${EMULATOR_MEMORY:-1536}"
EMULATOR_CORES="${EMULATOR_CORES:-2}"

find_avd_serial() {
  while read -r serial state; do
    [[ "${serial:-}" == emulator-* ]] || continue
    [[ "${state:-}" == device || "${state:-}" == offline ]] || continue

    local avd_name
    avd_name="$("$ADB_BIN" -s "$serial" emu avd name 2>/dev/null | sed -n '1p' | tr -d '\r')"
    if [[ "$avd_name" == "$AVD_NAME" ]]; then
      printf '%s\n' "$serial"
      return 0
    fi
  done < <("$ADB_BIN" devices | tail -n +2)

  return 1
}

if [[ ! -x "$ADB_BIN" || ! -x "$EMULATOR_BIN" ]]; then
  echo "Android SDK tools not found under $ANDROID_SDK_ROOT" >&2
  exit 1
fi

export ANDROID_SDK_ROOT JAVA_HOME

"$ADB_BIN" start-server >/dev/null

if ! serial="$(find_avd_serial)"; then
  emulator_args=(
    -avd "$AVD_NAME"
    -no-audio
    -no-boot-anim
    -no-snapshot
    -gpu swiftshader_indirect
    -memory "$EMULATOR_MEMORY"
    -cores "$EMULATOR_CORES"
  )

  if [[ "${ANDROID_HEADLESS:-0}" == "1" ]]; then
    emulator_args+=(-no-window)
  fi

  setsid -f "$EMULATOR_BIN" \
    "${emulator_args[@]}" \
    >"$EMULATOR_LOG" 2>&1

  for _ in {1..120}; do
    if serial="$(find_avd_serial)"; then
      break
    fi
    sleep 2
  done
fi

if [[ -z "${serial:-}" ]]; then
  echo "Emulator $AVD_NAME did not appear. Check $EMULATOR_LOG" >&2
  exit 1
fi

"$ADB_BIN" -s "$serial" wait-for-device >/dev/null

for _ in {1..180}; do
  if [[ "$("$ADB_BIN" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    break
  fi
  sleep 2
done

if [[ "$("$ADB_BIN" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; then
  echo "Emulator boot timed out. Check $EMULATOR_LOG" >&2
  exit 1
fi

"$ADB_BIN" -s "$serial" shell input keyevent 82 >/dev/null 2>&1 || true

exec flutter run -d "$serial" "$@"
