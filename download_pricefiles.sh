#!/bin/bash

# Download location for Zillow monthly sale price data
SALEPRICE_URL=http://files.zillowstatic.com/research/public/City/Sale_Prices_City.csv

# Make sure data directory exists; create it if needed
PARENTDIR=`dirname $0`
DATADIR=$PARENTDIR/data
[ -d $DATADIR ] || mkdir -p $DATADIR

# Change to data directory and download Zillow sale price data
cd $DATADIR
if [ -f Sale_Prices_City.csv ]
then
    mv Sale_Prices_City.csv Sale_Prices_City_old.csv
fi
wget -N $SALEPRICE_URL

if [ -f Sale_Prices_City_old.csv ]
then
    # Get a list of all Massachusetts towns contained in previous version of
    # the price file
    IFS=','
    OLD_TOWNS=(`grep Massachusetts Sale_Prices_City_old.csv | awk -F, '{printf("%s,", $2)}'`)
    for TWN in ${OLD_TOWNS[@]}
    do
        # Check to see whether the new version of the file still has price
        # data for each town, and if not, append the line from the old file
        # to the new one, so that we don't lose any data.
        NEW_TOWN=`awk -F, -v MATCH_TOWN="$TWN" '$3=="Massachusetts" && $2==MATCH_TOWN {print}' Sale_Prices_City.csv`
        if [ -z "$NEW_TOWN" ]
        then
     	    USE_TOWN=`awk -F, -v MATCH_TOWN="$TWN" '$3=="Massachusetts" && $2==MATCH_TOWN {print}' Sale_Prices_City_old.csv`
    	    echo "$USE_TOWN" >> Sale_Prices_City.csv
        fi
    done
fi