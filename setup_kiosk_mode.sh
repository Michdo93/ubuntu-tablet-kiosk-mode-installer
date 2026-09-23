#!/bin/bash
# FILE: setup_kiosk_mode.sh

# ==========================================
# KONFIGURATION / VARIABLEN
# ==========================================
USER_NAME="ubuntu"
KIOSK_URL="https://google.de"

# WLAN Konfiguration
WLAN_SSID="DEIN_WLAN_NAME"
WLAN_PASS="DEIN_WLAN_PASSWORT"
WLAN_IFACE="wlan0"

# ==========================================
# SKRIPT-AUSFÜHRUNG
# ==========================================

echo "--- 1. System-Update & Installation ---"
sudo apt update && sudo apt upgrade -y
sudo apt install -y chromium-browser openssh-server unclutter x11-xserver-utils \
                    curl avahi-daemon xserver-xorg xinit matchbox-window-manager \
                    nodm x11-common network-manager

echo "--- 2. Rechte für X-Server ohne Login setzen ---"
# Erlaubt den Start von X durch Hintergrundprozesse
sudo bash -c "echo 'allowed_users=anybody' > /etc/X11/Xwrapper.config"
sudo bash -c "echo 'needs_root_rights=yes' >> /etc/X11/Xwrapper.config"

echo "--- 3. Passwortloses Sudo für $USER_NAME ---"
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/kiosk-nopasswd

echo "--- 4. Kiosk-Browser-Skript erstellen ---"
mkdir -p /home/$USER_NAME/scripts
cat <<EOF > /home/$USER_NAME/scripts/kiosk.sh
#!/bin/bash
xset s off
xset s noblank
xset -dpms
unclutter -idle 0.1 -root &
matchbox-window-manager -use_titlebar no &

while true; do
  chromium-browser \
    --kiosk \
    --no-first-run \
    --simulate-outdated-no-au \
    --disable-restore-session-state \
    --window-position=0,0 \
    --check-for-update-interval=31536000 \
    --noerrdialogs \
    --disable-infobars \
    '$KIOSK_URL'
  sleep 5
done
EOF
chmod +x /home/$USER_NAME/scripts/kiosk.sh
chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/scripts

echo "--- 5. Systemd Kiosk Service erstellen ---"
sudo bash -c "cat <<EOF > /etc/systemd/system/kiosk.service
[Unit]
Description=Standalone Kiosk
After=network-online.target
Wants=network-online.target

[Service]
User=$USER_NAME
Environment=DISPLAY=:0
PAMName=login
Type=simple
ExecStart=/usr/bin/startx /home/$USER_NAME/scripts/kiosk.sh -- -nocursor -quiet -keeptty vt1
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

echo "--- 6. Boot-Optionen & Konsolen-Login deaktivieren ---"
# Verhindert, dass der Standard-Login-Prompt (Getty) die Tastatur/Monitor übernimmt
sudo systemctl set-default multi-user.target
sudo systemctl disable sddm 2>/dev/null
sudo systemctl mask getty@tty1.service

echo "--- 7. WLAN & Energiesparmodi ---"
sudo iw reg set DE

# Bestehende Verbindung mit demselben Namen löschen (falls vorhanden)
sudo nmcli connection delete "$WLAN_SSID" 2>/dev/null

# Neue Verbindung dynamisch anlegen
sudo nmcli connection add type wifi con-name "$WLAN_SSID" ifname "$WLAN_IFACE" ssid "$WLAN_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WLAN_PASS"

sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

sudo systemctl enable kiosk.service
echo "FERTIG. System startet neu..."
sudo reboot
