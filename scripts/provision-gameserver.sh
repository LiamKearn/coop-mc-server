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
STATE_DEVICE_PATH="/dev/sdf"

SERVER_DIR="/home/${APPLICATION_USER}/minecraft"
STATE_DIR="/home/${APPLICATION_USER}/mcstate"

MINECRAFT_VERSION="1.21.11"
FABRIC_INSTALLER_VERSION="1.1.1"
FABRIC_INSTALLER_JAR_CHECKSUM="2487a69dd6f9d9c2605265a7142d77c26ab62edc620e6bcf810d581d2ee31b79"

# EG. fabric-installer-1.1.1.jar
FABRIC_INSTALLER_JAR_NAME="fabric-installer-${FABRIC_INSTALLER_VERSION}.jar"
# eg. https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.1.1/fabric-installer-1.1.1.jar
FABRIC_INSTALLER_JAR_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_INSTALLER_VERSION}/${FABRIC_INSTALLER_JAR_NAME}"
FABRIC_INSTALLER_JAR_PATH="${SERVER_DIR}/${FABRIC_INSTALLER_JAR_NAME}"

SYSTEMD_MINECRAFT_STATE_MOUNT="home-mcuser-mcstate.mount"
SYSTEMD_FABRIC_SERVICE="minecraft-fabric-server.service"
SYSTEMD_PUSH_PLAYER_COUNT_ONESHOT="push_player_count.service"
SYSTEMD_PUSH_PLAYER_COUNT_TIMER="push_player_count.timer"

# ========================================================
# END VARIABLES
# ========================================================

# Install Amazon's java runtime early in the background since it takes ages
sudo yum install -y java-21-amazon-corretto-headless &
JAVA_INSTALL_PID=$!

# Create a application user
sudo adduser "${APPLICATION_USER}"
sudo chown -R "${APPLICATION_USER}:${APPLICATION_USER}" "/home/${APPLICATION_USER}"
sudo chmod 755 "/home/${APPLICATION_USER}"

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
allow-flight=true
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
max-players=67
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
view-distance=20
white-list=true
EOF
# Something seems to want to access this, which is odd? Hasn't created any
# issues but I saw a warning in the logs while spinning this fella up
sudo chown "${APPLICATION_USER}:${APPLICATION_USER}" "${SERVER_DIR}/server.properties"

# Mount the state disk as a systemd mount so that the server service can depend on it
sudo tee "/etc/systemd/system/${SYSTEMD_MINECRAFT_STATE_MOUNT}" <<EOF
[Unit]
Description=Minecraft State Disk
Requires=local-fs.target
Requires=dev-sdf.device
After=local-fs.target
After=dev-sdf.device

[Mount]
What=${STATE_DEVICE_PATH}
Where=${STATE_DIR}
Type=ext4
Options=defaults,nofail

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir -p /etc/systemd/system/multi-user.target.wants
sudo ln -sf \
    "/etc/systemd/system/${SYSTEMD_MINECRAFT_STATE_MOUNT}" \
    "/etc/systemd/system/multi-user.target.wants/${SYSTEMD_MINECRAFT_STATE_MOUNT}"

sudo tee "/etc/systemd/system/${SYSTEMD_FABRIC_SERVICE}" <<EOF
[Unit]
Description=Minecraft Fabric Server
Requires=${SYSTEMD_MINECRAFT_STATE_MOUNT}
After=${SYSTEMD_MINECRAFT_STATE_MOUNT}
After=network.target

[Service]
Type=simple
User=${APPLICATION_USER}
Group=${APPLICATION_USER}

WorkingDirectory=${SERVER_DIR}
ExecStart=java -jar ${SERVER_DIR}/fabric-server-launch.jar nogui

StandardOutput=journal
StandardError=journal

KillSignal=SIGTERM
TimeoutStopSec=60
# MC is a JVM process, which can 143 on SIGTERM
SuccessExitStatus=143

Restart=always
RestartSec=5

LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
sudo mkdir -p /etc/systemd/system/multi-user.target.wants
sudo ln -sf \
  "/etc/systemd/system/${SYSTEMD_FABRIC_SERVICE}" \
  "/etc/systemd/system/multi-user.target.wants/${SYSTEMD_FABRIC_SERVICE}"

# Download the server jar
sudo curl -o "${FABRIC_INSTALLER_JAR_PATH}" -OJ "${FABRIC_INSTALLER_JAR_URL}"
check_the_sum "${FABRIC_INSTALLER_JAR_PATH}" "${FABRIC_INSTALLER_JAR_CHECKSUM}"

# Install a RCON client
sudo curl -o /usr/local/bin/rcon -L "https://github.com/Sch8ill/rcon/releases/download/1.4.0/rcon-cli-v1.4.0-linux-arm64"
check_the_sum "/usr/local/bin/rcon" "ba600de1c96a24d7b388777c1521e43e3a1a78e4401d5d019ffb52d37f625899"
sudo chmod +x /usr/local/bin/rcon

# Now for modifications!

download_mod "https://cdn.modrinth.com/data/P7dR8mSH/versions/DdVHbeR1/fabric-api-0.141.1%2B1.21.11.jar" "6a577f83bd8b33c9404127d16531acc9c4195f47de0395957c9d4cd09d7b98c6"
download_mod "https://cdn.modrinth.com/data/Vebnzrzj/versions/CzCJJMuo/LuckPerms-Fabric-5.5.21.jar" "98db2f98bbdab74a36c74e8b42e5f5f15e6991051f4a2a55f4ddab4a10ce1304"
download_mod "https://cdn.modrinth.com/data/8dI2tmqs/versions/nR8AIdvx/FabricProxy-Lite-2.11.0.jar" "ebc7abeaf6c03ac619c701ebb332de6966c6d83edfabf02434720c8fc3d03cdc"
download_mod "https://cdn.modrinth.com/data/fdZkP5Bb/versions/hA27RLKS/vanilla-permissions-0.3.3%2B1.21.11.jar" "95fa72dcd5076b53d84c9d3ecd2c637b2cc5f3b61970eab4517ca4737c95438a"
download_mod "https://cdn.modrinth.com/data/gvQqBUqZ/versions/gl30uZvp/lithium-fabric-0.21.2%2Bmc1.21.11.jar" "3106639c73ee23f44bfbe5e5e7a8154dfe3ad0fd48491e4a85767598ed7b0739"
download_mod "https://cdn.modrinth.com/data/zQhsx8KF/versions/RyZYsN9V/servux-fabric-1.21.11-0.9.1.jar" "b2124f6509f0d52bc2bb32cbfe7ffae0372dd6ff2813f16a483ac3c987a636ba"

# TODO, first systemd oneshot fails because the server isn't running yet.
# `Jan 13 22:11:21 ip-172-31-25-83.ec2.internal push_player_count.sh[1983]: RCON response line: 'error while trying to connect: dial tcp 127.0.0.1:50323: connect: >`
# We could add a dependency on the minecraft-fabric-server.service
#
# Cron script for pushing player count
sudo tee /usr/local/bin/push_player_count.sh <<'SCRIPT'
#!/bin/bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 100")
INSTANCE_ID=$(curl -s \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
LINE=$(/usr/local/bin/rcon --no-colors -a localhost:50323 -p 'coop' -c 'list' | tr -d '\0')
PLAYER_COUNT=$(echo "$LINE" | sed -n 's/There are \([0-9]\+\) .*/\1/p')

echo "Instance ID: $INSTANCE_ID"
echo "RCON response line: '$LINE'"
echo "Pushing player count: $PLAYER_COUNT"

aws cloudwatch put-metric-data \
--namespace coopmcserver \
--metric-name playercount \
--dimensions InstanceId="$INSTANCE_ID" \
--value "$PLAYER_COUNT"
SCRIPT
sudo chmod +x /usr/local/bin/push_player_count.sh

# Systemd timer for pushing player count every 5 minutes
sudo tee "/etc/systemd/system/${SYSTEMD_PUSH_PLAYER_COUNT_TIMER}" <<EOF
[Unit]
Description=Push Minecraft player count to CloudWatch every 5 minutes
Requires=${SYSTEMD_PUSH_PLAYER_COUNT_ONESHOT}
Requires=${SYSTEMD_FABRIC_SERVICE}
After=${SYSTEMD_FABRIC_SERVICE}
[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Unit=push_player_count.service
[Install]
WantedBy=timers.target
EOF
sudo mkdir -p /etc/systemd/system/timers.target.wants
sudo ln -sf "/etc/systemd/system/${SYSTEMD_PUSH_PLAYER_COUNT_TIMER}" \
            "/etc/systemd/system/timers.target.wants/${SYSTEMD_PUSH_PLAYER_COUNT_TIMER}"

sudo tee "/etc/systemd/system/${SYSTEMD_PUSH_PLAYER_COUNT_ONESHOT}" <<EOF
[Unit]
Description=Push Minecraft player count to CloudWatch
Requires=${SYSTEMD_FABRIC_SERVICE}
[Service]
Type=oneshot
ExecStart=/usr/local/bin/push_player_count.sh
StandardOutput=journal
StandardError=journal
EOF
sudo mkdir -p /etc/systemd/system/multi-user.target.wants
sudo ln -sf "/etc/systemd/system/${SYSTEMD_PUSH_PLAYER_COUNT_ONESHOT}" \
            "/etc/systemd/system/multi-user.target.wants/${SYSTEMD_PUSH_PLAYER_COUNT_ONESHOT}"

# Install server files using the fabric installer
wait $JAVA_INSTALL_PID
sudo su - "${APPLICATION_USER}" -c "cd '${SERVER_DIR}' && java -jar '${FABRIC_INSTALLER_JAR_PATH}' server -mcversion '${MINECRAFT_VERSION}' -downloadMinecraft"

# TODO https://downloadmoreram.com/
