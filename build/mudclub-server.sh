#!/bin/bash

# bail out if any part of this fails
set -e

# This is the self-extracting installer script for an FPM shell installer package.
# It contains the logic to unpack a tar archive appended to the end of this script
# and, optionally, to run post install logic.
# Run the package file with -h to see a usage message or look at the print_usage method.
#
# The post install scripts are called with INSTALL_ROOT, INSTALL_DIR and VERBOSE exported
# into the environment for their use.
#
# INSTALL_ROOT = the path passed in with -i or a relative directory of the name of the package
#                file with no extension
# INSTALL_DIR  = the same as INSTALL_ROOT unless -c (capistrano release directory) argumetn
#                is used. Then it is $INSTALL_ROOT/releases/<datestamp>
# CURRENT_DIR  = if -c argument is used, this is set to the $INSTALL_ROOT/current which is
#                symlinked to INSTALL_DIR
# VERBOSE      = is set if the package was called with -v for verbose output
function main() {
    set_install_dir

    if ! slug_already_current ; then

      create_pid
      wait_for_others
      kill_others
      set_owner
      pre_install
      unpack_payload

      if [ "$UNPACK_ONLY" == "1" ] ; then
          echo "Unpacking complete, not moving symlinks or restarting because unpack only was specified."
      else
          create_symlinks

          set +e # don't exit on errors to allow us to clean up
          if ! run_post_install ; then
              revert_symlinks
              log "Installation failed."
              exit 1
          else
              clean_out_old_releases
              log "Installation complete."
          fi
      fi

    else
        echo "This slug is already installed in 'current'. Specify -f to force reinstall. Exiting."
    fi
}

# check if this slug is already running and exit unless `force` specified
# Note: this only works with RELEASE_ID is used
function slug_already_current(){
    local this_slug=$(basename $0 .slug)
    local current=$(basename "$(readlink ${INSTALL_ROOT}/current)")
    log "'current' symlink points to slug: ${current}"

    if [ "$this_slug" == "$current" ] ; then
        if [ "$FORCE" == "1" ] ; then
        log "Force was specified. Proceeding with install after renaming live directory to allow running service to shutdown correctly."
            local real_dir=$(readlink ${INSTALL_ROOT}/current)
            if [ -e ${real_dir}.old ] ; then
                # remove that .old directory, if needed
                log "removing existing .old version of release"
                rm -rf ${real_dir}.old
            fi
            mv ${real_dir} ${real_dir}.old
            mkdir -p ${real_dir}
        else
            return 0;
        fi
    fi
    return 1;
}

# deletes the PID file for this installation
function delete_pid(){
    rm -f ${INSTALL_ROOT}/$$.pid 2> /dev/null
}

# creates a PID file for this installation
function create_pid(){
    trap "delete_pid" EXIT
    echo $$> ${INSTALL_ROOT}/$$.pid
}


# checks for other PID files and sleeps for a grace period if found
function wait_for_others(){
    local count=`ls ${INSTALL_ROOT}/*.pid | wc -l`

    if [ $count -gt 1 ] ; then
        sleep 10
    fi
}

# kills other running installations
function kill_others(){
    for PID_FILE in $(ls ${INSTALL_ROOT}/*.pid) ; do
        local p=`cat ${PID_FILE}`
        if ! [ $p == $$ ] ; then
            kill -9 $p
            rm -f $PID_FILE 2> /dev/null
        fi
    done
}

# echos metadata file. A function so that we can have it change after we set INSTALL_ROOT
function fpm_metadata_file(){
    echo "${INSTALL_ROOT}/.install-metadata"
}

# if this package was installed at this location already we will find a metadata file with the details
# about the installation that we left here. Load from that if available but allow command line args to trump
function load_environment(){
    local METADATA=$(fpm_metadata_file)
    if [ -r "${METADATA}" ] ; then
        log "Found existing metadata file '${METADATA}'. Loading previous install details. Env vars in current environment will take precedence over saved values."
        local TMP="/tmp/$(basename $0).$$.tmp"
        # save existing environment, load saved environment from previous run from install-metadata and then
        # overlay current environment so that anything set currencly will take precedence
        # but missing values will be loaded from previous runs.
        save_environment "$TMP"
        source "${METADATA}"
        source $TMP
        rm "$TMP"
    fi
}

# write out metadata for future installs
function save_environment(){
    local METADATA=$1
    echo -n "" > ${METADATA} # empty file

    # just piping env to a file doesn't quote the variables. This does
    # filter out multiline junk, _, and functions. _ is a readonly variable.
    env | grep -v "^_=" | grep -v "^[^=(]*()=" | egrep "^[^ ]+=" | while read ENVVAR ; do
        local NAME=${ENVVAR%%=*}
        # sed is to preserve variable values with dollars (for escaped variables or $() style command replacement),
        # and command replacement backticks
        # Escaped parens captures backward reference \1 which gets replaced with backslash and \1 to esape them in the saved
        # variable value
        local VALUE=$(eval echo '$'$NAME | sed 's/\([$`]\)/\\\1/g')
        echo "export $NAME=\"$VALUE\"" >> ${METADATA}
    done

    if [ -n "${OWNER}" ] ; then
        chown ${OWNER} ${METADATA}
    fi
}

function set_install_dir(){
    # if INSTALL_ROOT isn't set by parsed args, use basename of package file with no extension
    DEFAULT_DIR=$(echo $(basename $0) | sed -e 's/\.[^\.]*$//')
    INSTALL_DIR=${INSTALL_ROOT:-$DEFAULT_DIR}

    DATESTAMP=$(date +%Y%m%d%H%M%S)
    if [ -z "$USE_FLAT_RELEASE_DIRECTORY" ] ; then
        
        INSTALL_DIR="${RELEASES_DIR}/${RELEASE_ID:-$DATESTAMP}"
    fi

    mkdir -p "$INSTALL_DIR" || die "Unable to create install directory $INSTALL_DIR"

    export INSTALL_DIR

    log "Installing package to '$INSTALL_DIR'"
}

function set_owner(){
    export OWNER=${OWNER:-$USER}
    log "Installing as user $OWNER"
}

function pre_install() {
    # for rationale on the `:`, see #871
    :

}

function unpack_payload(){
    if [ "$FORCE" == "1" ] || [ ! "$(ls -A $INSTALL_DIR)" ] ; then
        log "Unpacking payload . . ."
        local archive_line=$(grep -a -n -m1 '__ARCHIVE__$' $0 | sed 's/:.*//')
        tail -n +$((archive_line + 1)) $0 | tar -C $INSTALL_DIR -xf - > /dev/null || die "Failed to unpack payload from the end of '$0' into '$INSTALL_DIR'"
    else
        # Files are already here, just move symlinks
        log "Directory already exists and has contents ($INSTALL_DIR). Not unpacking payload."
    fi
}

function run_post_install(){
    local AFTER_INSTALL=$INSTALL_DIR/.fpm/after_install
    if [ -r $AFTER_INSTALL ] ; then
        set_post_install_vars
        chmod +x $AFTER_INSTALL
        log "Running post install script"
        output=$($AFTER_INSTALL 2>&1)
        errorlevel=$?
        log $output
        return $errorlevel
    fi
    return 0
}

function set_post_install_vars(){
    # for rationale on the `:`, see #871
    :
    
}

function create_symlinks(){
    [ -n "$USE_FLAT_RELEASE_DIRECTORY" ] && return

    export CURRENT_DIR="$INSTALL_ROOT/current"
    if [ -e "$CURRENT_DIR" ] || [ -h "$CURRENT_DIR" ] ; then
        log "Removing current symlink"
        OLD_CURRENT_TARGET=$(readlink $CURRENT_DIR)
        rm "$CURRENT_DIR"
    fi
    ln -s "$INSTALL_DIR" "$CURRENT_DIR"

    log "Symlinked '$INSTALL_DIR' to '$CURRENT_DIR'"
}

# in case post install fails we may have to back out switching the symlink to current
# We can't switch the symlink after because post install may assume that it is in the
# exact state of being installed (services looking to current for their latest code)
function revert_symlinks(){
    if [ -n "$OLD_CURRENT_TARGET" ] ; then
        log "Putting current symlink back to '$OLD_CURRENT_TARGET'"
        if [ -e "$CURRENT_DIR" ] ; then
            rm "$CURRENT_DIR"
        fi
        ln -s "$OLD_CURRENT_TARGET" "$CURRENT_DIR"
    fi
}

function clean_out_old_releases(){
    [ -n "$USE_FLAT_RELEASE_DIRECTORY" ] && return

    if [ -n "$OLD_CURRENT_TARGET" ] ; then
        # exclude old 'current' from deletions
        while [ $(ls -tr "${RELEASES_DIR}" | grep -v ^$(basename "${OLD_CURRENT_TARGET}")$ | wc -l) -gt 2 ] ; do
            OLDEST_RELEASE=$(ls -tr "${RELEASES_DIR}" | grep -v ^$(basename "${OLD_CURRENT_TARGET}")$ | head -1)
            log "Deleting old release '${OLDEST_RELEASE}'"
            rm -rf "${RELEASES_DIR}/${OLDEST_RELEASE}"
        done
    else
        while [ $(ls -tr "${RELEASES_DIR}" | wc -l) -gt 2 ] ; do
            OLDEST_RELEASE=$(ls -tr "${RELEASES_DIR}" | head -1)
            log "Deleting old release '${OLDEST_RELEASE}'"
            rm -rf "${RELEASES_DIR}/${OLDEST_RELEASE}"
        done
    fi
}

function print_package_metadata(){
    local metadata_line=$(grep -a -n -m1 '__METADATA__$' $0 | sed 's/:.*//')
    local archive_line=$(grep -a -n -m1 '__ARCHIVE__$' $0 | sed 's/:.*//')

    # This used to be a sed call but it was taking _forever_ and this method is super fast
    local start_at=$((metadata_line + 1))
    local take_num=$((archive_line - start_at))

    head -n${start_at} $0 | tail -n${take_num}
}

function print_usage(){
    echo "Usage: `basename $0` [options]"
    echo "Install this package"
    echo "  -i <DIRECTORY> : install_root - an optional directory to install to."
    echo "      Default is package file name without file extension"
    echo "  -o <USER>     : owner - the name of the user that will own the files installed"
    echo "                   by the package. Defaults to current user"
    echo "  -r: disable capistrano style release directories - Default behavior is to create a releases directory inside"
    echo "      install_root and unpack contents into a date stamped (or build time id named) directory under the release"
    echo "      directory. Then create a 'current' symlink under install_root to the unpacked"
    echo "      directory once installation is complete replacing the symlink if it already "
    echo "      exists. If this flag is set just install into install_root directly"
    echo "  -u: Unpack the package, but do not install and symlink the payload"
    echo "  -f: force - Always overwrite existing installations"
    echo "  -y: yes - Don't prompt to clobber existing installations"
    echo "  -v: verbose - More output on installation"
    echo "  -h: help -  Display this message"
}

function die () {
    local message=$*
    echo "Error: $message : $!"
    exit 1
}

function log(){
    local message=$*
    if [ -n "$VERBOSE" ] ; then
        echo "$*"
    fi
}

function parse_args() {
    args=`getopt mi:o:rfuyvh $*`

    if [ $? != 0 ] ; then
        print_usage
        exit 2
    fi
    set -- $args
    for i
    do
        case "$i"
            in
            -m)
                print_package_metadata
                exit 0
                shift;;
            -r)
                USE_FLAT_RELEASE_DIRECTORY=1
                shift;;
            -i)
                shift;
                export INSTALL_ROOT="$1"
                export RELEASES_DIR="${INSTALL_ROOT}/releases"
                shift;;
            -o)
                shift;
                export OWNER="$1"
                shift;;
            -v)
                export VERBOSE=1
                shift;;
            -u)
                UNPACK_ONLY=1
                shift;;
            -f)
                FORCE=1
                shift;;
            -y)
                CONFIRM="y"
                shift;;
            -h)
                print_usage
                exit 0
                shift;;
            --)
                shift; break;;
        esac
    done
}

# parse args first to get install root
parse_args $*
# load environment from previous installations so we get defaults from that
load_environment
# reparse args so they can override any settings from previous installations if provided on the command line
parse_args $*

main
save_environment $(fpm_metadata_file)
exit 0

__METADATA__

__ARCHIVE__
./                                                                                                  0000755 0000000 0000000 00000000000 14417761217 006113  5                                                                                                    ustar                                                                                                                                                                                                                                                          ./.fpm/                                                                                             0000755 0000000 0000000 00000000000 14417761217 006753  5                                                                                                    ustar                                                                                                                                                                                                                                                          ./.fpm/after_install                                                                                0000644 0000000 0000000 00000007521 14417761217 011532  0                                                                                                    ustar                                                                                                                                                                                                                                                          #!/bin/bash
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
		gem install pleaserun 2> /dev/null
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
		echo "================================"
		echo "* Attempting to configure MudClub service..."
		pleaserun --install --user $MUDCLUB --group $MUDCLUB --name $MUDCLUB --description "MudClub: open source team sports club management service" --chdir $MUDHOME --environment-file /etc/mudclub "/srv/rails/mudclub/bin/rails server"
		exit 0
	else
		printf "ERROR!\n    => Could not clone from https://github.com/iangullo/mudclub.git\n"
		exit 2
	fi
else
	printf "ERROR!\n    => Could not create '%s'\n" $MUDHOME
	exit 1
fi                                                                                                                                                                               ./usr/                                                                                              0000755 0000000 0000000 00000000000 14417761217 006724  5                                                                                                    ustar                                                                                                                                                                                                                                                          ./usr/local/                                                                                        0000755 0000000 0000000 00000000000 14417761217 010016  5                                                                                                    ustar                                                                                                                                                                                                                                                          ./usr/local/bin/                                                                                    0000755 0000000 0000000 00000000000 14417761217 010566  5                                                                                                    ustar                                                                                                                                                                                                                                                          ./usr/local/bin/mudclub-start                                                                       0000755 0000000 0000000 00000000132 14417757505 013303  0                                                                                                    ustar                                                                                                                                                                                                                                                          #!/bin/bash
# Launch rails application for MudClub
su - mudclub -c "nohup rails server &"
                                                                                                                                                                                                                                                                                                                                                                                                                                      ./usr/local/bin/mudclub-stop                                                                        0000755 0000000 0000000 00000000251 14414027244 013120  0                                                                                                    ustar                                                                                                                                                                                                                                                          #!/bin/bash
# Post install script for MudClub
MUDHOME="/srv/rails/mudclub"
SRVCPID="tmp/pids/server.pid"

[ -f "$MUDHOME/$SRVCPID" ] && kill -9 `cat "$MUDHOME/$SRVCPID"`                                                                                                                                                                                                                                                                                                                                                       ./usr/local/bin/mudclub-update                                                                      0000755 0000000 0000000 00000001471 14417716632 013433  0                                                                                                    ustar                                                                                                                                                                                                                                                          #!/bin/bash
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
                                                                                                                                                                                                       ./etc/                                                                                              0000755 0000000 0000000 00000000000 14417761217 006666  5                                                                                                    ustar                                                                                                                                                                                                                                                          ./etc/nginx/                                                                                        0000755 0000000 0000000 00000000000 14417761217 010011  5                                                                                                    ustar                                                                                                                                                                                                                                                          ./etc/nginx/sites-available/                                                                        0000755 0000000 0000000 00000000000 14417761217 013056  5                                                                                                    ustar                                                                                                                                                                                                                                                          ./etc/nginx/sites-available/mudclub                                                                 0000644 0000000 0000000 00000000436 14414027224 014425  0                                                                                                    ustar                                                                                                                                                                                                                                                          upstream rails_server {
  server localhost:3000;
}

server {
  listen 80;

  location / {
    root /srv/rails/mudclub/public;
    try_files $uri @missing;
  }

  location @missing {
    proxy_pass http://rails_server;
    proxy_set_header Host $http_host;
    proxy_redirect off;
  }
}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  