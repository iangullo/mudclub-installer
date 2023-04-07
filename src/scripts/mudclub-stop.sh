#!/bin/bash
# Post install script for MudClub
MUDHOME="/srv/rails/mudclub"
SRVCPID="tmp/pids/server.pid"

[ -f "$MUDHOME/$SRVCPID" ] && kill -9 `cat "$MUDHOME/$SRVCPID"`