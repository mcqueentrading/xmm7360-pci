# xmm7360-pci

Driver for the **Fibocom L850-GL / Intel XMM7360** LTE modem (PCI ID `8086:7360`),
with a C userspace RPC tool and full DKMS packaging for Arch Linux.

Confirmed working with this C port on the **Lenovo ThinkPad T14s (Intel)**
(Fibocom L850 / XMM7360) under Arch Linux, kernels 6.18-lts and 7.x.
See [DEVICES.md](DEVICES.md) for the full list of tested devices.

> ⚠️ _In development. No support provided. May not work, may crash your
> computer, may singe your jaffles._

![CI](https://github.com/xmm7360/xmm7360-pci/workflows/CI/badge.svg)

---

## How it works

The modem sits on the PCIe bus and exposes two interfaces:

| Interface | Purpose |
|---|---|
| `/dev/xmm0/rpc` | RPC channel — modem initialisation, attach, signal |
| `wwan0` | Network interface — IP data via kernel MUX layer |
| `ttyXMM1`, `ttyXMM2` | AT command ports — used by ModemManager |

`open_xdatachannel` talks to the RPC channel to wake the modem, unlock
FCC, enable RF, open the SIM subsystem, and enable signal reporting.
ModemManager then uses the AT ports for everything else (registration,
signal strength, connection management), and NetworkManager handles the
IP connection.

---

## Installation (Arch Linux — recommended)

```bash
# Clone the repo
git clone https://github.com/Andron338/xmm7360-pci.git
cd xmm7360-pci

# Build and install via pacman (handles DKMS, udev, systemd)
makepkg -si

# Reboot — iosm is blacklisted, xmm7360 loads automatically
reboot
```

After reboot the modem initialises on its own:

1. `xmm7360` module loads and creates `wwan0`, `ttyXMM1`, `ttyXMM2`
2. udev triggers `xmm7360-init.service`
3. `open_xdatachannel --init-only` wakes the modem over the RPC channel
4. ModemManager detects the SIM via the Fibocom plugin
5. Connect using NetworkManager GUI or `nmcli`

On every kernel update DKMS rebuilds the module automatically — no
manual steps needed.

---

## Manual installation (other distros)

### Dependencies

- `gcc`, `make`, `linux-headers`
- `libnm` (NetworkManager GLib library)
- `openssl`
- `libuuid`

### Build

```bash
# Build the kernel module
make -C kernel
sudo make -C kernel load   # load without installing

# Build the RPC tool
make -C tool
```

### Install

```bash
# Install kernel module via DKMS
sudo cp xmm7360.c /usr/src/xmm7360-1.0.0/
sudo cp Makefile.dkms /usr/src/xmm7360-1.0.0/Makefile
sudo cp dkms.conf /usr/src/xmm7360-1.0.0/
sudo dkms install xmm7360/1.0.0

# Install RPC tool
sudo install -m755 rpc/open_xdatachannel /usr/local/bin/

# Install udev rule and systemd service
sudo cp 80-xmm7360.rules /usr/lib/udev/rules.d/
sudo cp xmm7360-init.service /usr/lib/systemd/system/
sudo cp xmm7360-modprobe.conf /usr/lib/modprobe.d/xmm7360.conf

# Enable init service
sudo systemctl enable xmm7360-init.service

# Reboot
sudo reboot
```

---

## Usage

### Automatic (after install)

The `xmm7360-init.service` runs automatically on boot. Connect via
NetworkManager GUI or:

```bash
# Create a connection (first time only)
nmcli connection add type gsm ifname '*' apn your.apn.here con-name lte

# Connect
nmcli connection up lte
```

### Manual

```bash
# Wake modem only (let ModemManager handle the rest)
sudo open_xdatachannel --init-only

# Full manual setup (bypasses ModemManager — use with iosm module)
sudo open_xdatachannel --apn your.apn.here
```

### SIM PIN

If your SIM has a PIN enabled, unlock it via the AT port before or
after `--init-only`:

```bash
echo 'AT+CPIN="0000"' | sudo tee /dev/ttyXMM1
```

Replace `0000` with your PIN.

---

## Signal strength

Signal reporting requires the Fibocom ModemManager plugin. Check it is
being used:

```bash
mmcli -m 0 | grep plugin
# should show: plugin: fibocom
```

Then enable polling:

```bash
mmcli -m 0 --signal-setup=5
mmcli -m 0 --signal-get
```

If the plugin shows `generic` instead of `fibocom`, the udev rule in
`80-xmm7360.rules` needs to be reloaded:

```bash
sudo udevadm control --reload-rules
sudo systemctl restart ModemManager
```

---

## Uninstall

```bash
sudo pacman -R xmm7360-dkms   # Arch
# or
sudo dkms remove xmm7360/1.0.0 --all
sudo rm /usr/local/bin/open_xdatachannel
sudo rm /usr/lib/udev/rules.d/80-xmm7360.rules
sudo rm /usr/lib/systemd/system/xmm7360-init.service
sudo rm /usr/lib/modprobe.d/xmm7360.conf
```

---

## Power management

Suspend/resume is handled in-kernel. On resume the module emits a uevent
that re-runs `xmm7360-init.service` automatically, so the modem returns
without any manual step or systemd sleep hook.

If ModemManager ever drops the modem after a disconnect, the
`xmm7360-rescan.service` re-scans it automatically; `sudo xmm7360-reset`
forces a full module reload as a last resort.

On systems where S3/S4 resume races ModemManager or NetworkManager, see
[`docs/S4_RESUME_DEBUG.md`](docs/S4_RESUME_DEBUG.md). This repo includes a
watchdog wrapper that skips suspend/hibernate windows and an installer that
disables the conflicting post-resume unit used by older local setups:

```bash
bash scripts/install-s4-resume-fixes.sh
```

---

## Project layout

```
xmm7360-pci/
├── PKGBUILD / .SRCINFO / xmm7360-dkms.install   Arch packaging (flat for AUR)
├── kernel/    xmm7360.c, Makefile, Makefile.dkms, dkms.conf
├── tool/      open_xdatachannel.c, xmm_*.{c,h}, Makefile, man page
├── tests/     userspace unit tests + KUnit module
├── systemd/   init / signal / rescan / recovery services
├── udev/      80-xmm7360.rules
├── conf/      xmm7360-modprobe.conf (blacklists iosm)
├── scripts/   xmm7360-reset (manual recovery)
├── docs/      INSTALLING.md, DEVICES.md
└── .github/workflows/   CI/CD (see below)
```

### CI/CD workflows

| Workflow | Purpose |
|---|---|
| `tests.yaml` | unit tests (gcc/clang), ASan+UBSan, valgrind, KUnit build |
| `rpc-tool.yml` | tool build + tests + cppcheck |
| `kernel-module-ci.yaml` | build `.ko` against 5 kernels |
| `makepkg.yaml` | build + lint package, DKMS-build per kernel |
| `aur-publish.yaml` | auto-publish to the AUR on packaging changes |
| `80-xmm7360.rules` | udev rules |
| `xmm7360-modprobe.conf` | Blacklists iosm |
| `xmm7360-dkms.install` | Arch post-install hooks |
| `rpc/` | Userspace RPC tool source |

---

## See also

- `man 8 open_xdatachannel`
- [ModemManager](https://www.freedesktop.org/wiki/Software/ModemManager/)
- [NetworkManager](https://networkmanager.dev/)
- [INSTALLING.md](INSTALLING.md)
- [DEVICES.md](DEVICES.md)
