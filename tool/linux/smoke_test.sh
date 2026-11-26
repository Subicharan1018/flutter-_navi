#!/usr/bin/env bash
# Installs the .deb in a clean Ubuntu container and runs the real app.
# Run as root inside the container:  smoke_test.sh <dir with the .deb> <report dir>
#
# Checked: every library resolves from the package's own dependencies; the app
# opens a window and stays up; audio from a file reaches PulseAudio (a null
# sink, not a speaker); MPRIS reports and obeys play/pause; a second launch is
# forwarded to the running copy; closing the window exits cleanly; no error is
# logged. Once without a keyring, once with one and a comma-decimal locale.
set -euo pipefail

if [ "$(id -u)" = 0 ] && [ "${1:-}" != "--as-user" ]; then
  dist=$(realpath "$1"); report=$(realpath "$2"); self=$(realpath "$0")
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # The app alone first, without recommended extras: only what Depends names.
  apt-get install -y -qq --no-install-recommends "$dist"/NaviVibe-linux-x64.deb > /dev/null
  missing=$(LD_LIBRARY_PATH=/opt/navivibe/lib ldd /opt/navivibe/navivibe /opt/navivibe/lib/*.so | grep 'not found' | sort -u || true)
  if [ -n "$missing" ]; then
    echo "FAIL: libraries missing after installing the .deb:" | tee -a "$report/report.txt"
    echo "$missing" | tee -a "$report/report.txt"
    exit 1
  fi
  echo "PASS: .deb installs and every library resolves from its Depends" >> "$report/report.txt"
  # Test tools.
  apt-get install -y -qq --no-install-recommends xvfb xauth openbox wmctrl x11-utils \
    dbus dbus-x11 pulseaudio pulseaudio-utils ffmpeg imagemagick desktop-file-utils \
    locales procps libgl1-mesa-dri gdb > /dev/null
  desktop-file-validate /usr/share/applications/com.navivibe.navivibe.desktop
  echo "PASS: desktop entry is valid" >> "$report/report.txt"
  locale-gen de_DE.UTF-8 > /dev/null
  useradd -m tester
  useradd -m tester2
  chmod 777 "$report"; chmod 666 "$report/report.txt"
  cp "$self" /tmp/smoke.sh; chmod 755 /tmp/smoke.sh
  su tester -c "bash /tmp/smoke.sh --as-user bare '$report'"
  apt-get install -y -qq --no-install-recommends gnome-keyring libsecret-tools > /dev/null
  su tester2 -c "bash /tmp/smoke.sh --as-user keyring '$report'"
  exit 0
fi

# ── One scenario, as an ordinary user ────────────────────────────────────────
scenario=$2
report=$3
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  export XDG_RUNTIME_DIR=/tmp/run-$(id -u)
  mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
  exec dbus-run-session -- bash "$0" "$@"
fi
cd "$HOME"
log="$report/app-$scenario.log"
app_pid=""

say() { echo "$1" | tee -a "$report/report.txt"; }
fail() {
  say "FAIL [$scenario]: $1"
  echo "---- last 60 log lines ----" | tee -a "$report/report.txt"
  tail -n 60 "$log" 2>/dev/null | tee -a "$report/report.txt"
  find "$HOME" -name last_error.txt -exec head -c 3000 {} \; | tee -a "$report/report.txt"
  exit 1
}
pass() { say "PASS [$scenario]: $1"; }

# wait_for <seconds> <command...>
wait_for() {
  local t=$1; shift
  for _ in $(seq 1 "$t"); do
    if "$@" > /dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

export DISPLAY=:99
Xvfb :99 -screen 0 1280x800x24 -nolisten tcp > /dev/null 2>&1 &
xvfb_pid=$!
trap 'kill $app_pid ${wm_pid:-} $xvfb_pid 2>/dev/null || true; pulseaudio --kill 2>/dev/null || true' EXIT
wait_for 15 xdpyinfo || fail "Xvfb did not start"
openbox > /dev/null 2>&1 &
wm_pid=$!

pulseaudio --start --exit-idle-time=-1 > /dev/null 2>&1 || true
wait_for 15 pactl info || fail "PulseAudio did not start"
pactl load-module module-null-sink sink_name=speaker > /dev/null
pactl set-default-sink speaker

ffmpeg -loglevel error -y -f lavfi -i sine=frequency=440:duration=120 -ac 2 "$HOME/tone one.flac"
ffmpeg -loglevel error -y -f lavfi -i sine=frequency=660:duration=120 -ac 2 "$HOME/tone two.flac"

if [ "$scenario" = keyring ]; then
  export LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8   # libmpv refuses a comma-decimal LC_NUMERIC
  mkdir -p "$HOME/.local/share/keyrings"
  eval "$(printf '\n' | gnome-keyring-daemon --unlock --components=secrets)"
  echo -n probe | secret-tool store --label=probe smoke probe || fail "test keyring did not come up"
fi

start_app() {
  navivibe "$@" >> "$log" 2>&1 &
  app_pid=$!
}
alive() { kill -0 "$app_pid" 2>/dev/null; }
has_window() { wmctrl -l | grep -q 'NaviVibe$'; }
sink_input() { pactl list short sink-inputs | grep -q .; }
mpris_name() {
  dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.ListNames | grep -o 'org\.mpris\.MediaPlayer2\.com\.navivibe[^"]*' | head -1
}
mpris_get() {
  dbus-send --session --print-reply --dest="$(mpris_name)" /org/mpris/MediaPlayer2 \
    org.freedesktop.DBus.Properties.Get string:org.mpris.MediaPlayer2.Player string:"$1"
}
mpris_is() { mpris_get PlaybackStatus | grep -q "\"$1\""; }
mpris_call() {
  dbus-send --session --print-reply --dest="$(mpris_name)" /org/mpris/MediaPlayer2 \
    "org.mpris.MediaPlayer2.Player.$1" > /dev/null
}
# Loudest sample on the null sink over 3 s, in dB (silence is about -91).
loudness() {
  timeout 3 parec -d speaker.monitor --format=s16le --rate=44100 --channels=2 > /tmp/cap-$scenario.raw || true
  ffmpeg -hide_banner -f s16le -ar 44100 -ac 2 -i /tmp/cap-$scenario.raw -af volumedetect -f null - 2>&1 \
    | sed -n 's/.*max_volume: \(-\?[0-9.]*\) dB.*/\1/p'
}
loud() { local v; v=$(loudness); [ -n "$v" ] && awk -v v="$v" 'BEGIN { exit !(v > -50) }'; }
no_errors() {
  local bad
  # One line is allowed: Flutter's GTK engine prints the atk_socket_embed
  # assertion when there is no accessibility bus (a container has none).
  bad=$(grep -nE 'Unhandled [Ee]xception|EXCEPTION CAUGHT|\[ERROR:flutter|Failed assertion|MissingPluginException|-CRITICAL \*\*|Segmentation fault|Error loading artUri|^#0 |Audio engine unavailable|AudioService\.init failed|OfflineService\.initialize failed|Non-numeric locale' "$log" \
    | grep -v "atk_socket_embed: assertion 'plug_id != NULL' failed" || true)
  [ -z "$bad" ] || fail "errors in the log ($1):
$bad"
  local crash
  crash=$(find "$HOME" -name last_error.txt | head -1)
  [ -z "$crash" ] || fail "the app recorded an uncaught error ($1)"
}

: > "$log"
start_app "$HOME/tone one.flac"
wait_for 60 has_window || fail "no NaviVibe window within 60 s"
pass "window opened"
wait_for 45 sink_input || fail "no audio stream reached PulseAudio"
sleep 3
wait_for 15 loud || fail "the audio stream is silent"
pass "the file named on the command line plays: sound reaches PulseAudio (null sink)"

wait_for 20 mpris_name || fail "no MPRIS player on the session bus"
wait_for 10 mpris_is Playing || fail "MPRIS does not report Playing: $(mpris_get PlaybackStatus)"
mpris_get Metadata | grep -q 'tone one' || fail "MPRIS metadata has no title: $(mpris_get Metadata)"
mpris_call PlayPause
wait_for 10 mpris_is Paused || fail "MPRIS PlayPause did not pause"
sleep 2
if loud; then fail "still audible after pause"; fi
mpris_call PlayPause
wait_for 10 mpris_is Playing || fail "MPRIS PlayPause did not resume"
wait_for 15 loud || fail "silent after resume"
pass "MPRIS reports the song; pause and resume work"

timeout 30 navivibe "$HOME/tone two.flac" >> "$report/second-$scenario.log" 2>&1 || fail "second launch did not exit 0"
[ "$(pgrep -u "$(id -u)" -cx navivibe)" = 1 ] || fail "a second copy stayed running"
wait_for 15 grep -q 'forwarded by a second launch: 1' "$log" || fail "the running copy did not receive the file"
second_title() { mpris_get Metadata | grep -q 'tone two'; }
wait_for 20 second_title || fail "the forwarded file did not start"
pass "a second launch hands its file to the running window"

sleep 30
alive || fail "the app exited on its own"
no_errors "while running"
pass "still running after 30 more seconds, no errors logged"
import -window root /tmp/shot-$scenario.png && cp /tmp/shot-$scenario.png "$report/screen-$scenario.png"

wmctrl -c NaviVibe
gone() { ! kill -0 "$app_pid" 2>/dev/null; }
wait_for 20 gone || fail "closing the window did not end the app"
set +e; wait "$app_pid"; code=$?; set -e
# A native backtrace of a crash at close, with and without a song playing.
close_backtrace() {
  command -v gdb > /dev/null || return 0
  for song in "$HOME/tone one.flac" ""; do
    say "---- backtrace at close (${song:+playing}${song:-idle}) ----"
    gdb -batch -nx -ex 'handle SIGPIPE nostop noprint pass' -ex run -ex bt -ex 'info sharedlibrary libmpv' \
      --args /opt/navivibe/navivibe ${song:+"$song"} > /tmp/gdb.log 2>&1 &
    local gdb_pid=$!
    wait_for 60 has_window || true
    sleep 15
    wmctrl -c NaviVibe || true
    wait_for 60 sh -c "! kill -0 $gdb_pid 2>/dev/null" || kill "$gdb_pid"
    sed -n '/received signal\|exited normally\|exited with/,$p' /tmp/gdb.log | cut -c1-220 | head -n 30 \
      | tee -a "$report/backtrace.txt"
  done
}
if [ "$code" != 0 ]; then
  close_backtrace
  fail "exit code $code after closing the window"
fi
no_errors "at close"
pass "closing the window exits with code 0"

# Second start, on the data the first run left behind.
start_app
wait_for 60 has_window || fail "no window on the second start"
sleep 15
alive || fail "the second start did not stay up"
no_errors "second start"
pass "starts again on existing data"
import -window root /tmp/idle-$scenario.png && cp /tmp/idle-$scenario.png "$report/idle-$scenario.png"
wmctrl -c NaviVibe
wait_for 20 gone || fail "second close did not end the app"

if [ "$scenario" = bare ]; then
  grep -q 'No usable keyring' "$log" || fail "expected the no-keyring path"
  key=$(find "$HOME/.local/share" -name auth.key | head -1)
  [ -n "$key" ] && [ "$(stat -c %a "$key")" = 600 ] || fail "key file missing or not mode 600"
  pass "without a keyring: starts, key file is mode 600"
else
  if grep -q 'No usable keyring' "$log"; then fail "the working keyring was not used"; fi
  pass "with a keyring and a German locale"
fi
