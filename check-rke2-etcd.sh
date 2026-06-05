#!/usr/bin/env bash

set -u
set -o pipefail

RKE2_BIN_DIR="/var/lib/rancher/rke2/bin"
CRI_CONFIG_FILE="${CRI_CONFIG_FILE:-/var/lib/rancher/rke2/agent/etc/crictl.yaml}"
ETCD_TLS_DIR="/var/lib/rancher/rke2/server/tls/etcd"
ETCD_CERT="${ETCD_TLS_DIR}/server-client.crt"
ETCD_KEY="${ETCD_TLS_DIR}/server-client.key"
ETCD_CACERT="${ETCD_TLS_DIR}/server-ca.crt"

export PATH="${PATH}:${RKE2_BIN_DIR}"
export CRI_CONFIG_FILE

WARNINGS=0
FAILURES=0
MEMBER_COUNT=0
ENDPOINT_COUNT=0
LEADER_COUNT="unknown"
HEALTH_FAILURES=0
ALARM_COUNT=0

print_section() {
  printf '\n==== %s ====\n' "$1"
}

info() {
  printf '[INFO] %s\n' "$1"
}

pass() {
  printf '[PASS] %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '[WARN] %s\n' "$1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf '[FAIL] %s\n' "$1"
}

die_preflight() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 2
}

run_etcdctl() {
  crictl exec "$ETCD_CONTAINER" etcdctl "$@" \
    --cert "$ETCD_CERT" \
    --key "$ETCD_KEY" \
    --cacert "$ETCD_CACERT"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die_preflight "Required command not found: $1"
}

require_file() {
  [ -f "$1" ] || die_preflight "Required file not found: $1"
}

extract_endpoints() {
  awk -F',' '
    NF >= 5 {
      endpoint=$5
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", endpoint)
      if (endpoint != "") {
        print endpoint
      }
    }
  '
}

print_section "RKE2 etcd local check"
info "Using CRI_CONFIG_FILE=${CRI_CONFIG_FILE}"
info "Using RKE2 bin dir=${RKE2_BIN_DIR}"
info "Using etcd TLS dir=${ETCD_TLS_DIR}"

require_command crictl
require_file "$CRI_CONFIG_FILE"
require_file "$ETCD_CERT"
require_file "$ETCD_KEY"
require_file "$ETCD_CACERT"

print_section "Discover etcd container"
if ! ETCD_CONTAINERS="$(crictl ps --name etcd --quiet 2>&1)"; then
  printf '%s\n' "$ETCD_CONTAINERS"
  die_preflight "Failed to query etcd container with crictl."
fi

ETCD_CONTAINER_COUNT="$(printf '%s\n' "$ETCD_CONTAINERS" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
if [ "$ETCD_CONTAINER_COUNT" -eq 0 ]; then
  die_preflight "No running etcd container found. Expected crictl ps --name etcd --quiet to return one container."
fi

if [ "$ETCD_CONTAINER_COUNT" -gt 1 ]; then
  printf '%s\n' "$ETCD_CONTAINERS"
  die_preflight "Multiple etcd containers found. Please check the node manually."
fi

ETCD_CONTAINER="$(printf '%s\n' "$ETCD_CONTAINERS" | sed '/^[[:space:]]*$/d' | head -n 1)"
pass "Found etcd container: ${ETCD_CONTAINER}"

print_section "crictl ps --name etcd"
if crictl ps --name etcd; then
  pass "etcd container is visible through crictl."
else
  fail "Failed to display etcd container details."
fi

print_section "etcdctl member list"
if MEMBER_LIST_OUTPUT="$(run_etcdctl member list 2>&1)"; then
  printf '%s\n' "$MEMBER_LIST_OUTPUT"
  MEMBER_COUNT="$(printf '%s\n' "$MEMBER_LIST_OUTPUT" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  pass "member list command succeeded."
else
  printf '%s\n' "$MEMBER_LIST_OUTPUT"
  fail "member list command failed."
fi

ENDPOINTS=""
if [ -n "${MEMBER_LIST_OUTPUT:-}" ]; then
  ENDPOINTS="$(printf '%s\n' "$MEMBER_LIST_OUTPUT" | extract_endpoints | paste -sd ',' -)"
fi

if [ -z "$ENDPOINTS" ]; then
  fail "No client endpoints could be extracted from member list output."
else
  ENDPOINT_COUNT="$(printf '%s' "$ENDPOINTS" | awk -F',' '{ print NF }')"
  pass "Extracted client endpoints: ${ENDPOINTS}"
fi

if [ -n "$ENDPOINTS" ]; then
  print_section "etcdctl endpoint status"
  if ENDPOINT_STATUS_OUTPUT="$(run_etcdctl endpoint status --write-out=table --endpoints="$ENDPOINTS" 2>&1)"; then
    printf '%s\n' "$ENDPOINT_STATUS_OUTPUT"
    LEADER_COUNT="$(printf '%s\n' "$ENDPOINT_STATUS_OUTPUT" | awk -F'|' 'tolower($6) ~ /true/ { count++ } END { print count + 0 }')"
    pass "endpoint status command succeeded."
  else
    printf '%s\n' "$ENDPOINT_STATUS_OUTPUT"
    fail "endpoint status command failed."
  fi

  print_section "etcdctl endpoint health"
  if ENDPOINT_HEALTH_OUTPUT="$(run_etcdctl endpoint health --endpoints="$ENDPOINTS" 2>&1)"; then
    printf '%s\n' "$ENDPOINT_HEALTH_OUTPUT"
    HEALTH_FAILURES="$(printf '%s\n' "$ENDPOINT_HEALTH_OUTPUT" | grep -Eiv 'is healthy|^[[:space:]]*$' | wc -l | tr -d ' ')"
    if [ "$HEALTH_FAILURES" -eq 0 ]; then
      pass "all endpoints reported healthy."
    else
      warn "endpoint health command exited successfully, but output contains ${HEALTH_FAILURES} suspicious line(s)."
    fi
  else
    printf '%s\n' "$ENDPOINT_HEALTH_OUTPUT"
    HEALTH_FAILURES="$(printf '%s\n' "$ENDPOINT_HEALTH_OUTPUT" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
    fail "endpoint health command failed."
  fi
fi

print_section "etcdctl alarm list"
if ALARM_OUTPUT="$(run_etcdctl alarm list 2>&1)"; then
  if [ -n "$ALARM_OUTPUT" ]; then
    printf '%s\n' "$ALARM_OUTPUT"
    ALARM_COUNT="$(printf '%s\n' "$ALARM_OUTPUT" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
    warn "etcd alarm list is not empty."
  else
    pass "no etcd alarms reported."
  fi
else
  printf '%s\n' "$ALARM_OUTPUT"
  fail "alarm list command failed."
fi

print_section "Summary"
printf 'Container: %s\n' "${ETCD_CONTAINER:-unknown}"
printf 'Members: %s\n' "$MEMBER_COUNT"
printf 'Client endpoints: %s\n' "$ENDPOINT_COUNT"
printf 'Leaders reported by endpoint status: %s\n' "$LEADER_COUNT"
printf 'Endpoint health failures: %s\n' "$HEALTH_FAILURES"
printf 'Etcd alarms: %s\n' "$ALARM_COUNT"
printf 'Warnings: %s\n' "$WARNINGS"
printf 'Failures: %s\n' "$FAILURES"

if [ "$FAILURES" -gt 0 ]; then
  printf '\nResult: FAIL\n'
  exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
  printf '\nResult: WARN\n'
  exit 1
fi

printf '\nResult: PASS\n'
exit 0
