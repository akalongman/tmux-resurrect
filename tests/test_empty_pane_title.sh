#!/usr/bin/env bash
# A pane whose program cleared its title (OSC 2 with an empty string, what a
# TUI does on exit) must save and restore with its working directory intact,
# and a title that contains a colon must survive the round trip unchanged.
#
# Runs on a private tmux server through a PATH shim, so the plugin's own
# `tmux` calls never reach the user's server or save directory. Needs only
# tmux on PATH; no Vagrant, no expect.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
REAL_TMUX="$(command -v tmux)" || { echo "tmux not found" >&2; exit 1; }

if ! T="$(mktemp -d)" || [ -z "$T" ] || [ ! -d "$T" ]; then
	echo "mktemp -d failed; refusing to run against the live tmux server" >&2
	exit 1
fi
cleanup() {
	tmux kill-server 2>/dev/null
	rm -rf "$T"
}
trap cleanup EXIT

mkdir "$T/bin" "$T/work"
: > "$T/tmux.conf"
cat > "$T/bin/tmux" <<SHIM
#!/bin/sh
exec "$REAL_TMUX" -f "$T/tmux.conf" -S "$T/sock" "\$@"
SHIM
chmod +x "$T/bin/tmux"
export PATH="$T/bin:$PATH"
unset TMUX_PANE
# run-shell hands the plugin TMUX=<socket>,<pid>,<session>; restore.sh takes the
# socket for its new-session calls from it, so it must name the private one.
export TMUX="$T/sock,0,0"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }
assert_eq() { # description expected actual
	if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}

# wait_title target expected: poll until the pane title equals expected (5 s).
wait_title() {
	for _ in $(seq 1 50); do
		[ "$(tmux display -p -t "$1" '#{pane_title}')" = "$2" ] && return 0
		sleep 0.1
	done
	return 1
}

# The environment: window 0 clears its title, window 1 carries a colon in its.
tmux new-session -d -s probe -c "$T/work" -x 80 -y 24 "printf '\\033]2;\\007'; exec /bin/sh"
tmux new-window -d -t probe -c "$T/work" /bin/sh
tmux select-pane -t probe:1 -T 'LS: Main'
tmux set-option -g @resurrect-dir "$T/resurrect"
wait_title probe:0 '' || fail "the title of probe:0 never became empty"
wait_title probe:1 'LS: Main' || fail "the title of probe:1 was not set"

"$SCRIPTS/save.sh" quiet
last="$T/resurrect/last"
[ -f "$last" ] || { fail "no save file at $last"; exit 1; }
assert_eq "empty-title pane saved with its directory in the directory column" \
	":$T/work" "$(awk -F'\t' '$1 == "pane" && $2 == "probe" && $3 == 0 { print $8 }' "$last")"
assert_eq "colon-title pane saved with its directory in the directory column" \
	":$T/work" "$(awk -F'\t' '$1 == "pane" && $2 == "probe" && $3 == 1 { print $8 }' "$last")"

# A fresh server with one throwaway pane, as after a boot.
tmux kill-server
tmux new-session -d -s boot -c / /bin/sh
tmux set-option -g @resurrect-dir "$T/resurrect"
"$SCRIPTS/restore.sh" >/dev/null 2>&1
tmux has-session -t probe 2>/dev/null || fail "the probe session was not restored"

assert_eq "empty-title pane restored into its directory" \
	"$T/work" "$(tmux display -p -t probe:0 '#{pane_current_path}')"
assert_eq "empty-title pane restored with an empty title" \
	"" "$(tmux display -p -t probe:0 '#{pane_title}')"
assert_eq "colon-title pane restored into its directory" \
	"$T/work" "$(tmux display -p -t probe:1 '#{pane_current_path}')"
assert_eq "colon-title pane restored with its title" \
	"LS: Main" "$(tmux display -p -t probe:1 '#{pane_title}')"

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failure(s)"; exit 1; fi
