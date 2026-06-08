# S4/S3 Resume Notes

This fork carries a local resume stability fix for systems where the XMM7360
module races ModemManager, NetworkManager, or watchdog helpers during sleep.

Observed failure pattern:

- suspend enters cleanly with `PM: suspend entry (deep)`;
- previous attempts could hard-freeze or return with the modem stack wedged;
- `xmm7360-resume.service` could be queued while the system-sleep hook was
  trying to stop ModemManager, causing a systemd transaction conflict;
- a stale watchdog connection name could repeatedly try to activate a
  non-existent GSM profile.

The mitigation keeps one owner for sleep/resume:

- `/usr/lib/systemd/system-sleep/xmm7360` quiesces the modem before sleep and
  restores helpers after resume;
- `xmm7360-resume.service` should not be enabled in sleep targets on this
  setup because it can race the pre-sleep hook;
- `xmm7360-watchdog` skips itself while suspend/hibernate jobs are active;
- the watchdog GSM profile defaults to `lebara` but can be overridden with
  `XMM7360_CONN_NAME`.

Install the local fix package:

```bash
bash scripts/install-s4-resume-fixes.sh
```

Useful diagnostics:

```bash
journalctl -b -1 --no-pager | rg -i 'suspend|hibernate|resume|PM:|xmm7360|ModemManager|NetworkManager|wlp3s0|watchdog'
journalctl -b --no-pager | rg -i 'xmm7360|ModemManager|NetworkManager|wlp3s0|watchdog'
nmcli device status
nmcli -t -f NAME,TYPE,DEVICE connection show --active
```
