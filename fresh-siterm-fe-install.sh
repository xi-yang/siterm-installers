#!/bin/sh
# Copyright 2017 California Institute of Technology
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#       http://www.apache.org/licenses/LICENSE-2.0
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
# Title 			: dtnrm
# Author			: Justas Balcas
# Email 			: justas.balcas (at) cern.ch
# @Copyright		: Copyright (C) 2016 California Institute of Technology
# Date			: 2017/09/26
# =============================================================================
##H fresh-site-fe-install.sh [OPTIONS]
##H
##H Deploy all needed stuff for dtn-rm site-fe, called sensei
##H
##H Possible options:
##H  -R DIR         ROOT directory for installation;
##H  -T DIR         TMP Directory for temporary data;
##H  -H HOST        Hostname of this node; By default uses `hostname -f` output
##H  -P PORT        Time Series database repository port. No default;
##H  -I IP          Time Series database IP or hostname. No default;
##H  -U PROTOCOL    Time Series database protocol. By default tcp
##H  -h             Display this help.

# TODO also force to specify TSDB parameters it should get from FE.
# TODO. data directory should come from configuration parameter
datadir=/data/config/
workdir=`pwd`
packages="git autoconf automake curl gcc libmnl-devel libuuid-devel lm_sensors make MySQL-python nc pkgconfig python wget python-psycopg2 PyYAML zlib-devel python-devel httpd mod_wsgi"
# Check if release is supported.
# TODO. Support other releases also.
case $(uname) in
  Linux  ) linuxmajor=$(egrep -o 'release [0-9]+{1}\.' /etc/redhat-release|cut -d" " -f2|tr -d .)
           case $linuxmajor in
             6 ) arch=slc6_amd64_gcc481 ;;
             7 ) arch=slc7_amd64_gcc630 ;;
           esac
           xargsr="xargs -r"
           ;;
  *      ) echo "unsupported architecture" 1>&2; exit 1 ;;
esac

while [ $# -ge 1 ]; do
  case $1 in
    -R ) rootdir="$2"; shift; shift ;;
    -T ) tmpdir="$2"; shift; shift;;
    -N ) netdatarelease="$2"; shift; shift;;
    -H ) hostname="$2"; shift; shift;;
    -P ) tsdport="$2"; shift; shift;;
    -I ) tsdip="$2"; shift; shift;;
    -U ) tsdp="$2"; shift; shift;;
    -h ) perl -ne '/^##H/ && do { s/^##H ?//; print }' < $0 1>&2; exit 1 ;;
    -* ) echo "$0: unrecognized option $1, use -h for help" 1>&2; exit 1 ;;
    *  ) break ;;
  esac
done

# =======================================================================
# Do all checks and if all needed parameters are specified.
if [ X"$rootdir" = X ]; then
  echo "Usage: fresh-site-fe-install.sh [OPTIONS] (use -h for help)" 1>&2
  exit 1
fi

if [ X"$tmpdir" = X ]; then
    tmpdir=/tmp/foo/
fi

if [ X"$netdatarelease" = X ]; then
    netdatarelease=1.8.0
fi

if [ X"$hostname" = X ]; then
    hostname=`hostname -f`
fi

HISTORYDB=true
if [ X"$tsdport" = X ]; then
  echo "WARNING: Repository port is not specified." 1>&2
  HISTORYDB=false
fi

if [ X"$tsdp" = X ]; then
  tsdp=tcp
fi

if [ X"$tsdip" = X ]; then
  echo "WARNING: Repository ip is not specified." 1>&2
  HISTORYDB=false
fi

# =======================================================================
# Checking if running as root
echo '==================================================================='
echo 'Checking if running as root'
if [[ $(id -u) -ne 0 ]] ; then echo "Please run this script as root" ; exit 1 ; fi

# =======================================================================
# Installing packages.
echo '==================================================================='
echo 'Installing required packages through yum.'
echo "Packages: $packages"
yum install -y epel-release
yum install -y $packages

echo 'Installing and upgrading pip.'
wget https://bootstrap.pypa.io/get-pip.py
python get-pip.py

# Make sure root directory is there
[ -d $rootdir ] || mkdir -p $rootdir || exit $?
# Also make a tmp directory
[ -d $tmpdir ] || mkdir -p $tmpdir || exit $?

echo "==================================================================="
echo "Installing netdata release $netdatarelease"
# Receive netdata release and also untar it
rm -rf $tmpdir/netdata-$netdatarelease
cd $tmpdir
[ -f netdata-$netdatarelease.tar.gz ] || wget https://github.com/firehol/netdata/releases/download/v$netdatarelease/netdata-$netdatarelease.tar.gz || exit $?
tar -xf netdata-$netdatarelease.tar.gz -C $tmpdir || exit $?
cd $tmpdir/netdata-$netdatarelease
./netdata-installer.sh --dont-wait --install $rootdir || exit $?
cd ..
rm -rf $tmpdir/netdata-$netdatarelease
# Append few configs so that netdata consumes less memory
echo 1 >/sys/kernel/mm/ksm/run
echo 1000 >/sys/kernel/mm/ksm/sleep_millisecs

echo "==================================================================="
echo "We need latest setuptools to be able to install dtnrm package. Updating setuptools"
pip install --upgrade setuptools

echo "==================================================================="
echo "Cloning dtnrm and installing it"
# TODO should be versioned same as netdata
cd $workdir
python setup-site-fe.py install || exit $?

echo "==================================================================="
if [ "$HISTORYDB" = true ] ; then
  echo "Copying netdata configuration file and modifying it"
  netdataconf=$rootdir/netdata/etc/netdata/netdata.conf
  if [ -f $netdataconf ]; then
    echo "Current config file:"
    cat $netdataconf
    echo ""
    echo "-------------------------------------------------------------------"
  fi
  if [ -f packaging/netdata.conf ]; then
    echo "Overwriting with temporary config file:"
    cat packaging/netdata.conf
    cp packaging/netdata.conf $netdataconf
    echo ""
    echo "-------------------------------------------------------------------"
  fi
  perl -pi -e "s/##HOSTNAME##/$hostname/g" $netdataconf
  perl -pi -e "s/##REPOPORT##/$tsdport/g" $netdataconf
  perl -pi -e "s/##REPOIP##/$tsdip/g" $netdataconf
  perl -pi -e "s/##REPOPROT##/$tsdp/g" $netdataconf
  echo "Final configuration file:"
  cat $netdataconf
  echo ""
  echo "-------------------------------------------------------------------"
  echo "==================================================================="
  echo "Modifying ownership and permission rules for Site FE directories"
  echo "-------------------------------------------------------------------"
else
  echo "WARNING: Netdata configuration was not modified. you will have to do it by hand."
  echo "-------------------------------------------------------------------"
fi

# Ownership
echo "1. Making apache as owner of $datadir"
chown apache:apache -R $datadir
cd $datadir
# File permissions, recursive
echo "2. Recursive file permissions to 0644 in $datadir"
find . -type f -exec chmod 0644 {} \;
 # Dir permissions, recursive
echo "3. Recursive directory permissions to 0755 in $datadir"
find . -type d -exec chmod 0755 {} \;
# SELinux serve files off Apache, resursive
echo "4. Apply SELinux rule to allow Apache serve files from $datadir"
chcon -t httpd_sys_content_t $datadir -R
# Allow write only to specific dirs
chcon -t httpd_sys_rw_content_t $datadir -R
chcon -t httpd_sys_rw_content_t /data/www/html/sites/mysite/uploads -R
echo "5. Applying mod_proxy policy change so that it can write remotely."
echo "   More details: http://sysadminsjourney.com/content/2010/02/01/apache-modproxy-error-13permission-denied-error-rhel/"
/usr/sbin/setsebool -P httpd_can_network_connect 1

echo "==================================================================="
echo "==================================================================="
echo "==================================================================="
echo "                       INSTALLATION DONE                           "
echo "==================================================================="
echo "Please check the following things:"
echo "   1. Configuration changes:"
echo "        a) /etc/dtnrm-site-fe.conf file and that all parameters are correct"
echo "        b) /etc/dtnrm-site-fe-switches.conf file and that all paraemeters are correct"
echo "   2. $netdataconf file and that all backend parameters are correct"
echo "      It should report only to sense-service graphite listener. NOT to sense-dtn"
echo "   3. Start httpd service"
echo "   4. Execute all services and see if they work (While it is fresh install, just see if there is no obvious errors):"
echo "        b) ContinuousLoop-update: MRML template preparation about all DTNs and Switches. "
echo "        d) PolicyService: That deltas are accepted and it works"
echo "   5. Make sure firewalld is not running or open port 80/tcp"
exit 0
