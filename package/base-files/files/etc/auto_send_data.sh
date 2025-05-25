#!/bin/bash

# Collect device information - TMA Prime
# This script collects device information and sends it to a specified cloud endpoint using curl.
# It will be triggered each 1 minute by crontab
# Version: 0.3
# New Updates:
#   1. When powering on the Mesh Node, if there is no GPS signal, we set the TMA position as the default.
#   2. The previous position will be set and sent to IoT if there is no GPS signal.

# Version: 0.4
# New Updates:
#   1. Update IOT URL with 2 options (cloud & local)
#   2. Get default gateway ip when setting cloud and assigning 192.168.12.10 as local default gateway ip


#Get&Set cron service
GATEWAYIP=
GetSetConService (){
    if [ $IOT_CLOUD_FLAG == 1 ]; then
        fping -c 1 -t 500 $IOT_CLOUD_URL|grep "0% loss"
        if [ $? == 0 ]; then
            GATEWAYIP=$(route -n | awk 'NR > 2 && $2 != "0.0.0.0" {print $2}' | head -n 1)
            SetConService $GATEWAYIP
        else
            echo "Not found default gateway ip"
            exit 0
        fi

    else
        GATEWAYIP="192.168.12.10"
        SetConService $GATEWAYIP
    fi
}

SetConService(){
    grep "fping" /etc/crontabs/root
    if [ $? != 0 ]; then
        #255.255.255.0
        SUBNET=$(echo $1 | cut -d '.' -f1-3)
        (crontab -l 2>/dev/null; echo "* * * * * for ip in \$(seq 1 254);do fping -c 1 -t 100 $SUBNET.\$ip;done") | crontab -
        service cron restart
    fi
}
# Read iw output to get MAC Addresses and RSSI
ReadIWOutput () {
    IFS_BAK=$IFS
    IFS=$'\n'

    for line in $IW_OUTPUT
    do
        if [[ "$(echo $line)" =~ "Station" ]]
        then
            MAC_ADDR_LINE=$line

            IFS=$IFS_BAK
            IFS_BAK=
            MAC_ADDR_DEV=$(echo $MAC_ADDR_LINE | awk '{print $2}')
            IPv4_DEV=$(ip -4 neighbor | grep $MAC_ADDR_DEV | awk '{print $1}')
            # Validate if we can access the IP
            curl $IPv4_DEV > /dev/null 2>/dev/null
            VALID_IP=$?
            # Only store list of accessible IP
            if [ $VALID_IP -eq 0 ]; then
                MAC_ADDR_DEV_ARR="${MAC_ADDR_DEV_ARR} ${MAC_ADDR_DEV}"
                IPv4_DEV_ARR="${IPv4_DEV_ARR} ${IPv4_DEV}"
            fi

            IFS_BAK=$IFS
            IFS=$'\n'
        fi

        if [[ "$(echo $line)" =~ "signal:" ]]
        then
            SIGNAL_LINE=$line

            IFS=$IFS_BAK
            IFS_BAK=
            SIGNAL_DEV=$(echo $SIGNAL_LINE | awk '{print $2}')
            if [ $VALID_IP -eq 0 ]; then
                SIGNAL_DEV_ARR="${SIGNAL_DEV_ARR} ${SIGNAL_DEV}"
            fi

            IFS_BAK=$IFS
            IFS=$'\n'
        fi
    done

    IFS=$IFS_BAK
    IFS_BAK=
}

# check cron service

GetSetConService

# Create Json from iw output
# $1 - name of new field
JsonFromIW () {
    JSONDATA="${JSONDATA},\"$1\":[\
"

    INDEX=1
    NUM_MAC_ADDR_DEV=$(echo "$MAC_ADDR_DEV_ARR" | grep -o ' ' | wc -l)
    echo "Number of connected device for $1: $NUM_MAC_ADDR_DEV"
    while [[ "$INDEX" -le "$NUM_MAC_ADDR_DEV" ]]
    do
        MAC=$(echo "$MAC_ADDR_DEV_ARR" | awk "{print \$$INDEX}")
        IPv4=$(echo "$IPv4_DEV_ARR" | awk "{print \$$INDEX}")
        RSSI=$(echo "$SIGNAL_DEV_ARR" | awk "{print \$$INDEX}")
        JSONDATA="${JSONDATA}{\"MAC\":\"$MAC\", \"IPv4\":\"$IPv4\", \"RSSI\":\"$RSSI\"}"
        if [[ "$INDEX" -lt "$NUM_MAC_ADDR_DEV" ]]
        then
            JSONDATA="${JSONDATA},"
        fi
        JSONDATA="${JSONDATA}\
"
        INDEX=$((INDEX + 1))
    done

    JSONDATA="${JSONDATA}\
]"
}

interface=$1
 
DEVICE_ID=$(hostname)
MODEL=$(cat /tmp/sysinfo/model)
#MODEL=$(cat /proc/cpuinfo|grep "model name"|head -1 |awk -F ':' '{print $2}')
ARCH=$(uname -m)
FW_VERSION=$(cat /etc/openwrt_version)
UPTIME=$(uptime)
# IP_ADDR=$(ip -4 addr show br-lan | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Node information
IP_ADDR=$(ip -4 -br addr show $interface|grep UP)
if [ $? -ne 0 ]; then
    echo "Failed to get IP address"
else
    IP_ADDR=$(echo $IP_ADDR)| awk '{print $3}'
fi
MAC_ADDR=$(cat /sys/class/net/$interface/address)
RSSI=$(iw dev $interface link | grep -i 'signal' | awk '{print $4}')
SSID=$(iw dev $interface link | grep SSID | awk '{print $2}')

# Take IP Address
RAW_IP=$(ip -4 -br addr show $interface | grep UP | awk '{print $3}')
IP_ADDR=${RAW_IP%%/*}

# GPS information
# GPGGA message
GPGGA_messgage=$(head -n 20 /dev/ttyS0 | grep 'GPGGA' | head -n 1)
GPGGA_TIME_UTC=$(echo $GPGGA_messgage|awk -F ',' '{print $2}')
GPGGA_LATITUDI=$(echo $GPGGA_messgage|awk -F ',' '{print $3}')
GPGGA_NORTH_SOUTH=$(echo $GPGGA_messgage|awk -F ',' '{print $4}')
GPGGA_LONGITUDI=$(echo $GPGGA_messgage|awk -F ',' '{print $5}')
GPGGA_EAST_WEST=$(echo $GPGGA_messgage|awk -F ',' '{print $6}')
#set additional varibales here
# example: geoid,M,,,*checksum,,...

# GNGGA message
GNGGA_messgage=$(head -n 20 /dev/ttyS0 | grep 'GNGGA' | head -n 1)
GNGGA_TIME_UTC=$(echo $GNGGA_messgage|awk -F ',' '{print $2}')
GNGGA_LATITUDI=$(echo $GNGGA_messgage|awk -F ',' '{print $3}')
GNGGA_NORTH_SOUTH=$(echo $GNGGA_messgage|awk -F ',' '{print $4}')
GNGGA_LONGITUDI=$(echo $GNGGA_messgage|awk -F ',' '{print $5}')
GNGGA_EAST_WEST=$(echo $GNGGA_messgage|awk -F ',' '{print $6}')


TIME_UTC=
LONGITUDE_FLOAT=
EAST_WEST=
LATITUDE_FLOAT=
NORTH_SOUTH=
logfile=/tmp/jsondata.log
if [ -f $logfile ]; then
    TIME_UTC=$(grep time_utc $logfile | awk -F'"time_utc":"' '{print $2}' | awk -F'"' '{print $1}')
    LONGITUDE_FLOAT=$(grep longitude $logfile | awk -F'"longitude":"' '{print $2}' | awk -F'"' '{print $1}')
    EAST_WEST=$(grep east/west $logfile | awk -F'"east/west":"' '{print $2}' | awk -F'"' '{print $1}')
    LATITUDE_FLOAT=$(grep latitude $logfile | awk -F'"latitude":"' '{print $2}' | awk -F'"' '{print $1}')
    NORTH_SOUTH=$(grep north/south $logfile | awk -F'"north/south":"' '{print $2}' | awk -F'"' '{print $1}')
    echo 0 $TIME_UTC $LONGITUDE_FLOAT $EAST_WEST $LATITUDE_FLOAT $NORTH_SOUTH
else 
    TIME_UTC=000000.000
    LONGITUDE_FLOAT=10637.88524
    EAST_WEST=E
    LATITUDE_FLOAT=1051.34284
    NORTH_SOUTH=N
    echo 1 $TIME_UTC $LONGITUDE_FLOAT $EAST_WEST $LATITUDE_FLOAT $NORTH_SOUTH
fi

TIME_UTC=${GNGGA_TIME_UTC:=$TIME_UTC}
LONGITUDE_FLOAT=${GNGGA_LONGITUDI:=$LONGITUDE_FLOAT}
EAST_WEST=${GNGGA_EAST_WEST:=$EAST_WEST}
LATITUDE_FLOAT=${GNGGA_LATITUDI:=$LATITUDE_FLOAT}
NORTH_SOUTH=${GNGGA_NORTH_SOUTH:=$NORTH_SOUTH}
echo 2 $TIME_UTC $LONGITUDE_FLOAT $EAST_WEST $LATITUDE_FLOAT $NORTH_SOUTH
#set additional varibales here
JSONDATA="{\
\"device_id\":\"$DEVICE_ID\",\
\"model\":\"$MODEL\",\
\"arch\":\"$ARCH\",\
\"firmware_version\":\"$FW_VERSION\",\
\"uptime\":\"$UPTIME\",\
\"ip_address\":\"$IP_ADDR\",\
\"mac_address\":\"$MAC_ADDR\",\
\"time_utc\":\"$TIME_UTC\",\
\"latitude\":\"$LATITUDE_FLOAT\",\
\"north/south\":\"$NORTH_SOUTH\",\
\"longitude\":\"$LONGITUDE_FLOAT\",\
\"east/west\":\"$EAST_WEST\",\
\"data_percentBat\":90,\
\"data_isPower\":true\
"

# Associated devices for 2.4Ghz AP
MAC_ADDR_DEV_ARR=
SIGNAL_DEV_ARR=
IPv4_DEV_ARR=
IW_OUTPUT=$(iw dev phy0-ap0 station dump)
if [[ "$IW_OUTPUT" != "" ]]
then
    ReadIWOutput
fi

# Associated devices for Halow AP
IW_OUTPUT=$(iw dev wlan1.sta1 station dump)
if [[ "$IW_OUTPUT" != "" ]]
then
    ReadIWOutput
fi

if [[ "$MAC_ADDR_DEV_ARR" != "" ]]
then
    JsonFromIW "list_camera"
fi

JSONDATA="${JSONDATA}\
}"

# Remove colons from MAC address to get token
TOKEN=${MAC_ADDR//:/}
REAL_TOKEN=$(echo $TOKEN|tr 'a-z' 'A-Z')
# Show values (for debug)
echo "$JSONDATA"
echo "$JSONDATA" > $logfile
echo "IP: $IP_ADDR"
echo "TOKEN: $REAL_TOKEN"
# Send data to cloud endpoint
# Replace 'https://your-cloud-endpoint.com/api/deviceinfo' with your actual endpoint  
# Send data to cloud endpoint
if [ $IOT_CLOUD_FLAG == 1 ]; then
CLOUD_URL="https://$IOT_CLOUD_URL/api/device/telemetry/noauth/$REAL_TOKEN"
else
CLOUD_URL="http://$IOT_LOCAL_URL:8080/device/telemetry/noauth/$REAL_TOKEN"
fi

curl --insecure "$CLOUD_URL" \
  --header 'Content-Type: application/json' \
  --data "$JSONDATA"

# Check if the curl command was successful
if [ $? -eq 0 ]; then
  echo "Data sent successfully."
else
  echo "Failed to send data."
fi

# crontab
# * * * * * /bin/bash /path/to/curlsenddata.sh
# 1 * * * * /bin/bash /path/to/curlsenddata.sh wlan0

# *    *    *    *    *  command to be executed
# ┬    ┬    ┬    ┬    ┬
# │    │    │    │    │
# │    │    │    │    │
# │    │    │    │    └───── day of week (0 - 7) (0 or 7 are Sunday, or use names)
# │    │    │    └────────── month (1 - 12)
# │    │    └─────────────── day of month (1 - 31)
# │    └──────────────────── hour (0 - 23)
# └───────────────────────── min (0 - 59)

