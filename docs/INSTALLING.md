# Installing

This is the **C port** of xmm7360-pci: a C kernel module (`xmm7360.c`) plus a
C userspace RPC tool (`open_xdatachannel`), packaged for Arch Linux with DKMS,
udev rules and systemd services. There is no Python, no `pyroute2`, no
`lte.sh`, and no `xmm7360.ini` — those belonged to the original Python driver.

Confirmed working on the **Lenovo ThinkPad T14s (Intel)** (Fibocom L850 /
XMM7360) under Arch Linux, kernels 6.18-lts and 7.x.

---

## Recommended: Arch Linux package (DKMS)

This builds the kernel module via DKMS (so it rebuilds automatically on kernel
updates) and installs the udev rules and systemd services that bring the modem
up at boot and keep it healthy.

```bash
git clone https://github.com/Andron338/xmm7360-pci.git
cd xmm7360-pci
makepkg -si
```

The package:

- installs the module source to `/usr/src` and builds it with DKMS
- blacklists the in-tree `iosm` driver (so `xmm7360` binds instead)
- installs `/etc/xmm7360.conf` (set `XMM_APN` for your carrier)
- enables the boot + recovery services (see **Services** below)

After install, **reboot** so `xmm7360` loads in place of `iosm`. On the next
boot the modem initialises automatically and appears in ModemManager /
NetworkManager — connect to it like any other mobile-broadband connection.

Set your APN first if it isn't `internet`:

```bash
sudoedit /etc/xmm7360.conf      # XMM_APN=your.carrier.apn
```

---

## Services

| Service                   | When            | Job                                                        |
| ------------------------- | --------------- | ---------------------------------------------------------- |
| `xmm7360-init.service`    | boot, before MM | RPC wake (SIM open, RF on) so ModemManager can detect it   |
| `xmm7360-signal.service`  | boot, after MM  | enable periodic signal-quality reporting                   |
| `xmm7360-rescan.service`  | boot (polls)    | re-scan if ModemManager drops the modem after a disconnect |
| `xmm7360-recovery.service`| udev-triggered  | reload the module if the kernel reports an unrecoverable failure |

A manual escape hatch is also installed:

```bash
sudo xmm7360-reset      # force a full module reload + MM rescan
```

---

## Verifying

```bash
# kernel side
sudo dmesg | grep xmm7360            # expect: "modem is ready"
ls /dev/ttyXMM* /dev/xmm0/*          # device nodes present

# ModemManager side
mmcli -L                             # modem listed
mmcli -m 0 | grep -E 'state|signal|operator'   # registered, signal, carrier
```

Then connect via NetworkManager (`nmcli` or the GUI) using a mobile-broadband
(GSM) connection with your APN.

---

## Manual build (no package)

For development or non-Arch systems you can build the pieces directly.

Kernel module:

```bash
make -C kernel              # builds xmm7360.ko against the running kernel
sudo make -C kernel load    # rmmod iosm/xmm7360, then insmod xmm7360.ko
```

Userspace tool:

```bash
make -C tool                  # builds open_xdatachannel (needs openssl, libuuid)
sudo ./tool/open_xdatachannel --init-only
```

`--init-only` performs the RPC handshake (SIM open, RF on, signal reporting)
and exits, letting ModemManager manage the connection over the AT ports. Full
data-channel mode (`--apn internet`, raw IP on `wwan0`) exists for use with the
`iosm` module but is **not** the recommended path here — PPP via ModemManager
is the supported configuration.

---

## Suspend / resume

Handled in-kernel. On resume the module emits a uevent that re-runs
initialisation automatically. No manual step and no systemd sleep hook are
required (earlier revisions needed one; that is no longer the case).

---

## Secure Boot signing

If Secure Boot is enabled, unsigned modules fail to load with
`Operation not permitted`. DKMS can sign the module for you.

Generate a Machine Owner Key and enroll it:

```bash
sudo pacman -S --needed openssl mokutil

openssl req -new -x509 -newkey rsa:2048 \
  -keyout /root/mok.priv -outform DER -out /root/mok.der \
  -nodes -days 36500 -subj "/CN=xmm7360 Module Signing Key"

sudo mokutil --import /root/mok.der
# reboot — the firmware prompts you to enroll the key
```

Configure DKMS to sign on build by creating `/etc/dkms/sign_helper.sh`:

```bash
#!/bin/sh
/usr/lib/modules/"$1"/build/scripts/sign-file sha512 /root/mok.priv /root/mok.der "$2"
```

```bash
sudo chmod +x /etc/dkms/sign_helper.sh
```

and pointing DKMS at it in `/etc/dkms/framework.conf`:

```
sign_tool="/etc/dkms/sign_helper.sh"
```

DKMS will then sign `xmm7360.ko` automatically on every (re)build.

---

## Troubleshooting

- **Modem absent after a disconnect/reconnect** — the `xmm7360-rescan` service
  should re-scan within ~10 s. Force it manually with `sudo mmcli -S` (wait a
  few seconds, then `mmcli -L`), or `sudo xmm7360-reset` for a full reload.
- **Package seems updated but live rescan behavior is still too aggressive** —
  check whether an older manual unit is shadowing the packaged one:
  `systemctl cat xmm7360-rescan.service`. If the loaded file comes from
  `/etc/systemd/system/xmm7360-rescan.service` instead of
  `/usr/lib/systemd/system/xmm7360-rescan.service`, remove the stale `/etc`
  copy and reload systemd so the packaged unit wins.
- **`iosm` keeps grabbing the device** — confirm the blacklist landed:
  `cat /usr/lib/modprobe.d/xmm7360.conf` and reboot.
- **No signal / FCC-locked** — some units ship FCC-locked. Check
  `mmcli -m 0` for a failed/locked state; if so, an FCC-unlock script may be
  required (ModemManager ships several under
  `/usr/share/ModemManager/fcc-unlock.available.d/`).
- **Other hardware** — if you find a non-USB XMM7360 modem that needs different
  AT setup, see https://github.com/juhovh/xmm7360_usb for the USB variant.
