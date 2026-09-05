#!/bin/bash
# Installs this folder as an Omarchy shell plugin.
#
#   ./install.sh          copies it to ~/.config/omarchy/plugins/<id>/ (recommended)
#   ./install.sh --link   symlinks it — see the warning below
#
# Nothing to move if the repository already sits in place: the script then just
# (re)declares the plugin to the shell.
#
# The symlink is fine to try things out, but the shell watches
# ~/.config/omarchy/plugins without following links, so a code change will not
# be reloaded on its own. To develop, keep the repository directly inside the
# plugins folder.

set -euo pipefail

id="mdespeuilles.dock"
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
target="$HOME/.config/omarchy/plugins/$id"
mode="${1:---copy}"

if [[ $source_dir == "$(cd -- "$HOME/.config/omarchy/plugins" 2>/dev/null && pwd -P)/$id" ]]; then
  echo "Already installed in place: $target"
else
  mkdir -p "$(dirname -- "$target")"

  if [[ -e $target || -L $target ]]; then
    echo "Replacing the existing $target"
    rm -rf -- "$target"
  fi

  case "$mode" in
    --copy) cp -r "$source_dir" "$target" ;;
    --link) ln -s "$source_dir" "$target" ;;
    *) echo "Usage: install.sh [--copy|--link]" >&2; exit 1 ;;
  esac
  echo "Installed $id ($mode)."
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy plugin enable "$id" || true

echo
echo "Reserved strip along the bottom edge. If it does not show up yet:"
echo "  omarchy restart shell"
