#!/bin/bash

set -e  # Exit on error

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <hostname> <ip_address> <gateway>"
    exit 1
fi

HOSTNAME=$1
IP_ADDRESS=$2
GATEWAY=$3
SSH_KEY="YOUR-SSH-KEY-HERE"

echo "Configuring VM: $HOSTNAME ($IP_ADDRESS, Gateway: $GATEWAY)"

# Set Hostname
echo "Setting hostname..."
hostnamectl set-hostname "$HOSTNAME"

# Add to /etc/hosts if not already present
echo "Updating /etc/hosts..."

# Remove any existing 127.0.1.1 entry for the hostname
sed -i "/127.0.1.1 $HOSTNAME/d" /etc/hosts

# Remove any existing static IP entry for the hostname
sed -i "/$IP_ADDRESS $HOSTNAME/d" /etc/hosts

# Insert hostname entries above the existing IPv6 lines
sed -i "/# The following lines are desirable for IPv6 capable hosts/i\
127.0.1.1 $HOSTNAME\n\
$IP_ADDRESS $HOSTNAME\n\
" /etc/hosts

# Configure Networking (Netplan)
echo "Configuring networking..."
cat > /etc/netplan/50-cloud-init.yaml <<EOL
network:
  version: 2
  ethernets:
    ens18:
      addresses:
        - $IP_ADDRESS/29
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
EOL
netplan apply

# 3. Reset Machine ID
echo "Resetting machine ID..."
truncate -s 0 /etc/machine-id && systemd-machine-id-setup

# 4. Set Timezone
echo "Setting timezone to America/Los_Angeles..."
timedatectl set-timezone America/Los_Angeles

# 5. Add ttyS0 to GRUB (Serial Console)
echo "Configuring GRUB for serial console..."
sed -i 's/^GRUB_CMDLINE_LINUX=.*$/GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200"/' /etc/default/grub
update-grub

# 6. Add SSH Key if Not Present
echo "Ensuring SSH key is in authorized_keys..."
mkdir -p ~/.ssh
touch ~/.ssh/authorized_keys
grep -qxF "$SSH_KEY" ~/.ssh/authorized_keys || echo "$SSH_KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 7. Update System Packages (Last Step)
echo "Updating system packages..."
apt update && apt upgrade -y

# 8. Resize Disk
echo "Resizing disk and filesystem..."
pvresize /dev/sda3
lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv


echo "VM setup complete!"
