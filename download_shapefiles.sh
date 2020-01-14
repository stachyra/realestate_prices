#!/bin/bash

# Download location for townssurvey_shp data
TOWNSHAPE_URL=http://download.massgis.digital.mass.gov/shapefiles/state/townssurvey_shp.zip

# Make sure townssurvey_shp directory exists; creating it as well as parent
# data directory as needed
PARENTDIR=`dirname $0`
SHPDIR=$PARENTDIR/data/townssurvey_shp
[ -d $SHPDIR ] || mkdir -m 755 -p $SHPDIR

# Download townssurvey_shp data and unzip
cd $SHPDIR
wget $TOWNSHAPE_URL
unzip -o *.zip
rm *.zip
