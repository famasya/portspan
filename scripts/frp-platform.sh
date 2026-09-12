#!/bin/sh

# Resolve uname names to the artifact and Go target names used by frp.
# The caller must inspect FRP_RELEASE_ASSET after this function returns.
frp_resolve_platform() {
  FRP_HOST_OS=$1
  FRP_HOST_MACHINE=$2

  FRP_OS=
  FRP_ARCH=
  FRP_GOOS=
  FRP_GOARCH=
  FRP_GOARM=
  FRP_RELEASE_ASSET=no

  case "$FRP_HOST_OS" in
    Linux)
      FRP_OS=linux
      FRP_GOOS=linux
      ;;
    Darwin)
      FRP_OS=darwin
      FRP_GOOS=darwin
      ;;
    FreeBSD)
      FRP_OS=freebsd
      FRP_GOOS=freebsd
      ;;
    OpenBSD)
      FRP_OS=openbsd
      FRP_GOOS=openbsd
      ;;
    NetBSD)
      FRP_OS=netbsd
      FRP_GOOS=netbsd
      ;;
    DragonFly)
      FRP_OS=dragonfly
      FRP_GOOS=dragonfly
      ;;
    *)
      return 1
      ;;
  esac

  case "$FRP_HOST_MACHINE" in
    x86|386|i386|i486|i586|i686)
      FRP_ARCH=386
      FRP_GOARCH=386
      ;;
    x86_64|amd64)
      FRP_ARCH=amd64
      FRP_GOARCH=amd64
      ;;
    arm|armv6*)
      FRP_ARCH=arm
      FRP_GOARCH=arm
      FRP_GOARM=6
      ;;
    armv5*)
      # The generic linux_arm release is not assumed to run on ARMv5.
      # Build with the matching Go target instead of risking an illegal
      # instruction on an older CPU.
      FRP_ARCH=arm
      FRP_GOARCH=arm
      FRP_GOARM=5
      ;;
    armhf|armv7|armv7l|armv7hl|armv8l)
      FRP_ARCH=arm_hf
      FRP_GOARCH=arm
      FRP_GOARM=7
      ;;
    arm64|aarch64)
      FRP_ARCH=arm64
      FRP_GOARCH=arm64
      ;;
    loong64|loongarch64)
      FRP_ARCH=loong64
      FRP_GOARCH=loong64
      ;;
    mips)
      FRP_ARCH=mips
      FRP_GOARCH=mips
      ;;
    mipsel)
      FRP_ARCH=mipsle
      FRP_GOARCH=mipsle
      ;;
    mips64)
      FRP_ARCH=mips64
      FRP_GOARCH=mips64
      ;;
    mips64el)
      FRP_ARCH=mips64le
      FRP_GOARCH=mips64le
      ;;
    ppc64)
      FRP_ARCH=ppc64
      FRP_GOARCH=ppc64
      ;;
    ppc64le)
      FRP_ARCH=ppc64le
      FRP_GOARCH=ppc64le
      ;;
    riscv64)
      FRP_ARCH=riscv64
      FRP_GOARCH=riscv64
      ;;
    s390x)
      FRP_ARCH=s390x
      FRP_GOARCH=s390x
      ;;
    sparc64)
      FRP_ARCH=sparc64
      FRP_GOARCH=sparc64
      ;;
    *)
      return 1
      ;;
  esac

  case "$FRP_OS:$FRP_ARCH:$FRP_GOARM" in
    linux:arm:5)
      FRP_RELEASE_ASSET=no
      ;;
    darwin:amd64:|darwin:arm64:|freebsd:amd64:|openbsd:amd64:|\
    linux:amd64:|linux:arm:6|linux:arm:7|linux:arm64:|\
    linux:arm_hf:7|linux:loong64:|linux:mips:|linux:mips64:|\
    linux:mips64le:|linux:mipsle:|linux:riscv64:)
      FRP_RELEASE_ASSET=yes
      ;;
  esac
}
