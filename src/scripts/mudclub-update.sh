#!/bin/bash
# Update script for MudClub - pulls from git and rebuilds application
export MUDCLUB="mudclub"
export MUDHOME="/srv/rails/$MUDCLUB"
echo "MudClub: Trying to update..."
echo "================================"
cd $MUDHOME
if su - $MUDCLUB -c "git pull" ; then
	printf "* Checking necesssary gems...\n  "
	su - $MUDCLUB -c "bundle"
	printf "* Migrating database..."
	su - $MUDCLUB -c "rails db:migrate -e production" 2> /dev/null
	echo "OK"
	printf "* Compiling assets..."
	su - $MUDCLUB -c "rails assets:precompile" 2> /dev/null
	echo "OK"
	printf "* Restarting service..."
	systemctl restart $MUDCLUB.service
	echo "OK"
	echo "================================"
	echo >&2 "MudClub: Successfully updated!"
	exit 0
else
	echo >&2 "    * ERROR: Could not clone from https://github.com/iangullo/mudclub.git"
	exit 1
fi
