#!/bin/bash
# WordPress site backup for Laravel Forge migration.
#
# Sites live in ~/{site}/public/. This walks every site directory, exports the
# WordPress database and content for any install it finds, and writes a per-site
# tarball plus a sites.csv manifest that migrate-restore.sh reads on the other end.
# Everything is then bundled into a single migrate.tar.gz dropped into a
# download-accessible site so the destination server can fetch it over HTTP.

set -euo pipefail

# Establish the user root and core paths.
cd
ROOT="$(pwd)"
MIGRATE="$ROOT/migrate"
SITES="$MIGRATE/sites.csv"

# Determine whether we're backing up a single site or all of them.
echo "Which site would you like to back up? [ALL/site]"
read -r APPS
# Which site should receive the final migrate.tar.gz for download?
echo "Into which site directory should the migration archive be placed?"
read -r MIGRATEAPP

# Reset the migration workspace so a re-run starts clean.
if [ ! -d "$MIGRATE" ]; then
	mkdir "$MIGRATE"
else
	rm -Rf "${MIGRATE:?}"/*
fi

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

	# Pull the core WP variables we need to restore the site later.
	URL="$(wp option get home)"
	# Reduce the home URL down to the bare host (strip scheme, auth, port, path).
	SITE="$(echo "$URL" | sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/')"
	PREFIX="$(wp config get table_prefix)"
	ARCHIVE="$APP.tar.gz"

	# Append this site to the manifest restore reads back in.
	echo "$APP,$SITE,$URL,$ARCHIVE,$PREFIX" >>"$SITES"

	# Export the database, then tar it together with the portable content.
	if [ -f "db.sql" ]; then rm db.sql; fi
	wp db export db.sql --quiet
	if [ -f "$MIGRATE/$ARCHIVE" ]; then rm "$MIGRATE/$ARCHIVE"; fi
	tar czf "$MIGRATE/$ARCHIVE" --checkpoint=.1000 --totals \
		db.sql \
		./wp-content/plugins \
		./wp-content/themes \
		./wp-content/uploads
	rm db.sql
done

echo "Individual site backups are complete. Now compressing to the migration site."

# Bundle every per-site archive plus the manifest into one download.
cd "$MIGRATE"
MIGRATE_PUBLIC="$ROOT/$MIGRATEAPP/public"
if [ -f "$MIGRATE_PUBLIC/migrate.tar.gz" ]; then rm -Rf "$MIGRATE_PUBLIC/migrate.tar.gz"; fi
tar czvf "$MIGRATE_PUBLIC/migrate.tar.gz" --checkpoint=.1000 --totals -- *

# Report the download URL for the migration package.
cd "$MIGRATE_PUBLIC"
MIGRATEURL="$(wp option get home)"
echo "Migration is complete. You can download the file from:"
echo "$MIGRATEURL/migrate.tar.gz"
