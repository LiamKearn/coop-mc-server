#!/usr/bin/env sh
set -xe

# ========================================================
# START FUNCTIONS
# ========================================================

check_the_sum() {
    FILE=$1
    EXPECTED=$2
    ACTUAL=$(sha256sum "${FILE}" | cut -d ' ' -f 1)
    echo "Checking the of ${FILE}"
    echo "Expected: ${EXPECTED}"
    echo "Actual: ${ACTUAL}"
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "Checksum of ${FILE} does not match expected checksum, exiting"
        rm -f "${FILE}"
        exit 1
    fi
    echo "Checksum matches!"
}

download_mod() {
    URL=$1
    CHECKSUM=$2
    FORCE_FILENAME=$3
    if [ -n "$FORCE_FILENAME" ]; then
        DOWNLOADED_PATH="${SERVER_DIR}/mods/${FORCE_FILENAME}"
        echo "Forcing output to ${DOWNLOADED_PATH}"
        sudo curl -o "${DOWNLOADED_PATH}" -sSOJ "${URL}"
    else
        echo "Not forcing output name"
        DOWNLOADED_PATH=$(sudo curl --output-dir "${SERVER_DIR}/mods" -sSOJ "${URL}" -w "%{filename_effective}\n" )
    fi
    echo "Downloaded mod to ${DOWNLOADED_PATH}"
    check_the_sum "${DOWNLOADED_PATH}" "${CHECKSUM}"
}

# ========================================================
# END FUNCTIONS
# ========================================================

# ========================================================
# START VARIABLES
# ========================================================

APPLICATION_USER="mcuser"
STATE_DEVICE_NAME="/dev/sdf"

SERVER_DIR="/home/${APPLICATION_USER}/minecraft"
STATE_DIR="/home/${APPLICATION_USER}/mcstate"

MINECRAFT_VERSION="1.21.1"
FABRIC_INSTALLER_VERSION="1.1.1"
FABRIC_INSTALLER_JAR_CHECKSUM="2487a69dd6f9d9c2605265a7142d77c26ab62edc620e6bcf810d581d2ee31b79"

# EG. fabric-installer-1.1.1.jar
FABRIC_INSTALLER_JAR_NAME="fabric-installer-${FABRIC_INSTALLER_VERSION}.jar"
# eg. https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.1.1/fabric-installer-1.1.1.jar
FABRIC_INSTALLER_JAR_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_INSTALLER_VERSION}/${FABRIC_INSTALLER_JAR_NAME}"
FABRIC_INSTALLER_JAR_PATH="${SERVER_DIR}/${FABRIC_INSTALLER_JAR_NAME}"

SERVICE_NAME="minecraft-fabric-server"
SERVICE_FILE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# ========================================================
# END VARIABLES
# ========================================================

# Create a application user
id "${APPLICATION_USER}" >/dev/null 2>&1 || sudo adduser "${APPLICATION_USER}"
sudo chown -R mcuser:mcuser /home/mcuser
sudo chmod 755 /home/mcuser

# Setup a server directory
sudo mkdir -p "${SERVER_DIR}"
sudo chown "${APPLICATION_USER}:${APPLICATION_USER}" "${SERVER_DIR}"

# Link stateful files and directories
# TODO: Store server-icon in this repo and use cloud-init's write_files to
# write it to the server directory
sudo ln -s "${STATE_DIR}/server-icon.png" "${SERVER_DIR}/server-icon.png"
sudo ln -s "${STATE_DIR}/world" "${SERVER_DIR}/world"
sudo ln -s "${STATE_DIR}/logs" "${SERVER_DIR}/logs"
sudo ln -s "${STATE_DIR}/config" "${SERVER_DIR}/config"
sudo ln -s "${STATE_DIR}/whitelist.json" "${SERVER_DIR}/whitelist.json"
sudo ln -s "${STATE_DIR}/banned-ips.json" "${SERVER_DIR}/banned-ips.json"
sudo ln -s "${STATE_DIR}/banned-players.json" "${SERVER_DIR}/banned-players.json"
sudo ln -s "${STATE_DIR}/ops.json" "${SERVER_DIR}/ops.json"

# This one is "unique" because of expert developers
sudo mkdir -p "${SERVER_DIR}/mods"
sudo ln -s "${STATE_DIR}/luckperms" "${SERVER_DIR}/mods/luckperms"
sudo chown -h "${APPLICATION_USER}:${APPLICATION_USER}" "${SERVER_DIR}/mods/luckperms"

sudo tee "${SERVER_DIR}/allowed_symlinks.txt" <<EOF
${STATE_DIR}/world
${STATE_DIR}/logs
${STATE_DIR}/config
${STATE_DIR}/whitelist.json
${STATE_DIR}/banned-ips.json
${STATE_DIR}/banned-players.json
${STATE_DIR}/ops.json
EOF

sudo tee "${SERVER_DIR}/eula.txt" <<EOF
eula=true
EOF

sudo tee "${SERVER_DIR}/server.properties" <<EOF
accepts-transfers=false
allow-flight=false
allow-nether=true
broadcast-console-to-ops=true
broadcast-rcon-to-ops=true
bug-report-link=
difficulty=hard
enable-command-block=false
enable-jmx-monitoring=false
enable-query=false
enable-rcon=true
enable-status=true
enforce-secure-profile=true
enforce-whitelist=false
entity-broadcast-range-percentage=100
force-gamemode=false
function-permission-level=2
gamemode=survival
generate-structures=true
generator-settings={}
hardcore=false
hide-online-players=false
initial-disabled-packs=
initial-enabled-packs=vanilla
level-name=world
level-seed=
level-type=minecraft\:normal
log-ips=true
max-chained-neighbor-updates=1000000
max-players=20
max-tick-time=60000
# https://minecraft.fandom.com/wiki/Server.properties
# Setting max-world-size to 4000 gives the player an 8000×8000 world border.
max-world-size=4000
motd=The COOP Minecraft Server!
network-compression-threshold=256
online-mode=true
op-permission-level=4
player-idle-timeout=0
prevent-proxy-connections=false
pvp=true
query.port=25565
rate-limit=0
rcon.password=coop
rcon.port=50323
region-file-compression=deflate
require-resource-pack=false
resource-pack=
resource-pack-id=
resource-pack-prompt=
resource-pack-sha1=
server-ip=
server-port=25565
simulation-distance=10
spawn-animals=true
spawn-monsters=true
spawn-npcs=true
spawn-protection=0
sync-chunk-writes=true
text-filtering-config=
use-native-transport=true
view-distance=16
white-list=true
EOF
# Something seems to want to access this, which is odd? Hasn't created any
# issues but I saw a warning in the logs while spinning this fella up
sudo chown "${APPLICATION_USER}:${APPLICATION_USER}" "${SERVER_DIR}/server.properties"

sudo tee "${SERVICE_FILE_PATH}" <<EOF
[Unit]
Description=Minecraft Fabric Server
After=network.target

[Service]
Type=simple
User=${APPLICATION_USER}
Group=${APPLICATION_USER}

WorkingDirectory=${SERVER_DIR}
ExecStart=java -jar ${SERVER_DIR}/fabric-server-launch.jar nogui
KillSignal=SIGTERM

Restart=always
RestartSec=5

SuccessExitStatus=143
KillSignal=SIGTERM
TimeoutStopSec=60
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
sudo mkdir -p /etc/systemd/system/multi-user.target.wants
sudo ln -sf \
  "${SERVICE_FILE_PATH}" \
  "/etc/systemd/system/multi-user.target.wants/${SERVICE_NAME}.service"

# Install Amazon's java runtime
sudo yum install -y java-21-amazon-corretto-headless

# Download the server jar
sudo curl -o "${FABRIC_INSTALLER_JAR_PATH}" -OJ "${FABRIC_INSTALLER_JAR_URL}"
check_the_sum "${FABRIC_INSTALLER_JAR_PATH}" "${FABRIC_INSTALLER_JAR_CHECKSUM}"

# Install a RCON client
sudo curl -o /usr/local/bin/rcon -L "https://github.com/Sch8ill/rcon/releases/download/1.4.0/rcon-cli-v1.4.0-linux-arm64"
check_the_sum "/usr/local/bin/rcon" "ba600de1c96a24d7b388777c1521e43e3a1a78e4401d5d019ffb52d37f625899"
sudo chmod +x /usr/local/bin/rcon

# Now for modifications!

# Not yet setup
# download_mod "https://cdn.modrinth.com/data/PFb7ZqK6/versions/DJbC2aUl/squaremap-fabric-mc1.21.1-1.2.7.jar" "d8b06c000a7d1701deef44effab230d0810300f8b6daeeb01033d2f1d98fc06b"
# Disabled because of crash, cba to debug atm.
# download_mod "https://cdn.modrinth.com/data/gvQqBUqZ/versions/5szYtenV/lithium-fabric-mc1.21.1-0.13.0.jar" "10d371fee397bf0306e1e2d863c54c56442bcc2dc6e01603f1469f2fe4910d61"

download_mod "https://cdn.modrinth.com/data/P7dR8mSH/versions/qKPgBeHl/fabric-api-0.104.0%2B1.21.1.jar" "b1aeaf90a9af7b5fd4069147bfb8b5bd4c66e4756248ae12fed776e2da694a1a"
download_mod "https://cdn.modrinth.com/data/KOHu7RCS/versions/Kxy5mXbm/Moonrise-Fabric-0.1.0-beta.2%2B44f8058.jar" "dfee191fbb525d0af10893aff55da02ee96e91d9e337b9eca75dc9724679a4b5"
download_mod "https://cdn.modrinth.com/data/fALzjamp/versions/dPliWter/Chunky-1.4.16.jar" "c9f03e322e631ee94ccb8dbf3776859cd12766e513b7533e9f966e799db47937"
download_mod "https://cdn.modrinth.com/data/s86X568j/versions/uT1cdd3k/ChunkyBorder-1.2.18.jar" "0a4066b36603e1d91fe7d11cce8e2eb066c668828889c866ce08d1baf469f351"
# SEE: https://download.geysermc.org/v2/projects/geyser/versions/latest for a list of versions
# SEE: https://github.com/GeyserMC/GeyserWebsite/blob/master/openapi/downloads.json for API spec
# Geyser returns a UTF8 filename content-disposition header, which is not supported by curl, we need to manually specifiy the filename here.
download_mod "https://download.geysermc.org/v2/projects/geyser/versions/2.4.3/builds/676/downloads/fabric" "cfb15ad7c1b938af8ad96554d2764549f66899262cc3579fdcdbc94bcc5400a5" "Geyser-Fabric.jar"
download_mod "https://cdn.modrinth.com/data/bWrNNfkb/versions/wPa1pHZJ/Floodgate-Fabric-2.2.4-b36.jar" "89fcd6add678289a10a45b2976198e43e149b7054c686b5fcb85d039c7b05746"
download_mod "https://cdn.modrinth.com/data/Vebnzrzj/versions/l47d4ZWk/LuckPerms-Fabric-5.4.140.jar" "3e17d490f87761c174478f68860367610a473ff5c2a9a9daad608773bf0e81bc"
download_mod "https://cdn.modrinth.com/data/8dI2tmqs/versions/KqB3UA0q/FabricProxy-Lite-2.10.1.jar" "36737b62c7a5dfb679ac3fac6a7db10f9a423317fba19574bc4d472b4711c742"

# Cron script for pushing player count
sudo tee /usr/local/bin/push_player_count.sh <<'SCRIPT'
#!/bin/bash
LINE=$(/usr/local/bin/rcon --no-colors -a localhost:50323 -p 'coop' -c 'list')
PLAYER_COUNT=$(echo "$LINE" | sed -n 's/There are \([0-9]\+\) .*/\1/p')

aws cloudwatch put-metric-data \
--namespace coopmcserver \
--metric-name playercount \
--value "$PLAYER_COUNT" \
SCRIPT
sudo chmod +x /usr/local/bin/push_player_count.sh

# Systemd timer for pushing player count every 5 minutes
sudo tee /etc/systemd/system/push_player_count.timer <<EOF
[Unit]
Description=Push Minecraft player count to CloudWatch every 5 minutes
[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Unit=push_player_count.service
[Install]
WantedBy=timers.target
EOF
sudo mkdir -p /etc/systemd/system/timers.target.wants
sudo ln -sf /etc/systemd/system/push_player_count.timer \
            /etc/systemd/system/timers.target.wants/push_player_count.timer

sudo tee /etc/systemd/system/push_player_count.service <<EOF
[Unit]
Description=Push Minecraft player count to CloudWatch
[Service]
Type=oneshot
ExecStart=/usr/local/bin/push_player_count.sh
StandardOutput=journal
StandardError=journal
EOF
sudo mkdir -p /etc/systemd/system/multi-user.target.wants
sudo ln -sf /etc/systemd/system/push_player_count.service \
            /etc/systemd/system/multi-user.target.wants/push_player_count.service

# Install server files using the fabric installer
sudo su - "${APPLICATION_USER}" -c "cd '${SERVER_DIR}' && java -jar '${FABRIC_INSTALLER_JAR_PATH}' server -mcversion '${MINECRAFT_VERSION}' -downloadMinecraft"

# TODO https://downloadmoreram.com/
