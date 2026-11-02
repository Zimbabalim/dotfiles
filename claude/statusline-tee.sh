#!/bin/bash
# Claude Code status line.
# 1. Saves Claude Code's statusline JSON (context usage, model, cost) to ~/.cache/claude-context/
#    for the nvim context card (<leader>ai, ~/.config/nvim/lua/context_panel.lua).
# 2. Hands the JSON on to claude-hud (https://github.com/jarrodwatts/claude-hud) if it's installed,
#    otherwise prints a simple "[Model] 12% context" line.

input=$(cat)

dir="$HOME/.cache/claude-context"
mkdir -p "$dir"
id=$(printf '%s' "$input" | /usr/bin/python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null)
[ -n "$id" ] && printf '%s' "$input" > "$dir/$id.json.tmp" && mv "$dir/$id.json.tmp" "$dir/$id.json"

# Newest installed claude-hud version.
plugin_dir=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/claude-hud/*/ 2>/dev/null \
  | awk -F/ '{ print $(NF-1) "\t" $0 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\t' \
  | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -f2-)

# Node: PATH first, then the newest nvm install, then Homebrew.
node=$(command -v node 2>/dev/null)
[ -z "$node" ] && node=$(ls -d "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | sort -V | tail -1)
[ -z "$node" ] && for n in /opt/homebrew/bin/node /usr/local/bin/node; do [ -x "$n" ] && node=$n && break; done

if [ -n "$plugin_dir" ] && [ -n "$node" ]; then
  cols=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
  export COLUMNS=$(( ${cols:-120} > 4 ? ${cols:-120} - 4 : 1 ))
  printf '%s' "$input" | exec "$node" "${plugin_dir}dist/index.js"
fi

printf '%s' "$input" | /usr/bin/python3 -I -c '
import json, sys
d = json.load(sys.stdin)
cw = d.get("context_window") or {}
print("[%s] %s%% context" % ((d.get("model") or {}).get("display_name", "Claude"), cw.get("used_percentage") or 0))
'
