#!/bin/bash

echo "Repairing folder permissions..."

cd
ROOT="$(pwd)"

for SITE in "$(ls $ROOT)"; do
	WP_ROOT="$ROOT/$SITE/public"
	if [ -d "$ROOT/$SITE/public"]; then
		echo "Repairing $SITE..."
		find ${WP_ROOT} -type d -exec chmod 755 {} \;
		find ${WP_ROOT} -type f -exec chmod 644 {} \;
	fi
done
echo "Install complete!"
