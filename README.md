# zone.eu DDNS

Small Bash dynamic DNS updater for ZoneID API v2. It keeps one Zone.eu DNS
A record pointed at the current public IPv4 address.

## What it does

- Detects the public IPv4 address with Google DNS and OpenDNS.
- Refuses to update when both resolvers return different valid addresses.
- Uses the ZoneID API v2 to create or update one matching A record.
- Caches the last successful IP locally so repeated cron runs avoid needless API calls.
- Uses `curl --netrc-file` so API credentials do not appear in command-line headers.

The legacy `ddns.sh` and `ddnsv2.sh` entrypoints are kept as wrappers around
`zone-ddns`.

## Requirements

- Bash 4 or newer
- `curl`
- `dig`
- `install`
- `python3` or `python` with the standard `json` module
- ZoneID username and API key

Zone documents the API at <https://api.zone.eu/v2>. Authentication is HTTP
Basic auth with the ZoneID username as the user and the API key as the password.

## Install

```bash
sudo install -m 0755 zone-ddns /usr/local/sbin/zone-ddns
sudo install -d -m 0755 /etc/zone-ddns /var/lib/zone-ddns
sudo install -m 0644 examples/config /etc/zone-ddns/config
sudo install -m 0600 examples/netrc /etc/zone-ddns/netrc
```

Edit `/etc/zone-ddns/config`:

```bash
DOMAIN=example.com
RECORD_NAME=example.com
NETRC_FILE=/etc/zone-ddns/netrc
STATE_FILE=/var/lib/zone-ddns/last_ipv4
API_BASE=https://api.zone.eu/v2
```

Edit `/etc/zone-ddns/netrc`:

```netrc
machine api.zone.eu
  login your-zoneid-username
  password your-zoneid-api-key
```

Keep the netrc file readable only by the user that runs the updater.

## Run

```bash
sudo zone-ddns
```

Use a different config file with:

```bash
ZONE_DDNS_CONFIG=/path/to/config zone-ddns
```

Example cron entry:

```cron
*/5 * * * * /usr/local/sbin/zone-ddns
```

Delete the state file if you want to force an API check on the next run:

```bash
sudo rm -f /var/lib/zone-ddns/last_ipv4
```

## Configuration

`DOMAIN` is required and must be the DNS zone name in Zone.eu.

`RECORD_NAME` defaults to `DOMAIN`. Set it to a fully qualified record name,
for example `home.example.com`, when updating a subdomain.

`NETRC_FILE` defaults to `/etc/zone-ddns/netrc`.

`STATE_FILE` defaults to `/var/lib/zone-ddns/last_ipv4`.

`API_BASE` defaults to `https://api.zone.eu/v2`.

The config file is sourced by Bash. Keep values simple, quote anything with
spaces, and do not make the file writable by untrusted users.

## Behavior

If no matching A record exists, `zone-ddns` creates one. If exactly one matching
A record exists and the IP changed, it updates that record. If more than one
matching A record exists, or the record is not modifiable, it exits without
changing DNS.

Only IPv4 A records are supported. IPv6 AAAA records and SPF/TXT updates are
not handled by this script.

## Tests

Run the test suite:

```bash
bash tests/zone-ddns-test.sh
```

Run syntax checks:

```bash
for file in zone-ddns ddns.sh ddnsv2.sh tests/zone-ddns-test.sh; do
  bash -n "$file"
done
```
