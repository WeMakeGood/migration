#!/bin/bash

echo "Run Process Per Site"
echo "--------------------"
echo "What command would you like to perform?"
read COMMAND

cd
ROOT="$(pwd)"

for SITE in $(ls $ROOT); do
	if [ -d $ROOT/$SITE/public ]; then
		cd $ROOT/$SITE/public
		$($COMMAND)
	fi
done
echo "Processing complete!"
