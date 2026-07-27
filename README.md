# initramfs-tools-halium

Hooks and configuration to build a Halium initramfs

## RMX1901 safety fork

This local fork replaces the legacy userdata path with a fail-closed policy:

- accept only an unambiguous `ext4` or `f2fs` result from `blkid`;
- probe ext4 with `ro,noload` and f2fs with `ro` before any writable mount;
- require an RMX1901 rootfs payload while userdata is still read-only for the
  legacy userdata-image layout;
- allow payload-free userdata only when the kernel command line contains one
  `systempart=/dev/disk/by-partlabel/system`, that alias resolves exactly to the
  RMX1901 early-udev system block device `/dev/sda11`, and the target is a block
  device;
- reject the legacy `/dev/block/by-name/system` alias because the pinned initrd
  udev rules create `/dev/disk/by-partlabel/*`, not `/dev/block/by-name/*`;
- retain the canonical system device, re-resolve and re-check the alias
  immediately before mounting, and mount the canonical device rather than the
  mutable alias;
- never run filesystem repair, resize, or format utilities at boot;
- attempt a read-only rescue mount and enter Halium panic if writable mounting fails.

For both layouts, userdata must first identify unambiguously as ext4 or f2fs,
mount read-only with the filesystem-specific safe options, and unmount cleanly
before the first read-write attempt. Other, malformed, duplicate, dynamic, or
non-canonical `systempart` values fail closed before userdata is mounted.
The parser disables pathname expansion while reading command-line words, and a
failed validated-system mount enters Halium panic instead of continuing with a
missing root filesystem.

For early userspace diagnosis, the fork also contains a dormant RMX1901 bridge
that is enabled only by exactly one literal `rmx1901.debug_rndis=1` kernel
command-line token. After a successful mountroot it configures the same RNDIS
gadget proven by the panic handler, runtime-masks usb-moded for that boot, and
starts an independently chrooted, public-key-only SSH server after `/dev` and
`/proc` cross the run-init handoff. Its host key, DHCP state, service mask, and
logs live only in `/run`; it does not create a userdata marker. Diagnostic
setup failure is logged but never aborts the normal boot path.

Run the behavior fixtures with:

```sh
/bin/sh tests/test-safe-userdata.sh
/bin/sh tests/test-debug-rndis.sh
/bin/sh tests/test-derive-initrd.sh
```

Derive the audited arm64 artifact from the pinned official base asset:

```sh
/bin/sh tools/derive-initrd.sh /absolute/path/to/pinned-initrd.img-touch-arm64 out/final
/bin/sh tools/audit-initrd.sh \
  /absolute/path/to/pinned-initrd.img-touch-arm64 \
  out/final/initrd.img-touch-arm64-rmx1901-safe \
  out/final/initrd.before.manifest \
  out/final/initrd.after.manifest
```

The builder rejects a base whose SHA-256 is not
`0bbac4577f3567aec935c958216de5d30c7355452ca56248d6728f4f2634bdb6`.
It does not stage, embed, or flash its output.

## Build an initramfs image

Building your own initramfs image wtih the tools in this repository is simple.

Requirements:

* Any OS with `debootstrap`
* `sudo` rights on the machine, to create the chroot

1. Clone this repository into your home folder
1. Install the prerequisites: `sudo apt install debootstrap qemu-user-static binfmt-support dpkg-dev`
1. `cd` into the repository
1. Run `sudo ./build-initrd.sh -a [ARCH]`

The initrd will be saved as `./out/initrd.img-touch-$ARCH` by default.

## Command-line / Environment options

`-a|--arch / ARCH=` The architecture to build an initrd for. Can be any architecture supported by Debian. Default `armhf`.

`-m|--mirror / MIRROR=` Mirror to pass to debootstrap. Default `http://deb.debian.org/debian`.

`RELEASE=` Debian release to use for building this initrd. Default `stable`.

`ROOT=` Location to place build chroot. Default `./build/$ARCH`.

`OUT=` Location to copy finished initrd to. Default `./out`.

`INCHROOTPACKAGES=` Packages to install in the chroot. These are installed in addition to the `minbase` packages specified by debootstrap. Default `initramfs-tools dctrl-tools e2fsprogs libc6-dev zlib1g-dev libssl-dev busybox-static`

## FAQ

*I'm getting a strange error when I try to build*

Try deleting your chroots (normally in the `build/` directory) and building again.

*I can't delete my chroots! They say that something is busy!*

Just run `umount build/*/*` to unmount anything that's mounted. If that doesn't work, reboot your computer. The mounts should be gone after that. Then you can delete the chroots.
