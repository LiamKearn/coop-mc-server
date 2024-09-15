#!/usr/bin/env sh
set -e

# ========================================================
# START FUNCTIONS
# ========================================================

check_the_sum() {
    FILE=$1
    EXPECTED=$2
    ACTUAL=$(sha256sum $FILE | cut -d ' ' -f 1)
    echo "Checking the of ${FILE}"
    echo "Expected: ${EXPECTED}"
    echo "Actual: ${ACTUAL}"
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "Checksum of ${FILE} does not match expected checksum, exiting"
        rm -f $FILE
        exit 1
    fi
    echo "Checksum matches!"
}

download_mod() {
    URL=$1
    CHECKSUM=$2
    curl --output-dir "${SERVER_DIR}/mods" -OJ "${URL}"
    check_the_sum "${SERVER_DIR}/mods/$(basename $URL)" "${CHECKSUM}"
}

# ========================================================
# END FUNCTIONS
# ========================================================

# ========================================================
# START VARIABLES
# ========================================================

APPLICATION_USER="mcuser"

MINECRAFT_VERSION="1.21.1"
FABRIC_LOADER_VERSION="0.16.5"
INSTALLER_VERSION="1.0.1"
SERVER_JAR_CHECKSUM="243ac92e0ddb12b031218d46d71f211d99d4d61a73fb2538bf73beee1ab37556"

# EG. fabric-server-mc.1.21.1-loader.0.16.5-launcher.1.0.1.jar
JAR_NAME="fabric-server-mc.${MINECRAFT_VERSION}-loader.${FABRIC_LOADER_VERSION}-launcher.${INSTALLER_VERSION}.jar"
# eg. https://meta.fabricmc.net/v2/versions/loader/1.21.1/0.16.5/1.0.1/server/jar
DOWNLOAD_LOCATION="https://meta.fabricmc.net/v2/versions/loader/${MINECRAFT_VERSION}/${FABRIC_LOADER_VERSION}/${INSTALLER_VERSION}/server/jar"
SERVER_DIR="/home/${APPLICATION_USER}/minecraft"
JAR_PATH="${SERVER_DIR}/${JAR_NAME}"
STATE_DIR="/home/${APPLICATION_USER}/mcstate"

# ========================================================
# END VARIABLES
# ========================================================

# Mount the state EBS volume
# Test if there is an existing filesystem on the volume, if not mkfs.ext4 one.
# partprobe -d -s /dev/sdb
if [ $(partprobe -d -s /dev/sdf | grep -q '(no output)') ]; then
    echo "No filesystem detected on /dev/sdf, creating one"
    sudo mkfs.ext4 /dev/sdf
fi
sudo mkdir -p "${STATE_DIR}"
sudo mount /dev/sdf "${STATE_DIR}"

# Create a application user
sudo adduser "${APPLICATION_USER}"

# Setup a server directory
mkdir -p "${SERVER_DIR}"
chown "${APPLICATION_USER}:${APPLICATION_USER}" "${SERVER_DIR}"

# Link stateful files and directories
# TODO: Store server-icon in this repo and use cloud-init's write_files to
# write it to the server directory
ln -s "${STATE_DIR}/server-icon.png" "${SERVER_DIR}/server-icon.png"
ln -s "${STATE_DIR}/world" "${SERVER_DIR}/world"
ln -s "${STATE_DIR}/logs" "${SERVER_DIR}/logs"
ln -s "${STATE_DIR}/config" "${SERVER_DIR}/config"
ln -s "${STATE_DIR}/whitelist.json" "${SERVER_DIR}/whitelist.json"
ln -s "${STATE_DIR}/banned-ips.json" "${SERVER_DIR}/banned-ips.json"
ln -s "${STATE_DIR}/banned-players.json" "${SERVER_DIR}/banned-players.json"
ln -s "${STATE_DIR}/ops.json" "${SERVER_DIR}/ops.json"

cat <<EOF > "${SERVER_DIR}/allowed_symlinks.txt"
${STATE_DIR}/world
${STATE_DIR}/logs
${STATE_DIR}/config
${STATE_DIR}/whitelist.json
${STATE_DIR}/banned-ips.json
${STATE_DIR}/banned-players.json
${STATE_DIR}/ops.json
EOF

cat <<EOF > "${SERVER_DIR}/eula.txt"
eula=true
EOF

cat <<EOF > "${SERVER_DIR}/server.properties"
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
enable-rcon=false
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
rcon.password=
rcon.port=25575
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
view-distance=10
white-list=true
EOF
# Something seems to want to access this, which is odd? Hasn't created any
# issues but I saw a warning in the logs while spinning this fella up
chown "${APPLICATION_USER}:${APPLICATION_USER}" "${SERVER_DIR}/server.properties"

# Install Amazon's java runtime
sudo yum install -y java-21-amazon-corretto-headless

# Download the server jar
curl -o "${JAR_PATH}" -OJ "${DOWNLOAD_LOCATION}"
check_the_sum "${JAR_PATH}" "${SERVER_JAR_CHECKSUM}"

# Now for modifications!

mkdir -p "${SERVER_DIR}/mods"
download_mod "https://cdn.modrinth.com/data/P7dR8mSH/versions/qKPgBeHl/fabric-api-0.104.0%2B1.21.1.jar" "b1aeaf90a9af7b5fd4069147bfb8b5bd4c66e4756248ae12fed776e2da694a1a"
download_mod "https://cdn.modrinth.com/data/gvQqBUqZ/versions/5szYtenV/lithium-fabric-mc1.21.1-0.13.0.jar" "10d371fee397bf0306e1e2d863c54c56442bcc2dc6e01603f1469f2fe4910d61"
download_mod "https://cdn.modrinth.com/data/KOHu7RCS/versions/Kxy5mXbm/Moonrise-Fabric-0.1.0-beta.2%2B44f8058.jar" "dfee191fbb525d0af10893aff55da02ee96e91d9e337b9eca75dc9724679a4b5"
download_mod "https://cdn.modrinth.com/data/fALzjamp/versions/dPliWter/Chunky-1.4.16.jar" "c9f03e322e631ee94ccb8dbf3776859cd12766e513b7533e9f966e799db47937"
download_mod "https://cdn.modrinth.com/data/s86X568j/versions/uT1cdd3k/ChunkyBorder-1.2.18.jar" "0a4066b36603e1d91fe7d11cce8e2eb066c668828889c866ce08d1baf469f351"

# Start the minecraft server as the application user running in a named screen session
su - "${APPLICATION_USER}" -c "cd ${SERVER_DIR} && screen -S mc -d -m java -jar ${JAR_NAME} nogui"

# TODO https://downloadmoreram.com/
