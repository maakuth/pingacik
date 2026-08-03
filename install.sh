#!/usr/bin/env bash
# Install or upgrade the Pingacik plasmoid for the current user.
set -euo pipefail

cd "$(dirname "$0")" || exit 1

PKG=package
ID=org.smolam.pingacik

if [ ! -f "$PKG/metadata.json" ]; then
    echo "error: $PKG/metadata.json not found" >&2
    exit 1
fi

if kpackagetool6 --type Plasma/Applet --show "$ID" >/dev/null 2>&1; then
    echo "Upgrading $ID…"
    kpackagetool6 --type Plasma/Applet --upgrade "$PKG"
else
    echo "Installing $ID…"
    kpackagetool6 --type Plasma/Applet --install "$PKG"
fi

cat <<EOF

Done. Add it via right-click on the panel -> "Add or Manage Widgets…" -> "Pingacik".

If you upgraded while the widget was already on the panel, restart the shell to
pick up the new QML:

    systemctl --user restart plasma-plasmashell

To try it without touching your panel:

    plasmoidviewer -a $ID -f planar    # full view
    plasmoidviewer -a $ID -f horizontal # panel view

To remove it:

    kpackagetool6 --type Plasma/Applet --remove $ID
EOF
