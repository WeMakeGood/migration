#!/bin/bash

echo "Run Process Per Site"
echo "--------------------"
echo "What command would you like to perform?"
read COMMAND

cd
ROOT="$(pwd)"

for SITE in $(ls $ROOT); do
	if [ -d $ROOT/$SITE/public ]; then
		echo "Processing $SITE..."
		cd $ROOT/$SITE/public
		${COMMAND[@]}
		echo ""
	fi
done
echo "Processing complete!"
