#!/bin/bash
# Post install script for MudClub
MUDCLUB=mudclub
SRVPATH="/srv/rails"
MUDHOME="/srv/rails/$MUDCLUB"
RAILS_ENV=production
mkdir -p $SRVPATH
echo "MudClub: Building application..."
puts "================================"
print "    * Pulling code..."
if git pull https://github.com/iangullo/mudclub.git
then
	puts "OK"
	cd $MUDHOME
	print "    * Installing necesssary gems..."
	bundle install --without 'development' 'test'
	puts "OK"
	print "    * Preparing database..."
	sudo -u postgres createuser $MUDCLUB
	sudo -u postgres createdb $MUDCLUB.production --owner=mudclub
	puts "OK"
	print "    * Migrating database..."
	rails db:migrate
	puts "OK"
	print "    * Compiling assets..."
	rails assets:precompile
	puts "OK"
	print "    * Creating '$MUDCLUB' user..."
	adduser $MUDCLUB --disabled-password --gecos ""
	puts "OK"
	print "    * Creating secrets..."
	rails secret -e
	chown -R $MUDCLUB $MUDCLUB
	puts "OK"
	print "    * Adding site to Nginx..."
	puts "OK"
	rm /etc/nginx/sites-enabled/default
	ln -s /etc/nginx/sites-available/mudclub /etc/nginx/sites-enabled/mudclub
	nginx -t && systemctl reload nginx
#	systemctl enable $MUDCLUB.service
#	systemctl start $MUDCLUB.service
	puts "================================"
	echo >&2 "MudClub: Successfully built!"
	exit 0
else
	echo >&2 "    * ERROR: Could not clone from https://github.com/iangullo/mudclub.git"
	exit 1
fi
