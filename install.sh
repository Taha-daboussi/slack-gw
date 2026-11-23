#!/usr/bin/env bash
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)"
tool=slack-gw
bin="$HOME/.local/bin"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/$tool"
backups="${XDG_STATE_HOME:-$HOME/.local/state}/$tool/install-backup/$(date +%s)"

backup() {
  mkdir -p "$backups"
  mv "$1" "$backups/$(basename "$1")"
  echo "backup: $backups/$(basename "$1")"
}

mkdir -p "$bin" "$units"
if [ ! -L "$bin/$tool" ] || [ "$(readlink "$bin/$tool")" != "$src/bin/$tool" ]; then
  if [ -e "$bin/$tool" ] || [ -L "$bin/$tool" ]; then backup "$bin/$tool"; fi
  ln -s "$src/bin/$tool" "$bin/$tool"
  echo "linked: $bin/$tool -> $src/bin/$tool"
fi
if ! cmp -s "$src/systemd/$tool.service" "$units/$tool.service"; then
  if [ -e "$units/$tool.service" ]; then backup "$units/$tool.service"; fi
  install -m 644 "$src/systemd/$tool.service" "$units/$tool.service"
  echo "installed: $units/$tool.service"
fi
systemctl --user daemon-reload

if [ ! -e "$conf/config.json" ]; then
  install -d -m 700 "$conf"
  install -m 600 "$src/config.example.json" "$conf/config.json"
  echo "created $conf/config.json from the example: put your own ids in it"
fi

missing=()
for t in uv browser-harness systemctl; do command -v "$t" >/dev/null || missing+=("$t"); done
[ ${#missing[@]} -eq 0 ] || echo "missing tools: ${missing[*]}"
echo "next: $tool login, then systemctl --user enable --now $tool"
