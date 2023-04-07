#!/bin/bash
# Launch rails application for MudClub
MUDHOME=/srv/rails/mudclub
cd $MUDHOME
nohup rails server -e production &
