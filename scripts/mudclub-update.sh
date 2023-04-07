#!/bin/bash
# Update script for MudClub - pulls from git and rebuilds application
MUDCLUB=mudclub
MUDHOME=/srv/rails/$MUDCLUB
echo "MudClub: Trying to update..."
puts "================================"
cd $MUDHOME
print "    * Pulling code..."
if git pull
	puts "OK"
	print "    * Checking necesssary gems..."
	bundle --without 'development' 'test'
	puts "OK"
	print "    * Migrating database..."
	rails db:migrate -e production
	puts "OK"
	print "    * Compiling assets..."
	rails assets:precompile
	puts "OK"
	print "    * Restarting service..."
	systemctl restart $MUDCLUB.service
	puts "OK"
	puts "================================"
	echo >&2 "MudClub: Successfully updated!"
	exit 0
else
	echo >&2 "    * ERROR: Could not clone from https://github.com/iangullo/mudclub.git"
	exit 1
fi
