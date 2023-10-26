#!/bin/bash

# Import variables
source /home/being/DynamicDNS/ddns.config.sh

# IP matching regex
IP='[\b(?:\d{1,3}\.){3}\d{1,3}\b]'

# File to keep the last known IP address
LAST_IP_FILE="/home/being/DynamicDNS/last_ip.txt"

# Fetch the WAN IP from Google DNS and OpenDNS
GDNS=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
ODNS=$(dig +short myip.opendns.com @resolver1.opendns.com)

# Read the last known IP from the file
if [[ -f $LAST_IP_FILE ]]; then
  LastIP=$(cat $LAST_IP_FILE)
else
  LastIP=""
fi

# Function to update DNS records
UpdateRecords() {
  RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "accept: application/json"\
    -H "authorization: Basic $AuthCreds"\
    -H "Content-Type: application/json"\
    -d '{ "destination": "'"$WanIP"'", "name": "'"$Domain"'" }'\
    -X PUT "https://api.zone.eu/v2/dns/$Domain/a/$idA")

  # Check if the API call was successful
  if [[ $RESPONSE_CODE -ge 200 && $RESPONSE_CODE -lt 300 ]]; then
    # If successful, update SPF as well
    curl -H "accept: application/json"\
         -H "authorization: Basic $AuthCreds"\
         -H "Content-Type: application/json"\
         -d '{ "destination": "'"v=spf1 ip4:$WanIP -all"'", "name": "'"$Domain"'" }'\
         -X PUT "https://api.zone.eu/v2/dns/$Domain/txt/$idSPF"

    # Save the new IP to the file
    echo $WanIP > $LAST_IP_FILE
    echo "Successfully updated DNS records."
  else
    echo "Failed to update DNS records. HTTP status code: $RESPONSE_CODE"
  fi
}

# Function to check if the IP has changed and update DNS records if needed
UpdateIfIPChanged() {
  if [[ "$1" != "$LastIP" ]]; then
    echo "Detected IP change. Attempting DNS update."
    WanIP=$1
    UpdateRecords
  else
    echo "IP has not changed. No DNS update API call needed."
  fi
}

# Check if the IPs fetched match the IP regex and then call UpdateIfIPChanged
if [[ $GDNS =~ $IP ]]; then
  UpdateIfIPChanged "$GDNS"
elif [[ $ODNS =~ $IP ]]; then
  UpdateIfIPChanged "$ODNS"
else
  echo "DNS resolve did not work as expected - did not match regex."
  echo "Did nothing."
fi
