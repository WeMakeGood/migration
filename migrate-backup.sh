#!/bin/bash
echo "Into which app should the archive be placed?"
read MIGRATEAPP
cd
ROOT="$(pwd)"
MIGRATE=$ROOT/migrate
SITES=$MIGRATE/sites.csv
# Set up the core directories
if [ ! -d $MIGRATE ]; then
	mkdir $MIGRATE
else
	rm -Rf $MIGRATE/*
fi
# Iterate through the apps folder
for APP in $(ls $ROOT/apps/); do
	echo "Backing up: $APP"
	cd $ROOT/apps/$APP/public
	if [ -f $ROOT/apps/$APP/public/wp-config.php ]; then
		# Remove SP directives to clean up output
		if [ -f wp-config.php ]; then rm -Rf wp-config.sp.php; fi
		cp wp-config.php wp-config.sp.php
		sed -iz "s/define('WP_SITEURL', SP_REQUEST_URL);//g" wp-config.php
		sed -iz "s/define('WP_HOME', SP_REQUEST_URL);//g" wp-config.php
		# Get the core WP variables
		URL="$(wp option get home)"
		SITE="$(echo $URL | sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/')"
		PREFIX="$(wp config get table_prefix)"
		ARCHIVE=$APP.tar.gz
		# Write out the log CSV
		echo "$APP,$SITE,$URL,$ARCHIVE,$PREFIX" >>$SITES
		# Back up the site
		if [ -f "db.sql" ]; then rm db.sql; fi
		wp db export db.sql --quiet
		if [ -f "$MIGRATE/$ARCHIVE" ]; then rm $MIGRATE/$ARCHIVE; fi
		tar czf $MIGRATE/$ARCHIVE --checkpoint=.1000 --totals db.sql ./wp-content/plugins ./wp-content/themes ./wp-content/uploads
		rm db.sql
	fi
done
echo "Individual site migration is complete. Now compressing to migration app."
# Compress the migration folder into the export app
cd $MIGRATE
if [ -f $ROOT/apps/$MIGRATEAPP/public/migrate.tar.gz ]; then rm -Rf $ROOT/apps/$MIGRATEAPP/public/migrate.tar.gz; fi
tar czvf $ROOT/apps/$MIGRATEAPP/public/migrate.tar.gz --checkpoint=.1000 --totals *
# Get the migration site URL
cd $ROOT/apps/$MIGRATEAPP/public/
MIGRATEURL="$(wp option get home)"
echo "Migration is complete. You can download the file from:"
echo "$MIGRATEURL/migrate.tar.gz"
