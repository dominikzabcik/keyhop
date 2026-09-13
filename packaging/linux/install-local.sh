#!/bin/sh
# Installs Keyhop from this folder into ~/.local, on any Linux distribution. No root needed.
#   PREFIX=/some/where ./install-local.sh   installs the programs somewhere else
set -eu

here=$(cd "$(dirname "$0")" && pwd)
prefix="${PREFIX:-$HOME/.local}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"

mkdir -p "$prefix/bin" "$data/applications" "$data/metainfo"
install -m 0755 "$here/keyhop" "$prefix/bin/keyhop"
install -m 0755 "$here/keyhop-tray" "$prefix/bin/keyhop-tray"
sed "s|^Exec=keyhop-tray|Exec=$prefix/bin/keyhop-tray|" "$here/app.keyhop.Keyhop.desktop" > "$data/applications/app.keyhop.Keyhop.desktop"
cp "$here/app.keyhop.Keyhop.metainfo.xml" "$data/metainfo/"
for png in "$here"/icons/keyhop-*.png; do
  size=${png##*-}
  size=${size%.png}
  mkdir -p "$data/icons/hicolor/${size}x${size}/apps"
  cp "$png" "$data/icons/hicolor/${size}x${size}/apps/app.keyhop.Keyhop.png"
done
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database -q "$data/applications" || true; fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -q -t "$data/icons/hicolor" || true; fi

echo "Installed keyhop and keyhop-tray into $prefix/bin."
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) echo "Add $prefix/bin to your PATH to run keyhop from a terminal." ;;
esac

if ! python3 -c 'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("AyatanaAppIndicator3", "0.1")' >/dev/null 2>&1; then
  echo "The tray also needs GTK 3, AppIndicator and libnotify for Python:"
  echo "  Fedora:        sudo dnf install python3-gobject gtk3 libayatana-appindicator-gtk3 libnotify"
  echo "  Debian/Ubuntu: sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1 gir1.2-notify-0.7"
  echo "  Arch:          sudo pacman -S python-gobject gtk3 libayatana-appindicator libnotify"
  echo "  openSUSE:      sudo zypper install python3-gobject-Gdk typelib-1_0-AyatanaAppIndicator3-0_1 typelib-1_0-Notify-0_7"
fi
