#!/bin/bash
# the whole script is based on a username "admin" and if you are using another user account, you have to change user "admin" inside of the code with your specify account
set -e

# ------------------- 1. SYSTEM DEPENDENCIES -------------------
echo "Installing dependencies..."
apt update && \
apt install -y curl gnupg --no-install-recommends
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
apt install -y nodejs docker.io docker-compose pulseaudio pulseaudio-utils alsa-utils socat mpv dbus nano git jq build-essential --no-install-recommends

# ------------------- 2. USER GROUPS -------------------
echo "Adding user to groups..."
usermod -aG audio,docker admin

# ------------------- 3. PULSEAUDIO SERVICE -------------------
echo "Creating PulseAudio systemd service..."
cat <<EOF > /etc/systemd/system/pulseaudio.service
[Unit]
Description=PulseAudio system server
After=sound.target network.target
Requires=sound.target

[Service]
Type=notify
ExecStart=/usr/bin/pulseaudio --system --realtime --disallow-exit --no-cpu-limit --load="module-native-protocol-unix auth-anonymous=1 socket=/var/run/pulse/native"
RuntimeDirectory=pulse
RuntimeDirectoryMode=0755
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pulseaudio.service
systemctl restart pulseaudio.service

# ------------------- 4. MODIFY system.pa -------------------
echo "Modifying /etc/pulse/system.pa..."
cp /etc/pulse/system.pa /etc/pulse/system.pa.bak

sed -i 's|^\s*load-module\s\+module-esound-protocol-unix\s*.*$|load-module module-native-protocol-unix auth-anonymous=1 socket=/var/run/pulse/native|' /etc/pulse/system.pa
sed -i '/^load-module module-native-protocol-unix$/d' /etc/pulse/system.pa

systemctl restart pulseaudio

# ------------------- 5. DOWNLOAD PROJECT FILES -------------------
echo "Downloading project files..."
mkdir -p /home/admin/pa
cd /home/admin/pa
cp /data/repo/PA/* .
chown -R admin:admin /home/admin/pa

# ------------------- 6 BUILD AND RUN DOCKER -------------------
echo "Building Docker image and running Linphone container..."
cd /home/admin/pa
sudo -u admin newgrp docker <<EOF
docker network create radiopa
docker build -t pa .
docker run -dit \
  --restart unless-stopped \
  --network radiopa \
  --name pa \
  -v /var/run/pulse:/var/run/pulse \
  -e PULSE_SERVER=unix:/var/run/pulse/native \
  --device /dev/snd:/dev/snd \
  -e TZ=Australia/Adelaide \
  -v /usr/share/zoneinfo:/usr/share/zoneinfo:ro \
  -v /home/admin/pa/pa.sh:/opt/pa.sh \
  -v /home/admin/pa/linphonerc:/opt/linphonerc \
  -v /home/admin/pa/pa.log:/var/log/pa.log \
  -v /home/admin/pa/darkice.cfg:/etc/darkice.cfg \
  pa

# ------------------- 6.1 BUILD AND RUN DOCKER -------------------
echo "Building Docker image and running Icecast container..."
docker run -dit \
  --restart unless-stopped \
  --network radiopa \
  --name icecast \
  -p 3001:8000 \
  -e ICECAST_ADMIN_PASSWORD=Admin \
  -e ICECAST_SOURCE_PASSWORD=Admin \
  -e ICECAST_RELAY_PASSWORD=Admin \
  -e ICECAST_PASSWORD=Admin \
  moul/icecast
EOF

# ------------------- 7. SETUP NODE DASHBOARD -------------------
echo "Setting up Node.js dashboard..."
mkdir -p /home/admin/pa/pa-dashboard/public
cd /home/admin/pa
mv server.js pa-dashboard/
cd pa-dashboard
npm init -y || {
    echo "npm init failed. Trying to fix with apt..."
    sudo apt --fix-broken install -y && npm init -y || {
        echo "Failed again. Exiting."
        exit 1
    }
}
npm install express body-parser
chown -R admin:admin /home/admin/pa

cd public
mv /home/admin/pa/default.html /home/admin/pa/pa-dashboard/public/index.html
mv /home/admin/pa/banner.jpg /home/admin/pa/pa-dashboard/public/banner.jpg
mv /home/admin/pa/favicon.ico /home/admin/pa/pa-dashboard/public/favicon.ico

# ------------------- 8. SYSTEMD SERVICE FOR DASHBOARD -------------------
echo "Creating systemd service for dashboard..."
cat <<EOF > /etc/systemd/system/pa-dashboard.service
[Unit]
Description=Radio Config Dashboard
After=network.target

[Service]
ExecStart=/usr/bin/node /home/admin/pa/pa-dashboard/server.js
WorkingDirectory=/home/admin/pa/pa-dashboard
Restart=always
User=admin
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pa-dashboard

# ------------------- 9. FIREWALL -------------------
echo "Allowing port 3000 on firewall..."
ufw allow proto tcp to 0.0.0.0/0 port 3000 comment "PA Config Dashboard"
ufw allow proto tcp to 0.0.0.0/0 port 3001 comment "PA Online Stream"
ufw default allow routed
ufw reload
echo "Setup completed successfully."
