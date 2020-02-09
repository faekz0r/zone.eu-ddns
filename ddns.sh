#!/bin/bash

# This script updates an existing DNS A record on zone.eu. Meaning the A record has to be created before using this script.
#
# Software used: dig, curl, jq.
#
# You can use curl -X GET "https://api.zone.eu/v2/dns/example.com/a" -H "accept: application/json" -H "authorization: Basic example.credentials.hash"
# to see your exisiting A records.


# Pull credentials, domain, ID.
source ddns.config.sh

GDNS=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com);
ODNS=$(dig +short myip.opendns.com @resolver1.opendns.com);

IP='[\b(?:\d{1,3}\.){3}\d{1,3}\b]'

# Another option 
# IP='[^\d*.\d*.\d*.\d*$]'

# Filter Google quotation marks.
GDNS=${GDNS//\"};

ZoneARecord=
WanIP=

# Pull A record from Zone API
GetARecord () {
	ZoneARecord=$(curl -s -X GET "https://api.zone.eu/v2/dns/$Domain/a/$ID" -H "accept: application/json" -H "authorization: Basic $AuthCreds" | jq -r '.[0].destination')
	printf "Zone DNS zone A record: $ZoneARecord"
}

# $1 DNS resolved WAN IP.
# Call GetARecord to define the current A record.
# When DNS resolved IP is different from ZoneARecord, will return true.

IpHasChanged () {
	GetARecord;
	if ! grep -Fxq $1 <<< $ZoneARecord ; then
		printf "\nGoogle or OpenDNS reported different IP from DNS A record.\n"
		return 1;
	else
		return 0;
	fi
}

# Uses API call to update the DNS A record with information from config and DNS resolvers.

UpdateARecord () {
	curl -H "accept: application/json"\
		-H "authorization: Basic $AuthCreds"\
		-H "Content-Type: application/json"\
		-d '{ "destination": "'"$WanIP"'", "name": "'"$Domain"'" }'\
		-X PUT "https://api.zone.eu/v2/dns/$Domain/a/$ID";
}

# Updates the DNS record if our IP is different from API pulled current record.

DynDNS () {
	IpHasChanged "$1";
	if ((IpHasChanged)); then
		printf "\n\nDetected IP change. DNS update API call executed.\n\n"
		WanIP=$1;
		UpdateARecord;
		exit 0;
	else
		printf "\n\nIP has not changed. No DNS update API call needed.\n\n"
                exit 0;
	fi
}

# Check if Google DNS or/and OpenDNS resolved IPs match IP regex.
# If yes, call DynDNS

if [[ $GDNS =~ $IP ]]; then
	DynDNS "$GDNS";
elif
	[[ $ODNS =~ $IP ]]; then
	DynDNS "$ODNS";
else
	printf "\n\nDNS resolve did not work as expected - did not match regex.\n"
	printf "Did nothing.\n\n"
	exit 0;
fi
