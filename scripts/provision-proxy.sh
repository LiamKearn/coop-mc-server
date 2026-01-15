#!/usr/bin/env sh
set -xe

# ========================================================
# START VARIABLES
# ========================================================

APPLICATION_USER="proxy"

SYSTEMD_PROXY_SERVICE="proxy.service"
SYSTEMD_LIMBO_SERVICE="limbo.service"

# ========================================================
# END VARIABLES
# ========================================================

# Create a application user
sudo adduser "${APPLICATION_USER}"
# Just for provisioning, will be changed later in provisioning
sudo chown ec2-user:ec2-user "/home/${APPLICATION_USER}"

sudo curl -o pico.tar.gz -L "https://github.com/Quozul/PicoLimbo/releases/download/v1.10.1%2Bmc1.21.11/pico_limbo_linux-aarch64-gnu.tar.gz"
sudo tar -xzf pico.tar.gz
sudo rm pico.tar.gz
sudo mv pico_limbo "/home/${APPLICATION_USER}/limbo"
sudo chown "${APPLICATION_USER}:${APPLICATION_USER}" "/home/${APPLICATION_USER}/limbo"

sudo mkdir -p /etc/systemd/system/multi-user.target.wants

sudo tee "/etc/systemd/system/${SYSTEMD_LIMBO_SERVICE}" << EOF
[Unit]
Description=Pico Limbo Server
After=network.target

[Service]
Type=simple
User=${APPLICATION_USER}
Group=${APPLICATION_USER}

WorkingDirectory=/home/${APPLICATION_USER}/
ExecStart=/home/${APPLICATION_USER}/limbo

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
After=network.target
After=${SYSTEMD_LIMBO_SERVICE}
Requires=${SYSTEMD_LIMBO_SERVICE}

[Service]
Type=simple
User=${APPLICATION_USER}
Group=${APPLICATION_USER}

WorkingDirectory=/home/${APPLICATION_USER}/
ExecStart=/home/${APPLICATION_USER}/proxy
EnvironmentFile=/home/${APPLICATION_USER}/proxy.env

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
