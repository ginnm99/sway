#!/bin/bash

username="$(logname)"

# Check for sudo
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run with sudo."
  exit 1
fi

# Check if nvidia-inst is installed
# If it is, do the Nvidia stuff
if pacman -Qq nvidia-inst 2>/dev/null | grep -q .; then
  echo "Adding the --unsupported-gpu flag to the sway call in greetd.conf..."
  sed -i 's|sway -c|sway --unsupported-gpu -c|' etc/greetd/greetd.conf
  echo "Adding a custom desktop file for Nvidia sessions..."
  mkdir -p /usr/share/wayland-sessions
  cat <<EOF >/usr/share/wayland-sessions/sway-nvidia.desktop
[Desktop Entry]
Name=Sway-Nvidia
Comment=Sway with Nvidia
Exec=sway --unsupported-gpu
Type=Application
EOF
  echo "Adding dracut config for early module loading..."
  cat <<EOF >/etc/dracut.conf.d/nvidia-modules.conf
force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
EOF
  echo "Regenerating initrds..."
  reinstall-kernels || dracut-rebuild
fi

# Install the custom package list
echo "Installing needed packages..."
pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout $(<packages-repository.txt)

# Deploy user configs
echo "Deploying user configs..."
rsync -a .config "/home/${username}/"
rsync -a home_config/ "/home/${username}/"

# Add "NoDisplay" property to desktop files we don't want in the launcher
echo "Adding custom local desktop files..."

src=/usr/share/applications
dst="/home/${username}/.local/share/applications"

mkdir -p "$dst"

for file in \
    avahi-discover.desktop \
    bssh.desktop \
    bvnc.desktop \
    eos-log-tool.desktop \
    eos-quickstart.desktop \
    eos-update.desktop \
    foot-server.desktop \
    footclient.desktop \
    nm-connection-editor.desktop \
    org.gnome.FileRoller.desktop \
    qv4l2.desktop \
    qvidcap.desktop \
    reflector-simple.desktop \
    stoken-gui.desktop \
    stoken-gui-small.desktop \
    thunar-bulk-rename.desktop \
    thunar-settings.desktop \
    thunar-volman-settings.desktop \
    xfce4-about.desktop \
    yad-icon-browser.desktop \
    yad-settings.desktop
do
    srcfile="$src/$file"
    dstfile="$dst/$file"

    if [[ -f "$srcfile" ]]; then
        cp "$srcfile" "$dstfile"

        printf 'NoDisplay=true\n' >> "$dstfile"

        echo "Updated: $file"
    else
        echo "Missing: $srcfile" >&2
    fi
done

# Restore user ownership
chown -R "${username}:${username}" "/home/${username}"

# Deploy system configs
echo "Deploying system configs..."
rsync -a --chown=root:root etc/ /etc/

# Check if the script is running in a virtual machine
if systemd-detect-virt | grep -vq "none"; then
  echo "Virtual machine detected; enabling WLR_RENDERER_ALLOW_SOFTWARE variable in ReGreet config..."
  # Uncomment WLR_RENDERER_ALLOW_SOFTWARE variable in ReGreet config
  sed -i '/^#WLR_RENDERER_ALLOW_SOFTWARE/s/^#//' /etc/greetd/regreet.toml
fi

# Enable the Greetd service
echo "Enabling the Greetd service..."
systemctl -f enable greetd.service

# Remove the repo
echo "Removing the EOS Community Sway repo..."
rm -rf ../sway

echo "Installation complete."

