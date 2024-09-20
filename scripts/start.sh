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
        curl -o "${DOWNLOADED_PATH}" -sSOJ "${URL}"
    else
        echo "Not forcing output name"
        DOWNLOADED_PATH=$(curl --output-dir "${SERVER_DIR}/mods" -sSOJ "${URL}" -w "%{filename_effective}\n" )
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

# Setup the state directory
sudo mkdir -p "${STATE_DIR}"

# Setup the EBS volume to be mounted
sudo cat >> /etc/fstab <<EOF
${STATE_DEVICE_NAME} ${STATE_DIR} ext4 defaults,nofail 0 2
EOF

# Wait for the EBS volume to be attached
while [ ! -e "${STATE_DEVICE_NAME}" ]; do sleep 1; done

# Test if there is an existing filesystem on the volume, if not make one
if ! blkid "${STATE_DEVICE_NAME}"; then
    mkfs -t ext4 "${STATE_DEVICE_NAME}"
fi

# Mount the volume
sudo mount -a

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

# This one is "unique" because of expert developers
mkdir -p "${SERVER_DIR}/mods"
ln -s "${STATE_DIR}/luckperms" "${SERVER_DIR}/mods/luckperms"
chown -h "${APPLICATION_USER}:${APPLICATION_USER}" "${SERVER_DIR}/mods/luckperms"

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
view-distance=16
white-list=true
EOF
# Something seems to want to access this, which is odd? Hasn't created any
# issues but I saw a warning in the logs while spinning this fella up
chown "${APPLICATION_USER}:${APPLICATION_USER}" "${SERVER_DIR}/server.properties"

cat <<EOF > "${SERVER_DIR}/start-server.sh"
#!/usr/bin/env sh
set -xe

# Run in loop to restart the server if it crashes
while true; do
    java -jar ${SERVER_DIR}/${JAR_NAME} nogui -dir ${SERVER_DIR}
    echo "Server crashed, restarting in 5.."
    sleep 5
done
EOF
chown "${APPLICATION_USER}:${APPLICATION_USER}" "${SERVER_DIR}/start-server.sh"
chmod +x "${SERVER_DIR}/start-server.sh"

# Install Amazon's java runtime
sudo yum install -y java-21-amazon-corretto-headless

# Download the server jar
curl -o "${JAR_PATH}" -OJ "${DOWNLOAD_LOCATION}"
check_the_sum "${JAR_PATH}" "${SERVER_JAR_CHECKSUM}"

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

# Start the minecraft server as the application user running in a named screen session
su - "${APPLICATION_USER}" -c "screen -S mc -d -m ${SERVER_DIR}/start-server.sh"

# TODO https://downloadmoreram.com/
