#!/bin/sh

# These digests are for the exact v0.71.0 assets used by the installers.
# Keep this function explicit so changing FRP_VERSION cannot reuse a stale
# checksum accidentally.
frp_expected_sha256() {
  case "$1" in
    frp_0.71.0_darwin_amd64.tar.gz)
      printf '%s\n' '1b1b4e2f1836e21e8733f1dddaacd4ed9ae67d7dbee39046b9d7b7eda6253637'
      ;;
    frp_0.71.0_darwin_arm64.tar.gz)
      printf '%s\n' '45be02b186860d375ed49a8941ae9569628a54bf14e67fc36b29c98c99dabcc6'
      ;;
    frp_0.71.0_freebsd_amd64.tar.gz)
      printf '%s\n' '207c85353dd66e9ef1125a8ee60e4fd4a562f364bc584c4a5ff55e7ac7355bb8'
      ;;
    frp_0.71.0_linux_amd64.tar.gz)
      printf '%s\n' '84f27e39f11169f7adcef8e8b70c9329de17747b1f14dad9fb95eef5682ea716'
      ;;
    frp_0.71.0_linux_arm.tar.gz)
      printf '%s\n' 'f40a984f83e8d34a9241b0be4a9d5fbcfe513a4a5c022b84a02637ff6d36833b'
      ;;
    frp_0.71.0_linux_arm64.tar.gz)
      printf '%s\n' 'f33c293c275d8fc68c654b6fba8f10b2551d6463d09a9fc9cffb7227eae82266'
      ;;
    frp_0.71.0_linux_arm_hf.tar.gz)
      printf '%s\n' 'eab1ecb45b00e2f9cf2ebc458fde570ceecb50689c4c5c728677f44825bf3d88'
      ;;
    frp_0.71.0_linux_loong64.tar.gz)
      printf '%s\n' 'e5f4d7e25b677cca885f3db5cc958441bfa12e7214e05304601331ac3d84cebc'
      ;;
    frp_0.71.0_linux_mips.tar.gz)
      printf '%s\n' 'dd3fb404b546f215848db466c5707f501bcc2e24f605228f52e2a1546904a29d'
      ;;
    frp_0.71.0_linux_mips64.tar.gz)
      printf '%s\n' '3d336925e8bbba313d956b04d59e2dcf301f169304bbc105340133bc3e524451'
      ;;
    frp_0.71.0_linux_mips64le.tar.gz)
      printf '%s\n' 'adcd256a6fa5c96985a1ddd02e0e759fc054fa3e858748055d7e49e80f51c68f'
      ;;
    frp_0.71.0_linux_mipsle.tar.gz)
      printf '%s\n' '14498e36554a275a9d41a61aa29680616a34c7c9d8914e2173a46dada4928c70'
      ;;
    frp_0.71.0_linux_riscv64.tar.gz)
      printf '%s\n' '92b48d5e4d44d2f1415fde24489d3dfff5badbd52ddf7e816467cdcaa973aa5c'
      ;;
    frp_0.71.0_openbsd_amd64.tar.gz)
      printf '%s\n' 'b029091fd9bca134fac6db7a80560a6d09a6c06c09b59cbf99e698d85bdd2eb5'
      ;;
    *)
      return 1
      ;;
  esac
}

frp_source_sha256() {
  case "$1" in
    0.71.0)
      printf '%s\n' '1dd367d6d822a7fce1d3012fce0a6e778bc90c454e2c7baa0eb1e6de6054c61b'
      ;;
    *)
      return 1
      ;;
  esac
}
