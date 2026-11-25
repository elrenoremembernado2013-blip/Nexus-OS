#!/bin/sh
# Ephemeral casper-bottom initramfs hook injected ONLY into test-initrd.img in RAM
# during QEMU validation. Never packaged into released NEXUS ISO images.

PREREQ=""
prereqs() {
  echo "$PREREQ"
}

case "${1:-}" in
  prereqs)
    prereqs
    exit 0
    ;;
esac

rootmnt="${rootmnt:-/root}"
[ -d "$rootmnt/etc" ] || exit 0

mkdir -p "$rootmnt/usr/local/libexec/nexus-test" "$rootmnt/etc/systemd/system/multi-user.target.wants"
cp -f /nexus-test/guest-mem-probe.sh "$rootmnt/usr/local/libexec/nexus-test/guest-mem-probe.sh"
cp -f /nexus-test/test-zram-pressure.sh "$rootmnt/usr/local/libexec/nexus-test/test-zram-pressure.sh"
cp -f /nexus-test/nexus-guest-test.py "$rootmnt/usr/local/libexec/nexus-test/nexus-guest-test.py"
chmod 0755 "$rootmnt/usr/local/libexec/nexus-test/"*

cat > "$rootmnt/etc/systemd/system/nexus-test-agent.service" <<'UNIT'
[Unit]
Description=NEXUS Ephemeral QEMU Test Telemetry Agent (Test Channel Only)
ConditionPathExists=/dev/virtio-ports/org.nexus.test.0
After=systemd-user-sessions.service lightdm.service NetworkManager.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/libexec/nexus-test/nexus-guest-test.py
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

ln -sf ../nexus-test-agent.service "$rootmnt/etc/systemd/system/multi-user.target.wants/nexus-test-agent.service"
exit 0
