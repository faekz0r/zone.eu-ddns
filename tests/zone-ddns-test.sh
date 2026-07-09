#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_under_test="$repo_root/zone-ddns"
tmp_root="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    fail "$message: expected [$expected], got [$actual]"
  fi
}

assert_contains() {
  local needle="$1"
  local file="$2"
  local message="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    fail "$message: expected [$needle] in $file"
  fi
}

assert_not_contains() {
  local needle="$1"
  local file="$2"
  local message="$3"
  if grep -Fq -- "$needle" "$file"; then
    fail "$message: unexpected [$needle] in $file"
  fi
}

assert_no_write_requests() {
  local curl_log="$1"
  if grep -Eq '^(POST|PUT) ' "$curl_log" 2>/dev/null; then
    fail "expected no POST/PUT requests, got: $(cat "$curl_log")"
  fi
}

assert_no_api_requests() {
  local curl_log="$1"
  if [[ -s "$curl_log" ]]; then
    fail "expected no API requests, got: $(cat "$curl_log")"
  fi
}

make_case_dir() {
  local name="$1"
  local dir="$tmp_root/$name"
  mkdir -p "$dir/mockbin" "$dir/state" "$dir/etc"
  printf 'machine api.zone.eu login being password TEST_SECRET\n' > "$dir/netrc"
  chmod 0600 "$dir/netrc"
  cat > "$dir/config" <<CFG
DOMAIN=228.ee
RECORD_NAME=228.ee
NETRC_FILE=$dir/netrc
STATE_FILE=$dir/state/last_ipv4
API_BASE=https://api.zone.eu/v2
CFG

  cat > "$dir/mockbin/dig" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *o-o.myaddr.l.google.com*) printf '%s\n' "${MOCK_GDNS:-}" ;;
  *myip.opendns.com*) printf '%s\n' "${MOCK_ODNS:-}" ;;
  *) exit 1 ;;
esac
MOCK
  chmod +x "$dir/mockbin/dig"

  cat > "$dir/mockbin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
method=GET
out_file=
write_status=0
url=
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -X)
      i=$((i + 1))
      method="${args[$i]}"
      ;;
    -o)
      i=$((i + 1))
      out_file="${args[$i]}"
      ;;
    -w)
      i=$((i + 1))
      [[ "${args[$i]}" == "%{http_code}" ]] && write_status=1
      ;;
    http://*|https://*)
      url="${args[$i]}"
      ;;
  esac
done

printf '%s %s %s\n' "$method" "$url" "$*" >> "$MOCK_CURL_LOG"

status=200
body='[]'
case "$method" in
  GET)
    status="${MOCK_GET_STATUS:-200}"
    body="${MOCK_RECORDS_JSON:-[]}"
    ;;
  PUT)
    status="${MOCK_PUT_STATUS:-200}"
    body='[{"updated":true}]'
    ;;
  POST)
    status="${MOCK_POST_STATUS:-201}"
    body='[{"created":true}]'
    ;;
  *)
    status=400
    body='{"error":"unexpected method"}'
    ;;
esac

if [[ -n "$out_file" ]]; then
  printf '%s' "$body" > "$out_file"
else
  printf '%s' "$body"
fi

if [[ "$write_status" == 1 ]]; then
  printf '%s' "$status"
fi
MOCK
  chmod +x "$dir/mockbin/curl"

  printf '%s\n' "$dir"
}

run_case() {
  local name="$1"
  local expected_status="$2"
  local gdns="$3"
  local odns="$4"
  local records_json="$5"
  local put_status="${6:-200}"
  local post_status="${7:-201}"

  local dir
  dir="$(make_case_dir "$name")"
  local stdout="$dir/stdout"
  local stderr="$dir/stderr"
  local curl_log="$dir/curl.log"
  : > "$curl_log"

  set +e
  PATH="$dir/mockbin:$PATH" \
    ZONE_DDNS_CONFIG="$dir/config" \
    MOCK_GDNS="$gdns" \
    MOCK_ODNS="$odns" \
    MOCK_RECORDS_JSON="$records_json" \
    MOCK_PUT_STATUS="$put_status" \
    MOCK_POST_STATUS="$post_status" \
    MOCK_CURL_LOG="$curl_log" \
    "$script_under_test" >"$stdout" 2>"$stderr"
  local status=$?
  set -e

  assert_eq "$expected_status" "$status" "$name exit status"
  printf '%s\n' "$dir"
}

one_record_same='[{"id":594701,"name":"228.ee","destination":"90.191.47.253","modify":true}]'
one_record_old='[{"id":594701,"name":"228.ee","destination":"90.191.47.200","modify":true}]'
zero_apex='[{"id":111,"name":"www.228.ee","destination":"90.191.47.10","modify":true}]'
multiple_apex='[{"id":1,"name":"228.ee","destination":"90.191.47.1","modify":true},{"id":2,"name":"228.ee","destination":"90.191.47.2","modify":true}]'

dir="$(make_case_dir skip_api_when_cached_ip_matches)"
printf '90.191.47.253\n' > "$dir/state/last_ipv4"
: > "$dir/curl.log"
PATH="$dir/mockbin:$PATH" \
  ZONE_DDNS_CONFIG="$dir/config" \
  MOCK_GDNS="90.191.47.253" \
  MOCK_ODNS="90.191.47.253" \
  MOCK_RECORDS_JSON="$one_record_old" \
  MOCK_CURL_LOG="$dir/curl.log" \
  "$script_under_test" >"$dir/stdout" 2>"$dir/stderr"
assert_no_api_requests "$dir/curl.log"
assert_contains "unchanged since last successful update" "$dir/stdout" "cached IP exits before API lookup"

dir="$(run_case no_update_when_record_matches 0 "90.191.47.253" "90.191.47.253" "$one_record_same")"
assert_no_write_requests "$dir/curl.log"
assert_eq "90.191.47.253" "$(cat "$dir/state/last_ipv4")" "matching record stores last IP"
assert_contains "--netrc-file" "$dir/curl.log" "curl uses netrc"
assert_not_contains "TEST_SECRET" "$dir/curl.log" "curl args do not expose secret"
assert_not_contains "authorization:" "$dir/curl.log" "curl args do not use authorization header"

dir="$(run_case update_when_record_differs 0 "90.191.47.253" "90.191.47.253" "$one_record_old")"
assert_contains "PUT https://api.zone.eu/v2/dns/228.ee/a/594701" "$dir/curl.log" "changed IP updates existing apex record"
assert_eq "90.191.47.253" "$(cat "$dir/state/last_ipv4")" "updated record stores last IP"

dir="$(run_case create_when_no_apex_record_exists 0 "90.191.47.253" "90.191.47.253" "$zero_apex")"
assert_contains "POST https://api.zone.eu/v2/dns/228.ee/a" "$dir/curl.log" "missing apex record is created"
assert_eq "90.191.47.253" "$(cat "$dir/state/last_ipv4")" "created record stores last IP"

dir="$(run_case fail_when_multiple_apex_records_exist 1 "90.191.47.253" "90.191.47.253" "$multiple_apex")"
assert_no_write_requests "$dir/curl.log"
[[ ! -f "$dir/state/last_ipv4" ]] || fail "multiple apex records must not update state"

dir="$(run_case fallback_to_opendns_when_google_fails 0 "not-an-ip" "90.191.47.253" "$one_record_old")"
assert_contains "PUT https://api.zone.eu/v2/dns/228.ee/a/594701" "$dir/curl.log" "OpenDNS fallback updates existing record"
assert_eq "90.191.47.253" "$(cat "$dir/state/last_ipv4")" "OpenDNS fallback stores last IP"

dir="$(run_case fail_when_both_resolvers_are_invalid 1 "bad" "also-bad" "$one_record_old")"
assert_no_write_requests "$dir/curl.log"
[[ ! -f "$dir/state/last_ipv4" ]] || fail "invalid resolvers must not update state"

dir="$(run_case fail_when_resolvers_disagree 1 "90.191.47.253" "90.191.47.254" "$one_record_old")"
assert_no_write_requests "$dir/curl.log"
[[ ! -f "$dir/state/last_ipv4" ]] || fail "disagreeing resolvers must not update state"

dir="$(run_case api_failure_does_not_update_state 1 "90.191.47.253" "90.191.47.253" "$one_record_old" 500)"
assert_contains "PUT https://api.zone.eu/v2/dns/228.ee/a/594701" "$dir/curl.log" "API failure attempted one PUT"
[[ ! -f "$dir/state/last_ipv4" ]] || fail "API failure must not update state"

printf 'All zone-ddns tests passed\n'
