#!/bin/bash -ex
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

VAGRANT="/vagrant/rpi_chroot"

# Working directory
ROOT="/var/tmp/rpi_chroot"

# Directory that will be chrooted
MOUNT_ROOT="$ROOT/mnt"

IMAGE_SIZE=16

# Cleanup after each run.
function cleanup {
  rm -f "$ROOT/*.img"
  umount /dev/loop0 || true
  umount /dev/loop1 || true
  umount "$MOUNT_ROOT" || true
  losetup -d /dev/loop0 /dev/loop1
}
trap cleanup EXIT  

# Install dependencies if they are not already installed
apt-get update
apt-get install ruby qemu qemu-user-static binfmt-support unzip -y

# Save bandwidth, only download Raspbian if it is not already
mkdir -p "$MOUNT_ROOT"
cd "$ROOT"
if [[ ! -f "$VAGRANT/raspbian-latest.img.zip" ]]
then
  wget https://downloads.raspberrypi.org/raspbian_latest -O "$VAGRANT/raspbian-latest.img.zip"
fi
unzip -o "$VAGRANT/raspbian-latest.img.zip"

# Get the starting block of the root partition in the raspbian image
START_BLOCK=$(fdisk -lu 2016-03-18-raspbian-jessie.img | tail -1 | awk '{print $2}')

# resize image
"$DIR/resize_image.py" "$ROOT"/2016-03-18-raspbian-jessie.img $IMAGE_SIZE

# Loopback mount both the whole of the image and it's root partition
WHOLE_LOOP=$(losetup -f --show 2016-03-18-raspbian-jessie.img)
ROOT_LOOP=$(losetup -f --show -o $((START_BLOCK * 512)) 2016-03-18-raspbian-jessie.img)

# Alter the root partition to take up the new space
parted --script "$WHOLE_LOOP" rm 2
parted --script "$WHOLE_LOOP" mkpart primary 67.1 $((IMAGE_SIZE * 1024))

# Expand the filesystem in the root partition
e2fsck -f "$ROOT_LOOP"
resize2fs "$ROOT_LOOP"

# Delete the loopback devices as they are no longer needed
losetup -d /dev/loop0 /dev/loop1

# Mount the root partition of the image
mount 2016-03-18-raspbian-jessie.img -o loop,offset=$((START_BLOCK * 512)),rw "$MOUNT_ROOT"

# Create the script that will alter the image somehow
echo "#!/bin/bash -ex
export HOME=/root

apt-get -y install sudo openssh-server pwgen
rm -f /etc/ssh/ssh_host_ecdsa_key /etc/ssh/ssh_host_rsa_key
ssh-keygen -q -N '' -t dsa -f /etc/ssh/ssh_host_ecdsa_key
ssh-keygen -q -N '' -t rsa -f /etc/ssh/ssh_host_rsa_key
sed -i 's/#UsePrivilegeSeparation.*/UsePrivilegeSeparation no/g' /etc/ssh/sshd_config
sed -i 's/UsePAM.*/UsePAM no/g' /etc/ssh/sshd_config

useradd --create-home -s /bin/bash vagrant

mkdir -p /home/vagrant/.ssh

echo 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key' > /home/vagrant/.ssh/authorized_keys

chown -R vagrant: /home/vagrant/.ssh
echo -n 'vagrant:vagrant' | chpasswd

mkdir -p /etc/sudoers.d
install -b -m 0440 /dev/null /etc/sudoers.d/vagrant
echo 'vagrant ALL=NOPASSWD: ALL' >> /etc/sudoers.d/vagrant

sshd -D -p 55522
" > "$MOUNT_ROOT/tmp/setup.sh"
chmod 755 "$MOUNT_ROOT/tmp/setup.sh"

echo > "$MOUNT_ROOT/etc/ld.so.preload"
cp /usr/bin/qemu-arm-static "$MOUNT_ROOT/usr/bin"

mount --bind /dev "$MOUNT_ROOT/dev/"
mount --bind /sys "$MOUNT_ROOT/sys/"
mount --bind /proc "$MOUNT_ROOT/proc/"
mount --bind /dev/pts "$MOUNT_ROOT/dev/pts"

# Run the script in the chroot
chroot "$MOUNT_ROOT" tmp/setup.sh

