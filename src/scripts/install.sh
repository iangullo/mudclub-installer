#!/bin/bash
# Post install script for MudClub
export MUDCLUB=mudclub
export MUDPASS=EtClausi
export SRVPATH="/srv/rails"
export MUDHOME="/srv/rails/$MUDCLUB"
export RAILS_ENV=production
export BUNDLE="~/bin/bundle"
export RAILS="~/bin/rails"
echo "MudClub: Rails server app for sports clubs..."
echo "============================================="
printf "* Creating '%s' folder in '%s'..." $MUDCLUB $MUDHOME
if mkdir -p $MUDHOME 2> /dev/null ; then
	echo "OK"
	cd $MUDHOME
	printf "* Creating '$MUDCLUB' user..."
	adduser $MUDCLUB --disabled-password --gecos "" --quiet --home $MUDHOME --shell /bin/bash 2> /dev/null
	chown -R $MUDCLUB $MUDHOME 2> /dev/null
	echo "OK"
	cd $SRVPATH
	printf "* "
	if su $MUDCLUB -c "git clone https://github.com/iangullo/mudclub.git"; then
		# prepare bash environment
		printf "* Copying default configuration..."
		su - $MUDCLUB -c 'cp /etc/skel/.profile .'
		su - $MUDCLUB -c 'cp /etc/skel/.bashrc .'
		ln -s /etc/mudclub $MUDHOME/.env
		su - $MUDCLUB -c 'echo "# Override PATH" >> .bashrc'
		su - $MUDCLUB -c 'echo PATH="~/vendor/bundle/ruby/3.1.0/bin:~/bin:/usr/bin:/usr/local/bin" >> .bashrc'
		su - $MUDCLUB -c 'echo "# Load mudclub environment file" >> .bashrc'
		su - $MUDCLUB -c 'echo "if [ -f .env ]; then" >> .bashrc'
		su - $MUDCLUB -c 'echo "  set -o allexport; source .env; set +o allexport" >> .bashrc'
		su - $MUDCLUB -c 'echo "fi" >> .bashrc'
		echo "OK"
		printf "* Installing necesssary gems...\n  "
		su - $MUDCLUB -c "$BUNDLE config set --local path 'vendor/bundle' 2> /dev/null" 2> /dev/null
		su - $MUDCLUB -c "$BUNDLE config set --local without 'development test' 2> /dev/null" 2> /dev/null
		su - $MUDCLUB -c "$BUNDLE install 2> /dev/null" 2> /dev/null
		# rails server preparation
		printf "* Creating secrets..."
		RAILS_SEC=`su - $MUDCLUB -c "$RAILS secret"`
		su - $MUDCLUB -c "printf \" %s\n\" $RAILS_SEC >> ~/config/secrets.yml"
		echo "OK"
		# ensure postgresql user exists
		VAL=`su - postgres  -c "psql -t -c '\du'" | cut -d \| -f 1 | grep -w $MUDCLUB`
		if [ -z $VAL ] ; then
			printf "* Creating database user..."
			su - postgres -c "psql -c \"CREATE USER $MUDCLUB SUPERUSER LOGIN PASSWORD '$MUDPASS';\""
			echo "OK"
		fi
		# ensure database $MUDCLUB exists
		VAL=`su - postgres  -c "psql -lqt | cut -d \| -f 1 | grep -w $MUDCLUB"`
		if [ -z $VAL ] ; then
			printf "* Creating database..."
			su - mudclub -c "rails db:create 2> /dev/null" 2> /dev/null
			su - mudclub -c "psql create extension unaccent 2> /dev/null" 2> /dev/null
			echo "OK"
		fi
		# rails server preparation
		printf "* Migrating database..."
		su - $MUDCLUB -c "$RAILS db:migrate 2> /dev/null" 2> /dev/null
		su - $MUDCLUB -c "$RAILS db:seed 2> /dev/null" 2> /dev/null
		echo "OK"
		printf "* Compiling assets..."
		su - $MUDCLUB -c "npm install flowbite 2> /dev/null" 2> /dev/null
		su - $MUDCLUB -c "$RAILS assets:precompile 2> /dev/null" 2> /dev/null
		printf "* Adding site to Nginx..."
		rm /etc/nginx/sites-enabled/default 2> /dev/null
		ln -s /etc/nginx/sites-available/mudclub /etc/nginx/sites-enabled/mudclub 2> /dev/null
		nginx -t && systemctl reload nginx 2> /dev/null
		#	pleaserun --name $MUDCLUB --user $MUDCLUB --overwrite --description "MudClub service definition" --chdir $MUDHOME /bin/bash -lc 'rails server -e production'
		echo "================================"
		echo "MudClub: Successfully built!"
		exit 0
	else
		printf "ERROR!\n    => Could not clone from https://github.com/iangullo/mudclub.git\n"
		exit 2
	fi
else
	printf "ERROR!\n    => Could not create '%s'\n" $MUDHOME
	exit 1
fi