#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "== Backing up current watchdog if present =="
if [ -e /usr/local/bin/xmm7360-watchdog.sh ]; then
  doas cp /usr/local/bin/xmm7360-watchdog.sh "/usr/local/bin/xmm7360-watchdog.sh.before-s4-fix-${STAMP}"
fi

echo "== Installing watchdog script =="
doas cp "${REPO_DIR}/scripts/xmm7360-watchdog" /usr/local/bin/xmm7360-watchdog.sh
doas chmod 755 /usr/local/bin/xmm7360-watchdog.sh

echo "== Installing watchdog systemd units =="
doas cp "${REPO_DIR}/systemd/xmm7360-watchdog.service" /etc/systemd/system/xmm7360-watchdog.service
doas cp "${REPO_DIR}/systemd/xmm7360-watchdog.timer" /etc/systemd/system/xmm7360-watchdog.timer

echo "== Disabling conflicting post-resume unit if present =="
doas systemctl disable xmm7360-resume.service 2>/dev/null || true

echo "== Reloading systemd and enabling watchdog timer =="
doas systemctl daemon-reload
doas systemctl enable --now xmm7360-watchdog.timer

echo "== Current state =="
systemctl is-enabled xmm7360-resume.service 2>/dev/null || true
systemctl list-timers --all | grep -F xmm7360-watchdog || true
nmcli -t -f NAME,TYPE,DEVICE connection show --active | grep -E 'gsm|ttyXMM|lebara' || true

echo "Done. Re-test S4/S3 after this."
