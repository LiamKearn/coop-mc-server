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

# ========================================================
# END FUNCTIONS
# ========================================================

# ========================================================
# START VARIABLES
# ========================================================

APPLICATION_USER="proxy"

SYSTEMD_PROXY_SERVICE="proxy.service"
SYSTEMD_LIMBO_SERVICE="limbo.service"
SYSTEMD_GEYSER_SERVICE="geyser.service"

SERVER_DIR="/home/${APPLICATION_USER}"
GEYSER_DIR="${SERVER_DIR}/geyser"

# ========================================================
# END VARIABLES
# ========================================================

# Install Amazon's java runtime early in the background since it takes ages
sudo yum install -y java-21-amazon-corretto-headless &
JAVA_INSTALL_PID=$!


# Create a application user
sudo adduser "${APPLICATION_USER}"
# Just for provisioning, will be changed later in provisioning
sudo chown ec2-user:ec2-user "${SERVER_DIR}"

sudo curl -o pico.tar.gz -L "https://github.com/Quozul/PicoLimbo/releases/download/v1.10.1%2Bmc1.21.11/pico_limbo_linux-aarch64-gnu.tar.gz"
check_the_sum pico.tar.gz "c6a7681b11a4d0b1e33720c16ab0003eeaaa81aa227cf58305832bd7a973f99d"
sudo tar -xzf pico.tar.gz
sudo rm pico.tar.gz
sudo mv pico_limbo "${SERVER_DIR}/limbo"
sudo chown "${APPLICATION_USER}:${APPLICATION_USER}" "${SERVER_DIR}/limbo"

sudo mkdir -p /etc/systemd/system/multi-user.target.wants

sudo tee "/etc/systemd/system/${SYSTEMD_LIMBO_SERVICE}" << EOF
[Unit]
Description=Pico Limbo Server
After=network.target

[Service]
Type=simple
User=${APPLICATION_USER}
Group=${APPLICATION_USER}

WorkingDirectory=${SERVER_DIR}/
ExecStart=${SERVER_DIR}/limbo

StandardOutput=journal
StandardError=journal

KillSignal=SIGTERM
TimeoutStopSec=5

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo ln -sf \
    "/etc/systemd/system/${SYSTEMD_LIMBO_SERVICE}" \
    "/etc/systemd/system/multi-user.target.wants/${SYSTEMD_LIMBO_SERVICE}"

sudo tee "/etc/systemd/system/${SYSTEMD_PROXY_SERVICE}" << EOF
[Unit]
Description=Minecraft Proxy Server
After=${SYSTEMD_LIMBO_SERVICE}
Requires=${SYSTEMD_LIMBO_SERVICE}
After=network.target
After=cloud-init.target
Wants=cloud-init.target

[Service]
Type=simple
User=${APPLICATION_USER}
Group=${APPLICATION_USER}

WorkingDirectory=${SERVER_DIR}
ExecStart=${SERVER_DIR}/proxy
EnvironmentFile=${SERVER_DIR}/proxy.env

StandardOutput=journal
StandardError=journal

KillSignal=SIGTERM
TimeoutStopSec=60

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo ln -sf \
  "/etc/systemd/system/${SYSTEMD_PROXY_SERVICE}" \
  "/etc/systemd/system/multi-user.target.wants/${SYSTEMD_PROXY_SERVICE}"

sudo mkdir -p "${GEYSER_DIR}"
# Just for provisioning, will be changed later in provisioning
sudo chown ec2-user:ec2-user "${GEYSER_DIR}"
sudo curl -o ${GEYSER_DIR}/geyser.jar -L "https://download.geysermc.org/v2/projects/geyser/versions/2.9.2/builds/1037/downloads/standalone"
check_the_sum ${GEYSER_DIR}/geyser.jar "adec02767b4e84c3b47d7124ed26e3c18f05b4565812e5617b9be83d92721a9f"

sudo tee "/etc/systemd/system/${SYSTEMD_GEYSER_SERVICE}" <<EOF
[Unit]
Description=Geyser Proxy Service
Requires=${SYSTEMD_PROXY_SERVICE}
After=${SYSTEMD_PROXY_SERVICE}
After=network.target

[Service]
Type=simple
User=${APPLICATION_USER}
Group=${APPLICATION_USER}

WorkingDirectory=${GEYSER_DIR}
ExecStart=java -Xms1024M -jar ${GEYSER_DIR}/geyser.jar

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
  "/etc/systemd/system/${SYSTEMD_GEYSER_SERVICE}" \
  "/etc/systemd/system/multi-user.target.wants/${SYSTEMD_GEYSER_SERVICE}"

wait $JAVA_INSTALL_PID

