# Optional containerized build environment for tc32.
#   make docker      (or: docker build -t tc32-build docker && docker run ...)
# Native builds work too: scripts/host-tools.sh builds flex/bison/m4/mtools/
# mksquashfs locally if the host lacks them and fetches the musl toolchain.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential bc bison flex cpio xz-utils bzip2 curl ca-certificates \
      perl python3 mtools dosfstools e2fsprogs fdisk zlib1g-dev liblzma-dev \
      squashfs-tools qemu-system-x86 file \
    && rm -rf /var/lib/apt/lists/*
ENV HOME=/tmp
