#!/bin/bash
set -euo pipefail

echo "=============================="
echo "Backup script indítása: $(date)"
START_TIME=$SECONDS

# --- Beállítások ---
SOURCE="/srv/samba/kozos"
DEST="/mnt/L/archive"
SNAPSHOT="$DEST/samba_backup.snar"   # tar inkrementális fájl
MAX_BACKUPS=10
TMPDIR=$(mktemp -d)
LOCKDIR="/tmp/samba_backup.lock"

# --- Atomic lock ---
if mkdir "$LOCKDIR" 2>/dev/null; then
    # sikeres lock
    trap 'rm -rf "$LOCKDIR"; rm -rf "$TMPDIR"' EXIT
else
    echo "Egy másik mentés már fut. Kilépés."
    exit 1
fi

# --- Ellenőrzések ---
[[ -d "$SOURCE" ]] || { echo "HIBA: Forrás nem létezik: $SOURCE"; exit 1; }
[[ -d "$DEST" ]]   || { echo "HIBA: Cél nem létezik: $DEST"; exit 1; }

# --- Snapshot készítés előtte ---
snapshot() {
    find "$SOURCE" -type f -printf '%p|%s|%T@\n' | sort
}

# --- Archívum létrehozása ---
while true; do
    DATE=$(date +"%Y%b%d_%Ho%Mp" | tr '[:upper:]' '[:lower:]')
    ARCHIVE="$DEST/linux_${DATE}.tgz"

    echo "Mentés készül: $ARCHIVE"

    # snapshot előtte
    snapshot > "$TMPDIR/before.txt"

    # archiválás (inkrementális)
    nice -n 19 ionice -c3 tar --listed-incremental="$SNAPSHOT" -czf "$ARCHIVE" -C "$(dirname "$SOURCE")" "$(basename "$SOURCE")"

    # snapshot utána
    snapshot > "$TMPDIR/after.txt"

    # ha változott valami a mentés közben → újra
    if diff -q "$TMPDIR/before.txt" "$TMPDIR/after.txt" >/dev/null; then
        echo "Mentés kész, nincs változás a folyamat közben."
        break
    else
        echo "Változás történt archiválás közben, újrakezdés..."
        rm -f "$ARCHIVE"
        sleep 1
    fi
done
