#!/bin/bash
set -e # Abort the script at first error
set -u # Treat unset variables as an error

# -----------------------
# Variables
# -----------------------

# File and directory paths
KEYS_DIR=~/keys
MINA_ENV_FILE=~/.mina-env
MINA_SERVICE_FILE=/usr/lib/systemd/user/mina.service

# APT Repository details
REPO_URL="http://packages.o1test.net"
REPO_DISTRO="focal"
REPO_COMPONENT="rampup"
MINA_PACKAGE="mina-berkeley=2.0.0rampup7-4a0fff9"

# -----------------------
# Functions
# -----------------------

# Ensure a variable is set and not empty
ensure_var() {
    local var_name="$1"
    local prompt_msg="$2"

    while true; do
        read -p "$prompt_msg" "$var_name"
        if [[ -z "${!var_name}" ]]; then
            echo "Input cannot be empty."
        else
            break
        fi
    done
}

# -----------------------
# Main Script
# -----------------------

# Remove old APT sources and add the new source
sudo rm -f /etc/apt/sources.list.d/mina*.list
echo "deb [trusted=yes] $REPO_URL $REPO_DISTRO $REPO_COMPONENT" | sudo tee /etc/apt/sources.list.d/mina-rampup.list

# Update APT and install the specified version of Mina
sudo apt-get update
sudo apt-get install -y "$MINA_PACKAGE"

# Create and set permissions for keys directory
mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"

# Read and verify user inputs
ensure_var json_string "Enter the key json string: "
ensure_var public_key "Enter public key: "
ensure_var external_ip "Enter external IP: "
ensure_var MINA_PRIVKEY_PASS "Enter MINA_PRIVKEY_PASS: " -s

# Write keys and permissions
echo "$json_string" > "$KEYS_DIR/my-wallet"
echo "$public_key" > "$KEYS_DIR/my-wallet.pub"
chmod 600 "$KEYS_DIR/my-wallet" "$KEYS_DIR/my-wallet.pub"

# Generate Mina keypair
mina libp2p generate-keypair -privkey-path "$KEYS_DIR/keys"

# Generate Mina environment file
cat <<EOL > "$MINA_ENV_FILE"
MINA_PRIVKEY_PASS="$MINA_PRIVKEY_PASS"
UPTIME_PRIVKEY_PASS="$MINA_PRIVKEY_PASS"
MINA_LIBP2P_PASS="$MINA_PRIVKEY_PASS"
EXTRA_FLAGS="--log-json --log-snark-work-gossip true --internal-tracing --insecure-rest-server --log-level Debug --file-log-level Debug --config-directory /root/.mina-config/ --external-ip $external_ip --itn-keys  f1F38+W3zLcc45fGZcAf9gsZ7o9Rh3ckqZQw6yOJiS4=,6GmWmMYv5oPwQd2xr6YArmU1YXYCAxQAxKH7aYnBdrk=,ZJDkF9EZlhcAU1jyvP3m9GbkhfYa0yPV+UdAqSamr1Q=,NW2Vis7S5G1B9g2l9cKh3shy9qkI1lvhid38763vZDU=,Cg/8l+JleVH8yNwXkoLawbfLHD93Do4KbttyBS7m9hQ= --itn-graphql-port 3089 --uptime-submitter-key  /root/keys/my-wallet --uptime-url https://block-producers-uptime-itn.minaprotocol.tools/v1/submit --metrics-port 10001 --enable-peer-exchange  true --libp2p-keypair /root/keys/keys --log-precomputed-blocks true --peer-list-url  https://storage.googleapis.com/seed-lists/testworld-2-0_seeds.txt --generate-genesis-proof  true --block-producer-key /root/keys/my-wallet --node-status-url https://nodestats-itn.minaprotocol.tools/submit/stats  --node-error-url https://nodestats-itn.minaprotocol.tools/submit/stats  --file-log-rotations 500"
RAYON_NUM_THREADS=6
EOL

chmod 600 "$MINA_ENV_FILE"

# Generate and start the Mina systemd service
cat <<EOL | sudo tee "$MINA_SERVICE_FILE"
[Unit]
Description=Mina Daemon Service
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Environment="PEERS_LIST_URL=https://storage.googleapis.com/seed-lists/testworld-2-0_seeds.txt"
Environment="LOG_LEVEL=Info"
Environment="FILE_LOG_LEVEL=Debug"
EnvironmentFile=%h/.mina-env
Type=simple
Restart=always
RestartSec=30
ExecStart=/usr/local/bin/mina daemon \$EXTRA_FLAGS
ExecStop=/usr/local/bin/mina client stop-daemon

[Install]
WantedBy=default.target
EOL

# Reload systemd, restart Mina service, enable it to start at boot, and enable user lingering
sudo systemctl daemon-reload
systemctl --user restart mina
systemctl --user enable mina
loginctl enable-linger

# Show recent logs and follow new logs
journalctl  -u mina -n 1000 -f
