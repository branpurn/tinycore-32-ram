# tc32 -- Tiny Core-derived single-floppy Linux for i486 / 32 MB
# Usage: make            build out/tc32.img
#        make test       boot it in QEMU (TCG, -cpu 486, -m 32) and assert basics
#        make sweep      test + headroom runs at 24/16/12/10/8 MB
#        make run        interactive QEMU (VGA window)    make run-serial (terminal)
.POSIX:
SHELL = /bin/sh
KERNEL_FRAGMENTS ?= base hdd tce modules
export KERNEL_FRAGMENTS

all: image

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

test: image
	tests/run.sh 32

sweep: image
	TC32_SWEEP=1 tests/run.sh 32

run:
	qemu-system-i386 -accel tcg -M isapc -cpu 486 -m 32 -drive if=floppy,format=raw,file=out/tc32.img -boot a

run-serial:
	qemu-system-i386 -accel tcg -M isapc -cpu 486 -m 32 -drive if=floppy,format=raw,file=out/tc32.img -boot a -nographic

scan:
	scripts/scan-public.sh

docker:
	docker build -t tc32-build docker
	docker run --rm -v "$$PWD":/src -w /src -u "$$(id -u):$$(id -g)" tc32-build make image

clean:
	rm -rf out build/kernel-obj build/rootfs-stage build/floppy-stage build/test-disk build/core.cpio build/rootfs.list

distclean:
	rm -rf out build

.PHONY: all tools kernel busybox rootfs check image test sweep run run-serial scan docker clean distclean
