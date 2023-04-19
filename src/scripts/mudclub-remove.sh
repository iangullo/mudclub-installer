#!/bin/bash
# Update script for MudClub - pulls from git and rebuilds application
MUDCLUB=mudclub
SRVPATH="/srv/rails"
MUDHOME="/srv/rails/$MUDCLUB"
RAILS_ENV=production
mkdir -p $SRVPATH
echo "MudClub: Removing application..."
echo "================================"
printf "  * Removing $MUDCLUB fron Nginx..."
#systemctl stop $MUDCLUB.service
#systemctl disable $MUDCLUB.service
rm /etc/nginx/sites-enabled/mudclub 2> /dev/null
rm /etc/nginx/sites-available/mudclub 2> /dev/null
nginx -t  2> /dev/null && systemctl reload nginx 2> /dev/null
echo "OK"
cd $MUDHOME
printf "  * Deleting database..."
su - $MUDCLUB -c "rails db:drop"
VAL=`su - postgres  -c "psql -t -c '\du'" | cut -d \| -f 1 | grep -w $MUDCLUB`
if [ ! -z $VAL ] ; then
	su - postgres -c "dropuser $MUDCLUB"
fi
echo "OK"
printf "  * Removing $MUDCLUB user..."
deluser $MUDCLUB --quiet 2> /dev/null
echo "OK"
printf "  * Deleting application..."
cd ..
rm -rf $MUDHOME 2> /dev/null
echo "OK"
echo "================================"
echo >&2 "MudClub: Successfully removed!"
exit 0
