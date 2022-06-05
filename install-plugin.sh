#!/bin/bash
echo "What plugin would you like to install?"
read PLUGIN
for SITE in `ls ~/apps/`; do
	cd ~/apps/$SITE/public/
	wp plugin install $PLUGIN --activate
done
echo "Done"
