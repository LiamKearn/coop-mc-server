#!/usr/bin/env sh
set -xe

# Start the minecraft server as the application user running in a named screen session
su - "${APPLICATION_USER}" -c "screen -S mc -d -m ${SERVER_DIR}/start-server.sh"
