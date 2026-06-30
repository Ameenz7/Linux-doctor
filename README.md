# linux-doctor

A Bash-based Linux diagnostic CLI with a menu interface, distro detection, safe problem reporting, and suggested fixes.

## What is included

- first-run welcome screen with a large centered `linux-doctor` banner
- interactive menu mode
- basic cross-distro health checks for:
  - system overview
  - disk space and inode pressure
  - memory and swap
  - CPU/load
  - failed systemd services
  - critical logs
  - network basics
  - package/update status
- safe suggestions only: no fixes are executed automatically

## Run it

```bash
cd linux-doctor
chmod +x linux-doctor.sh
./linux-doctor.sh
```

## Direct commands

```bash
./linux-doctor.sh --full
./linux-doctor.sh --disk
./linux-doctor.sh --memory
./linux-doctor.sh --cpu
./linux-doctor.sh --services
./linux-doctor.sh --logs
./linux-doctor.sh --network
./linux-doctor.sh --updates
```

## Change the welcome title style

Edit the banner lines in:

- `lib/common.sh` → `print_banner()`

That is the place to make the startup text look even closer to your reference image.
