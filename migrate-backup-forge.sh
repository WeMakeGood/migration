#!/bin/bash
# WordPress site backup for Laravel Forge.
#
# Sites live in ~/{site}/public/. This walks every site directory and, for any
# WordPress install it finds, writes a self-contained backup tarball to
# ~/backups/{site}.tar.gz — named by the site's home host. Each archive holds the
# database export plus the portable content (plugins, themes, uploads, wp-config.php).

set -euo pipefail

# Establish the user root and the backups destination.
cd
ROOT="$(pwd)"
BACKUPS="$ROOT/backups"
mkdir -p "$BACKUPS"

# Determine whether we're backing up a single site or all of them.
echo "Which site would you like to back up? [ALL/site]"
read -r APPS

# If no specific site was named, build the list from the home directory.
if [ -z "$APPS" ] || [ "$APPS" = "ALL" ]; then
	APPS="$(ls "$ROOT")"
fi

# Iterate through candidate site directories.
for APP in $APPS; do
	PUBLIC="$ROOT/$APP/public"
	# Only back up directories that actually contain a WordPress install.
	if [ ! -f "$PUBLIC/wp-config.php" ]; then
		continue
	fi

	echo "Backing up: $APP"
	cd "$PUBLIC"

	# Derive the archive name from the site's home host (strip scheme, auth, port, path).
	URL="$(wp option get home)"
	SITE="$(echo "$URL" | sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/')"
	ARCHIVE="$BACKUPS/$SITE.tar.gz"

	# Export the database, then tar it together with the portable content.
	if [ -f "db.sql" ]; then rm db.sql; fi
	wp db export db.sql --quiet
	if [ -f "$ARCHIVE" ]; then rm "$ARCHIVE"; fi
	tar czf "$ARCHIVE" --checkpoint=.1000 --totals \
		db.sql \
		wp-config.php \
		./wp-content/plugins \
		./wp-content/themes \
		./wp-content/uploads
	rm db.sql
done

echo "Backups complete. Archives are in $BACKUPS/"
