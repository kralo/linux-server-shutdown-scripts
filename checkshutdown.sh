#!/bin/bash
#
#set -x

##-- this file lives in /usr/local/sbin/

. /etc/autoshutdown.conf
NETWORKFILE="/var/spool/shutdown_networkcounter"
logit()
{
	logger -p local0.notice -s -- AutoShutdown: $*
}

IsOnline()
{
        for i in $*; do
		ping $i -c1
		if [ "$?" == "0" ]; then
		  logit PC $i is still active, auto shutdown terminated
		  return 1
		fi
        done

	return 0
}

IsRunning()
{
        for i in $*; do
		if [ `pgrep -c $i` -gt 0 ] ; then
		  logit $i still active, auto shutdown terminated
                  return 1
                fi
        done

        return 0
}

IsDamonActive()
{
        for i in $*; do
                if [ `pgrep -c $i` -gt 1 ] ; then
                  logit $i still active, auto shutdown terminated
                  return 1
                fi
        done

        return 0
}

IsNetworkActivity()
{
#first, delete if file is older than 21minutes, then it may remain from an old reboot!
#careful, you might need to modify this as you increase your checkscript-each-Xminutes-cron
find $NETWORKFILE -cmin +22 -exec rm -v {} \;

touch $NETWORKFILE
#with the help of: http://murga-linux.com/puppy/viewtopic.php?t=36109
#$NETWORKFILE

#get the old rx (if possible)
OLD_RX=`tail -n 1 $NETWORKFILE | grep -o -e '[0-9]*'`
T_RX=`expr $OLD_RX + 300`

RX=`/sbin/ifconfig eth0 | grep -m 1 RX | cut -d: -f2 | sed 's/ //g' | sed 's/errors//g'`
#add 1000 bytes;If a new RX measurement later, is less than this, some real network activity would have occurred
#echo "Threshold RX: " $T_RX >> $NETWORKFILE
echo "Current RX: " $RX >> $NETWORKFILE

echo $RX
echo $T_RX
if [ $RX -gt $T_RX ] ; then
NETWORK_CHK=0
logit " NEW_RX > threshold, a network user exists. "
return 1
else
NETWORK_CHK=1
logit " NEW_RX < threshold, no network activity. "
return 0
fi 



}
IsBusy()
{
	IsNetworkActivity
        if [ "$?" == "1" ]; then
                return 1
        fi

	# Samba
	if [ "x$SAMBANETWORK" != "x" ]; then
		if [ `/usr/bin/smbstatus -b | grep $SAMBANETWORK | wc -l ` != "0" ]; then
		  logit samba connected, auto shutdown terminated
	  	  return 1
		fi
	fi

	#damons that always have one process running
	IsDamonActive $DAMONS
        if [ "$?" == "1" ]; then
                return 1
        fi

	#backuppc, wget, wsus, ....
        IsRunning $APPLICATIONS
	if [ "$?" == "1" ]; then
                return 1
        fi

	# Read logged users
	USERCOUNT=`who | wc -l`;
	# No Shutdown if there are any users logged in
	test $USERCOUNT -gt 0 && { logit some users still connected, auto shutdown terminated; return 1; }

        IsOnline $CLIENTS
        if [ "$?" == "1" ]; then
                return 1
        fi

	return 0
}

COUNTFILE="/var/spool/shutdown_counter"
OFFFILE="/var/spool/shutdown_off"

# turns off the auto shutdown
if [ -e $OFFFILE ]; then
	logit auto shutdown is turned off by existents of $OFFFILE
	exit 0
fi

if [ "$AUTO_SHUTDOWN" = "true" ] || [ "$AUTO_SHUTDOWN" = "yes" ] ; then 
	IsBusy
	if [ "$?" == "0" ]; then
		# was it not busy already last time? Then shutdown.
		if [ -e $COUNTFILE ]; then
	        	# shutdown
	        	rm -f $COUNTFILE
		        logit auto shutdown caused by cron
        		/sbin/shutdown -P now
		        exit 0
		else
			# shut down next time
			touch $COUNTFILE
			logit marked for shutdown in next try
			exit 0
		fi
	else
		rm -f $COUNTFILE
		#logit aborted
		exit 0
	fi
fi

logit malfunction
exit 1
