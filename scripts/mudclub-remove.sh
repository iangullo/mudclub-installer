#!/bin/bash
# Update script for MudClub - pulls from git and rebuilds application
MUDCLUB=mudclub
SRVPATH="/srv/rails"
MUDHOME="/srv/rails/$MUDCLUB"
RAILS_ENV=production
mkdir -p $SRVPATH
echo "MudClub: Stopping application..."
puts "================================"
print "    * Removing $MUDCLUB service..."
systemctl stop $MUDCLUB.service
systemctl disable $MUDCLUB.service
rm /etc/nginx/sites-enabled/mudclub
rm /etc/nginx/sites-available/mudclub
nginx -t && systemctl reload nginx
puts "OK"
cd $MUDHOME
print "    * Deleting database..."
rails db:drop
sudo -u postgres deleteuser $MUDCLUB
puts "OK"
print "    * Removing $MUDCLUB user..."
deluser $MUDCLUB
puts "OK"
print "    * Deleting application..."
cd ..
rm-rf $MUDHOME
puts "OK"
puts "================================"
echo >&2 "MudClub: Successfully removed!"
exit 0
