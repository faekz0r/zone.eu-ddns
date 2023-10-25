#!/bin/bash

# This script updates an existing DNS A record on zone.eu. Meaning the A record has to be created before using this script.
#
# Software used: dig, curl, jq.
#
# You can use curl -X GET "https://api.zone.eu/v2/dns/example.com/a" -H "accept: application/json" -H "authorization: Basic example.credentials.hash"
# to see your exisiting A records.


# Pull credentials, domain, IDs.
source /home/being/DynamicDNS/ddns.config.sh

# Commands for resolving our WAN IP.
GDNS=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com);
ODNS=$(dig +short myip.opendns.com @resolver1.opendns.com);

# IP matching regex.
IP='[\b(?:\d{1,3}\.){3}\d{1,3}\b]'

# Another option
# IP='[^\d*.\d*.\d*.\d*$]'

# Filter Google quotation marks.
GDNS=${GDNS//\"};

ZoneARecord=
WanIP=

# Pull A record from Zone API.
#GetARecord () {
#	ZoneARecord=$(curl -s -X GET "https://api.zone.eu/v2/dns/$Domain/a/$idA" -H "accept: application/json" -H "authorization: Basic $AuthCreds" | jq -r '.[0].destination')
#	printf "Zone DNS current A record: $ZoneARecord"
#}

GetARecord () {
    curl -s -X GET "https://api.zone.eu/v2/dns/$Domain/a/$idA" -H "accept: application/json" -H "authorization: Basic $AuthCreds" > GetARecord_debug.json
    ZoneARecord=$(jq -r '.[0].destination' GetARecord_debug.json)
    printf "Zone DNS current A record: $ZoneARecord\n"
}


# $1 DNS resolved WAN IP.
# Call GetARecord to define the current A record.
# When DNS resolved IP is different from ZoneARecord, will return true.

IpHasChanged () {
	GetARecord;

	if [ "$1" != "$ZoneARecord" ] ; then
		printf "\nGoogle or OpenDNS reported different IP from DNS A record.\n"
		return;
	fi

	false
}

# Uses API calls to update the DNS records with information from config and DNS resolvers.

UpdateRecords () {
	curl -H "accept: application/json"\
		-H "authorization: Basic $AuthCreds"\
		-H "Content-Type: application/json"\
		-d '{ "destination": "'"$WanIP"'", "name": "'"$Domain"'" }'\
		-X PUT "https://api.zone.eu/v2/dns/$Domain/a/$idA";
	printf "\n\n"

	#SPF lisa h2kk
	curl -H "accept: application/json"\
                -H "authorization: Basic $AuthCreds"\
                -H "Content-Type: application/json"\
                -d '{ "destination": "'"v=spf1 ip4:$WanIP -all"'", "name": "'"$Domain"'" }'\
                -X PUT "https://api.zone.eu/v2/dns/$Domain/txt/$idSPF";
}

# Updates the DNS record if our IP is different from API pulled current record.

UpdateIfIPChanged () {
	if IpHasChanged $1; then
		printf "\n\nDetected IP change. DNS update API call executed.\n\n"
		WanIP=$1;
		UpdateRecords;
		exit 0;
	else
		printf "\n\nIP has not changed. No DNS update API call needed.\n\n"
                exit 0;
	fi
}

# Check if Google DNS or/and OpenDNS resolved IPs match IP regex.
# If yes, call UpdateIfIPChanged

if [[ $GDNS =~ $IP ]]; then
	UpdateIfIPChanged "$GDNS";
elif
	[[ $ODNS =~ $IP ]]; then
	UpdateIfIPChanged "$ODNS";
else
	printf "\n\nDNS resolve did not work as expected - did not match regex.\n"
	printf "Did nothing.\n\n"
	exit 0;
fi
