#!/bin/bash

# Set up the environment with API and SERVER keys
export $(grep -v '^#' .forge | xargs -d '\n')

if [ -v "$API_TOKEN" ]; then
	echo "You must create an environment file called .forge and include API_TOKEN with a valid Forge token."
	exit 99
fi

# Start at the very beginning
cd

# Get some basic variables
ROOT="$(pwd)"
MIGRATE="$ROOT/migrate"
UNTAR="$MIGRATE/untar"
SITES="$MIGRATE/sites.csv"
SERVERNAME="$(hostname)"
API_URL="https://forge.laravel.com/api/v1"

# Set up some Forge information
HEADERS=(-H "Authorization: Bearer $API_TOKEN" -H "Accept: application/json" -H "Content-Type: application/json")
SERVER_ID="$(curl -s "${HEADERS[@]}" -X GET $API_URL/servers -s | jq '.servers[] | select(.name | contains("'"$SERVERNAME"'")).id')"
SERVER_SITES="$(curl "${HEADERS[@]}" -X GET $API_URL/servers/$SERVER_ID/sites -s | jq -r '.sites[].name')"
DB_USER_ID="$(curl "${HEADERS[@]}" -X GET $API_URL/servers/$SERVER_ID/database-users -s | jq '.users[] | select(.name=='\"$USER\"').id')"

echo "System Configuration"
echo "  Server Name: $SERVERNAME"
echo "  Server ID: $SERVER_ID"
echo "  DB User ID: $DB_USER_ID"

# Download the migration file if neccessary
if [ ! -f "$MIGRATE/migrate.tar.gz" ]; then
	echo "Please provide the migration file URL:"
	read MIGRATIONFILE
	mkdir $MIGRATE
	cd $MIGRATE
	wget $MIGRATIONFILE
fi

# Move into the migration folder
cd $MIGRATE

# Unpack the migration tarball
if [ ! -f "$SITES" ]; then
	echo "Unpacking the migration file."
	tar xf migrate.tar.gz --checkpoint=.1000 --totals
fi

echo "The migration package has been expanded. Would you like to restore your sites? (Y/n)"
read CONTINUE
if [ "$CONTINUE" == "n" ]; then exit 99; fi

# Parse the sites.csv
OLDIFS=$IFS
IFS=','
[ ! -f $SITES ] && {
	echo "$SITES file not found"
	exit 99
}
while read APP SITE URL ARCHIVE PREFIX NEWSITE; do
	cd $MIGRATE
	unset IFS
	echo "Processing site: $SITE"
	SITE_DB_NAME=${SITE//./_}
	SITE_ROOT="$ROOT/$SITE/public"

	# Check for an existing database
	SITE_DB_ID="$(curl -s "${HEADERS[@]}" -X GET $API_URL/servers/$SERVER_ID/databases | jq '.databases[] | select(.name=="'$SITE_DB_NAME'").id')"
	# Create a new database if it needs to be added
	if [ -v $SITE_DB_ID ]; then
		echo "Adding database..."
		# Create the database
		SITE_DB_ID="$(curl -s "${HEADERS[@]}" -X POST $API_URL/servers/$SERVER_ID/databases --data '{"name":"'"$SITE_DB_NAME"'"}' | jq '.database.id')"
		if [[ ! "$SITE_DB_ID" =~ ^-?[0-9]+$ ]]; then
			echo $SITE_DB_ID
			exit 99
		fi
	fi

	# Add the database to the user
	DB_USER_DBS="$(curl -s "${HEADERS[@]}" -X GET $API_URL/servers/$SERVER_ID/database-users/$DB_USER_ID | jq -c '.user.databases')"
	if [[ ! "$DB_USER_DBS" == *"$SITE_DB_ID"* ]]; then
		DB_USER_DBS="$(echo "$DB_USER_DBS" | jq -c '. += ['$SITE_DB_ID'] | unique')"
		curl -s "${HEADERS[@]}" -X PUT $API_URL/servers/$SERVER_ID/database-users/$DB_USER_ID -d '{"databases": '"$DB_USER_DBS"'}' >/dev/null
	fi

	# Get the site ID or make it
	SITE_ID="$(curl -s "${HEADERS[@]}" -X GET $API_URL/servers/$SERVER_ID/sites | jq '.sites[] | select(.name=="'$SITE'").id')"
	if [ -v $SITE_ID ]; then
		echo "Creating site..."
		SITE_ID="$(curl -s "${HEADERS[@]}" -X POST $API_URL/servers/$SERVER_ID/sites -d '{"domain":"'"$SITE"'","project_type":"php","directory":"/public","isolated":true,"username":"'"$USER"'","php_version":"php80"}' | jq -cr '.site.id')"
		if [[ ! "$SITE_ID" =~ ^-?[0-9]+$ ]]; then
			echo $SITE_ID
			exit 99
		fi
	fi

	# Install WordPress if we need it
	if [ ! -f $SITE_ROOT/wp-config.php ]; then
		echo "Installing WordPress..."
		# Clean out the current WP, just in case
		curl -s "${HEADERS[@]}" -X DELETE $API_URL/servers/$SERVER_ID/sites/$SITE_ID/wordpress > /dev/null
		# Create a new WP installation
		curl -s "${HEADERS[@]}" -X POST $API_URL/servers/$SERVER_ID/sites/$SITE_ID/wordpress -d '{"database": "'"$SITE_DB_NAME"'", "user": '"$DB_USER_ID"'}' >/dev/null
		until [ -f $SITE_ROOT/wp-config.php ]; do
			sleep 1
		done
	fi

	# Start setting up the install
	if [ -d $UNTAR ]; then rm -Rf $UNTAR; fi
	mkdir $UNTAR
	echo "Unpacking site archive: $ARCHIVE"
	tar xf $ARCHIVE -C $UNTAR --checkpoint=.1000 --totals

	echo "Copying migrated files..."
	cd $UNTAR
	# Rsync the downloaded files to the current website
	rsync -aqP ./wp-content/plugins/ $SITE_ROOT/wp-content/plugins/
	rsync -aqP ./wp-content/themes/ $SITE_ROOT/wp-content/themes/
	rsync -aqP ./wp-content/uploads/ $SITE_ROOT/wp-content/uploads/

	echo "Importing database..."
	# Use WP CLI to restore the original database
	cd $SITE_ROOT
	sed -i "s/'wp_';/'$PREFIX';/g" wp-config.php
	wp db import $UNTAR/db.sql

	echo ""
	IFS=','
done <$SITES
IFS=$OLDIFS
echo "Install complete!"
