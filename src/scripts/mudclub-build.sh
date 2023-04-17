#!/bin/bash
# Post install script for MudClub
MUDCLUB=mudclub
SRVPATH="/srv/rails"
MUDHOME="/srv/rails/$MUDCLUB"
RAILS_ENV=production
BUNDLE="~/bin/bundle"
RAILS="~/bin/rails"
echo "MudClub: Rails server app for sports clubs..."
echo "============================================="
printf "  * Creating '%s' folder in '%s'..." $MUDCLUB $MUDHOME
if mkdir -p $MUDHOME 2> /dev/null ; then
	echo "OK"
	cd $MUDHOME
	printf "  * Creating '$MUDCLUB' user..."
	adduser $MUDCLUB --disabled-password --gecos "" --quiet --home $MUDHOME --shell /bin/bash 2> /dev/null
	chown -R $MUDCLUB $MUDHOME 2> /dev/null
	echo "OK"
	printf "  * Getting source code..."
	cd $SRVPATH
	if su $MUDCLUB -c "git clone https://github.com/iangullo/mudclub.git 2> /dev/null"; then
		su - $MUDCLUB -c "cat '#!/bin/bash' > .bashrc"
		su - $MUDCLUB -c "cat 'export PATH=~/bin:/usr/bin:/usr/local/bin' >> .bashrc"
		su - $MUDCLUB -c "cat 'export RAILS_ENV=production' >> .bashrc"
		echo "OK"
		printf "  * Installing necesssary gems..."
		su - $MUDCLUB -c "$BUNDLE config set --local path 'vendor/bundle'" 2> /dev/null
		su - $MUDCLUB -c "$BUNDLE config set --local without 'development test'" 2> /dev/null
		su - $MUDCLUB -c "$BUNDLE install" 2> /dev/null
		echo "OK"
		#	gem install pleaserun
		# ensure postgresql user exists
		if (( ! $(su - postgres  -c "psql -t -c '\du'" | cut -d \| -f 1 | grep -qw $MUDCLUB) )) ; then
			printf "    * Creating database user..."
			su - postgres -c "createuser -d $MUDCLUB"
			echo "OK"
		fi
		# ensure postgresql user exists
		if (( ! $(su - postgres -c "psql -lqt" | cut -d \| -f 1 | grep -qw $MUDCLUB.production) )) ; then
			printf "    * Creating database..."
			su -u postgres -c "createdb $MUDCLUB.production --owner=$MUDCLUB"
			echo "OK"
		fi
		# rails server preparation
		printf "  * Migrating database..."
		su - $MUDCLUB -c "$RAILS db:migrate"
		echo "OK"
		printf "  * Compiling assets..."
		su - $MUDCLUB -c "$RAILS assets:precompile"
		echo "OK"
		# rails server preparation
		printf "  * Creating secrets..."
		su - $MUDCLUB -c "$RAILS secret"
		echo "OK"
		printf "  * Adding site to Nginx..."
		echo "OK"
		rm /etc/nginx/sites-enabled/default
		ln -s /etc/nginx/sites-available/mudclub /etc/nginx/sites-enabled/mudclub
		nginx -t && systemctl reload nginx
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