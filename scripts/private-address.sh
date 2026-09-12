#!/bin/sh

is_private_ipv4() {
  private_address=$1
  case "$private_address" in
    ''|*[!0-9.]*|.*|*.|*..*) return 1 ;;
  esac

  private_old_ifs=$IFS
  IFS=.
  set -- $private_address
  IFS=$private_old_ifs
  [ "$#" -eq 4 ] || return 1

  for private_octet in "$@"; do
    [ "$private_octet" -le 255 ] 2>/dev/null || return 1
  done

  case "$1" in
    10|100|192)
      if [ "$1" -eq 100 ]; then
        [ "$2" -ge 64 ] 2>/dev/null && [ "$2" -le 127 ] 2>/dev/null || return 1
      elif [ "$1" -eq 192 ]; then
        [ "$2" -eq 168 ] 2>/dev/null || return 1
      fi
      ;;
    172)
      [ "$2" -ge 16 ] 2>/dev/null && [ "$2" -le 31 ] 2>/dev/null || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

is_private_or_vpn_address() {
  private_address=$1
  case "$private_address" in
    *:*)
      case "$private_address" in
        [Ff][Cc]:*|[Ff][Cc][0-9A-Fa-f]:*|[Ff][Cc][0-9A-Fa-f][0-9A-Fa-f]:*|\
        [Ff][Dd]:*|[Ff][Dd][0-9A-Fa-f]:*|[Ff][Dd][0-9A-Fa-f][0-9A-Fa-f]:*|\
        [Ff][Ee]80:*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *)
      is_private_ipv4 "$private_address"
      ;;
  esac
}

is_private_or_vpn_network() {
  private_network=$1
  case "$private_network" in
    */*)
      private_network_address=${private_network%/*}
      private_network_prefix=${private_network#*/}
      ;;
    *)
      return 1
      ;;
  esac

  case "$private_network_prefix" in
    ''|*[!0-9]*) return 1 ;;
  esac
  is_private_or_vpn_address "$private_network_address" || return 1

  case "$private_network_address" in
    *:*)
      [ "$private_network_prefix" -le 128 ] 2>/dev/null
      ;;
    *)
      [ "$private_network_prefix" -le 32 ] 2>/dev/null
      ;;
  esac
}
