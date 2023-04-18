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
		# prepare bash environment
		su - $MUDCLUB -c 'cp /etc/skel/.profile .'
		su - $MUDCLUB -c 'cp /etc/skel/.bashrc .'
		su - $MUDCLUB -c 'echo "export PATH=$MUDHOME/vendor/bundle/ruby/3.1.0/bin:$MUDHOME/bin:/usr/bin:/usr/local/bin" >> .bashrc'
		su - $MUDCLUB -c 'echo "export RAILS_ENV=production >> .bashrc'
		su - $MUDCLUB -c 'echo "export DB_HOST=localhost" >> .bashrc'
		su - $MUDCLUB -c 'echo "export DB_USERNAME=mudclub" >> .bashrc'
		su - $MUDCLUB -c 'echo "export DB_PASSWORD=" >> .bashrc'
		su - $MUDCLUB -c 'echo "export DB_NAME=mudclub" >> .bashrc'
		echo "OK"
		printf "  * Installing necesssary gems...\n\t"
		su - $MUDCLUB -c "$BUNDLE config set --local path 'vendor/bundle'" 2> /dev/null
		su - $MUDCLUB -c "$BUNDLE config set --local without 'development test'" 2> /dev/null
		su - $MUDCLUB -c "$BUNDLE install" 2> /dev/null
		#echo "OK"
		#	gem install pleaserun
		# check postgresql port
		#PG_PORT=`pg_conftool  show port | cut -d \= -f 2 | xargs`
		#if $PG_PORT
		#fi
		# ensure postgresql user exists
		VAL=`su - postgres  -c "psql -t -c '\du'" | cut -d \| -f 1 | grep $MUDCLUB`
		if ! [[ $VAL ]] ; then
			printf "  * Creating database user..."
			su - postgres -c "createuser -s -d $MUDCLUB -W"
			echo "OK"
		fi
		# ensure database $MUDCLUB exists
		VAL=`su - postgres  -c "psql -lqt | cut -d \| -f 1 | grep $MUDCLUB`
		if ! [[ $VAL ]] ; then
			printf "  * Creating database..."
			su - postgres -c "createdb $MUDCLUB --owner=$MUDCLUB"
			echo "OK"
		fi
		# rails server preparation
		printf "  * Creating secrets..."
		RAILS_SEC=`su - $MUDCLUB -c "$RAILS secret"`
		RAILS_SEC="secret_key_base: $RAILS_SEC"
		su - $MUDCLUB -c "echo $RAILS_SEC >> .bashrc"
		echo "OK"
		# rails server preparation
		printf "  * Migrating database..."
		su - $MUDCLUB -c "$RAILS db:migrate"
		echo "OK"
		printf "  * Compiling assets..."
		su - $MUDCLUB -c "$RAILS assets:precompile"
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