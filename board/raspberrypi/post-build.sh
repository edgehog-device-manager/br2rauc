#!/bin/sh

set -u
set -e

RAUC_COMPATIBLE="${2:-br2rauc-rpi4-64}"

# Pass VERSION as an environment variable (eg: export from a top-level Makefile)
# If VERSION is unset, fallback to the Buildroot version
RAUC_VERSION=${VERSION:-${BR2_VERSION_FULL}}

# Add a console on tty1
if [ -e ${TARGET_DIR}/etc/inittab ]; then
	grep -qE '^tty1::' ${TARGET_DIR}/etc/inittab ||
		sed -i '/GENERIC_SERIAL/a\
tty1::respawn:/sbin/getty -L  tty1 0 vt100 # HDMI console' ${TARGET_DIR}/etc/inittab
# systemd doesn't use /etc/inittab, enable getty.tty1.service instead
elif [ -d ${TARGET_DIR}/etc/systemd ]; then
	mkdir -p "${TARGET_DIR}/etc/systemd/system/getty.target.wants"
	ln -sf /lib/systemd/system/getty@.service \
		"${TARGET_DIR}/etc/systemd/system/getty.target.wants/getty@tty1.service"
fi

# Mount persistent data partitions
if [ -e ${TARGET_DIR}/etc/fstab ]; then
	# For configuration data
	# WARNING: data=journal is safest, but potentially slow!
	grep -qE 'LABEL=Data' ${TARGET_DIR}/etc/fstab ||
		echo "LABEL=Data /var/lib ext4 defaults,data=journal,noatime 0 0" >>${TARGET_DIR}/etc/fstab

	# For bulk data (eg: firmware updates)
	grep -qE 'LABEL=OTA' ${TARGET_DIR}/etc/fstab ||
		echo "LABEL=OTA /var/tmp ext4 defaults,noatime 0 0" >>${TARGET_DIR}/etc/fstab
fi

# Copy custom cmdline.txt file
install -D -m 0644 ${BR2_EXTERNAL_BR2RAUC_PATH}/board/raspberrypi/cmdline.txt ${BINARIES_DIR}/custom/cmdline.txt

# Copy RAUC certificate
if [ -e ${BR2_EXTERNAL_BR2RAUC_PATH}/openssl-ca/dev/ca.cert.pem ]; then
	install -D -m 0644 ${BR2_EXTERNAL_BR2RAUC_PATH}/openssl-ca/dev/ca.cert.pem ${TARGET_DIR}/etc/rauc/keyring.pem
else
	echo "RAUC CA certificate not found!"
	echo "...did you run the openssl-ca.sh script?"
	exit 1
fi

# Update RAUC compatible string
sed -i "/compatible/s/=.*\$/=${RAUC_COMPATIBLE}/" ${TARGET_DIR}/etc/rauc/system.conf

# Create rauc version file
echo "${RAUC_VERSION}" >${TARGET_DIR}/etc/rauc/version

# Customize login prompt with login hints
cat <<-EOF >>${TARGET_DIR}/etc/issue

	Default root:password
	With great power comes great responsibility!

	eth0: \4{eth0}

EOF
