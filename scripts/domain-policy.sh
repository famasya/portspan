#!/bin/sh

validate_dns_label() {
  policy_label=$1
  case "$policy_label" in
    ''|*[!a-z0-9-]*|-*|*-|control) return 1 ;;
  esac
  [ "${#policy_label}" -le 63 ]
}

validate_base_domain() {
  policy_domain=$1
  case "$policy_domain" in
    ''|*[!A-Za-z0-9.-]*|.*|*.) return 1 ;;
  esac

  [ "${#policy_domain}" -le 253 ] || return 1
  policy_old_ifs=$IFS
  IFS=.
  set -- $policy_domain
  IFS=$policy_old_ifs
  [ "$#" -ge 2 ] || return 1

  for policy_label in "$@"; do
    case "$policy_label" in
      ''|-*|*-|*[!A-Za-z0-9-]*) return 1 ;;
    esac
    [ "${#policy_label}" -le 63 ] || return 1
  done
}

validate_allowed_domains() {
  policy_allowed=$1
  case "$policy_allowed" in
    ''|*[!a-z0-9,-]*|,*|*,,|*,) return 1 ;;
  esac

  policy_old_ifs=$IFS
  IFS=,
  set -- $policy_allowed
  IFS=$policy_old_ifs
  [ "$#" -gt 0 ] || return 1

  policy_seen=
  for policy_label in "$@"; do
    validate_dns_label "$policy_label" || return 1
    case ",$policy_seen," in
      *,"$policy_label",*) return 1 ;;
    esac
    if [ -n "$policy_seen" ]; then
      policy_seen="$policy_seen,$policy_label"
    else
      policy_seen=$policy_label
    fi
  done
}

allowed_domain_contains() {
  policy_allowed=$1
  policy_candidate=$2
  case ",$policy_allowed," in
    *,"$policy_candidate",*) return 0 ;;
    *) return 1 ;;
  esac
}

allowed_domains_as_server_names() {
  policy_allowed=$1
  policy_base_domain=$2
  policy_old_ifs=$IFS
  IFS=,
  set -- $policy_allowed
  IFS=$policy_old_ifs

  policy_server_names=
  for policy_label in "$@"; do
    if [ -n "$policy_server_names" ]; then
      policy_server_names="$policy_server_names "
    fi
    policy_server_names="$policy_server_names$policy_label.$policy_base_domain"
  done
  printf '%s\n' "$policy_server_names"
}
