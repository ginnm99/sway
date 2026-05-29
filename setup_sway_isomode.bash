#!/usr/bin/env bash
username="$1"

# Clone the repo
echo "Cloning the EOS Community Sway repo..."
git clone https://github.com/EndeavourOS-Community-Editions/sway.git

# Check if nvidia-inst is installed
# If it is, do the Nvidia stuff
if pacman -Qq | grep -Eq '^nvidia(|-dkms|-open|-open-dkms)$'; then
    echo "Adding the --unsupported-gpu flag to the sway call in greetd.conf..."
    sed -i 's|sway -c|sway --unsupported-gpu -c|' sway/etc/greetd/greetd.conf
    echo "Adding a custom desktop file for Nvidia sessions..."
    mkdir -p /usr/share/wayland-sessions
    cat <<EOF > /usr/share/wayland-sessions/sway-nvidia.desktop
[Desktop Entry]
Name=Sway-Nvidia
Comment=Sway with Nvidia
Exec=sway --unsupported-gpu
Type=Application
EOF
    echo "Adding dracut config for early module loading..."
    cat <<EOF > /etc/dracut.conf.d/nvidia-modules.conf
force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
EOF
    echo "Regenerating initrds..."
    reinstall-kernels || dracut-rebuild
fi

# Install the custom package list
echo "Installing needed packages..."
pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout $(< ./sway/packages-repository.txt)

# Deploy user configs
echo "Deploying user configs..."
rsync -a sway/.config "/home/${username}/"
rsync -a sway/home_config/ "/home/${username}/"

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

# If autologin has been configured, update greetd.conf accordingly
if getent group autologin | grep -qw "${username}"; then
    echo "autologin group detected, configuring autologin in greetd.conf..."

    sway_command="sway"

    # Add --unsupported-gpu when nvidia-inst is installed
    if pacman -Qq | grep -Eq '^nvidia(|-dkms|-open|-open-dkms)$'; then
        echo "nvidia-inst detected, enabling --unsupported-gpu..."
        sway_command="sway --unsupported-gpu"
    fi

    cat <<EOF >> sway/etc/greetd/greetd.conf

[initial_session]
command = "${sway_command}"
user = "${username}"
EOF
fi

# Deploy system configs
echo "Deploying system configs..."
rsync -a --chown=root:root sway/etc/ /etc/

# Check if the script is running in a virtual machine
if systemd-detect-virt | grep -vq "none"; then
  echo "Virtual machine detected; enabling WLR_RENDERER_ALLOW_SOFTWARE variable in ReGreet config..."
  # Uncomment WLR_RENDERER_ALLOW_SOFTWARE variable in ReGreet config
  sed -i '/^#WLR_RENDERER_ALLOW_SOFTWARE/s/^#//' /etc/greetd/regreet.toml
fi

# Remove the repo
echo "Removing the EOS Community Sway repo..."
rm -rf sway

# Enable the Greetd service
echo "Enabling the Greetd service..."
systemctl enable greetd.service

echo "Installation complete."
