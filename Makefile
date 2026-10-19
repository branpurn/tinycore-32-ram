# tc32 -- Tiny Core-derived single-floppy Linux for i486 / 32 MB
# Usage: make            build out/tc32.img (rescue) + out/installer.img
#        make test       boot the rescue floppy in QEMU (TCG, -cpu 486, -m 32) and assert basics
#        make sweep      test + headroom runs at 24/16/12/10/8 MB
#        make installer  build out/installer.img (install-to-disk onto the IDE disk)
#        make test-install  install onto a 2 GB IDE disk in QEMU, boot it without
#                        the floppy, XMODEM transfer over the console + checksum
#        make run        interactive QEMU (VGA window)    make run-serial (terminal)
#        make gfx        X second stage: out/gfx/*.tcz (docs/GRAPHICS.md)
#        make gfx-755c   755C graphics kernel out/gfx/755c/vmlinuz.x + driver .tcz
#        make test-gfx   X in QEMU (vesafb test kernel + 755C kernel), screendumps
#        make gfx-floppies  1.44 MB transfer floppies with the second stage
.POSIX:
SHELL = /bin/sh
KERNEL_FRAGMENTS ?= base hdd tce modules
export KERNEL_FRAGMENTS

all: image installer

tools:
	scripts/host-tools.sh

kernel: tools
	scripts/build-kernel.sh $(KERNEL_FRAGMENTS)

busybox: tools
	scripts/build-busybox.sh

rootfs: kernel busybox
	scripts/mkrootfs.sh

check: busybox
	scripts/check-i486.sh out/busybox

image: rootfs check
	scripts/mkfloppy.sh
	@scripts/sizes.sh

extlinux: tools
	scripts/build-extlinux.sh

installer: image extlinux
	scripts/check-i486.sh out/extlinux
	scripts/mkinstaller.sh
	@scripts/sizes.sh

test: image
	tests/run.sh 32

sweep: image
	TC32_SWEEP=1 tests/run.sh 32

test-install: installer
	tests/run-install.sh

run:
	qemu-system-i386 -accel tcg -M isapc -cpu 486 -m 32 -drive if=floppy,format=raw,file=out/tc32.img -boot a

run-serial:
	qemu-system-i386 -accel tcg -M isapc -cpu 486 -m 32 -drive if=floppy,format=raw,file=out/tc32.img -boot a -nographic

# Interactive installer with a scratch 2 GB disk (out/hd-2g.img, created if missing).
run-installer:
	[ -f out/hd-2g.img ] || truncate -s 2000000000 out/hd-2g.img
	qemu-system-i386 -accel tcg -M isapc -cpu 486 -m 32 -drive if=floppy,format=raw,file=out/installer.img -drive if=ide,format=raw,file=out/hd-2g.img -boot a -nographic

run-disk:
	qemu-system-i386 -accel tcg -M isapc -cpu 486 -m 32 -drive if=ide,format=raw,file=out/hd-2g.img -boot c -nographic

gfx: tools
	scripts/build-gfx.sh
	scripts/mktcz-gfx.sh

gfx-kernel: tools
	scripts/build-gfx-kernel.sh test

gfx-755c: tools
	scripts/build-gfx-kernel.sh 755c

test-gfx: image gfx gfx-kernel gfx-755c
	tests/mk-gfx-disk.sh
	python3 tests/gfx.py --mode vesa
	tests/mk-gfx-disk.sh --deliver
	python3 tests/gfx.py --mode wd

gfx-floppies: gfx gfx-755c
	tools/mk-gfx-floppies.sh

scan:
	scripts/scan-public.sh

docker:
	docker build -t tc32-build docker
	docker run --rm -v "$$PWD":/src -w /src -u "$$(id -u):$$(id -g)" tc32-build make image

clean:
	rm -rf out build/kernel-obj build/kernel-gfxtest build/gfx/tcz build/gfx/test-disk build/rootfs-stage build/floppy-stage build/test-disk build/core.cpio build/rootfs.list build/installer-stage build/installer-floppy build/install.cpio build/install.list

distclean:
	rm -rf out build

.PHONY: all tools kernel busybox rootfs check image extlinux installer test sweep test-install run run-serial run-installer run-disk gfx gfx-kernel gfx-755c test-gfx gfx-floppies scan docker clean distclean
