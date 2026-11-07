#!/bin/bash
# Whitespace, empty entries, duplicate entries, '//', './' and trailing '/'
# are cleaned up; nested paths get their parent directories created.
# shellcheck disable=SC2088 # "~" in labels and option values is meant literally
set -e

source dev-container-features-test-lib

VOL=/mnt/home-persistence
expected="$(printf 'd .a\nd b/c\nf .config/tool/settings.json\nf my file')"

check "entries normalized" test "$(cat /usr/local/share/home-persistence/entries)" = "$expected"
check "~/.a links into volume" test "$(readlink "$HOME/.a")" = "$VOL/.a"
check "~/b/c links into volume" test "$(readlink "$HOME/b/c")" = "$VOL/b/c"
check "~/b is a real directory" sh -c 'test -d "$HOME/b" && test ! -L "$HOME/b"'
check "nested file links into volume" test "$(readlink "$HOME/.config/tool/settings.json")" = "$VOL/.config/tool/settings.json"
check "parent directory created in volume" test -d "$VOL/.config/tool"
check "path with space links into volume" test "$(readlink "$HOME/my file")" = "$VOL/my file"
check "write to nested file lands in volume" sh -c 'echo "{}" > "$HOME/.config/tool/settings.json" && test -f /mnt/home-persistence/.config/tool/settings.json'

reportResults
