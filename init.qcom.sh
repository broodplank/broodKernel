#!/system/bin/sh

# Mounts
mount -o noatime,remount,rw,discard,barrier=0,commit=60,noauto_da_alloc,delalloc,nosuid,nodev,nodiratime /cache /cache
mount -o noatime,remount,rw,discard,barrier=0,commit=60,noauto_da_alloc,delalloc,nosuid,nodev,nodiratime /data /data
mount -o noatime,remount,rw,discard,barrier=0,commit=60,noauto_da_alloc,delalloc,nosuid,nodev,nodiratime /persist /persist

# Remount all partitions with noatime
for k in $(busybox mount | grep relatime | cut -d " " -f3);
do
busybox mount -o remount,noatime $k;
done;

# Kerneltweaks
mount -t debugfs none /sys/kernel/debug
echo NO_NORMALIZED_SLEEPER > /sys/kernel/debug/sched_features
unmount /sys/kernel/debug

# Touchscreen Tweaks
echo 7035 > /sys/class/touch/switch/set_touchscreen;
echo 8002 > /sys/class/touch/switch/set_touchscreen;
echo 11000 > /sys/class/touch/switch/set_touchscreen;
echo 13060 > /sys/class/touch/switch/set_touchscreen;
echo 14005 > /sys/class/touch/switch/set_touchscreen;

# Other Tweaks
setprop windowsmgr.max_events_per_sec 60; 
setprop ro.telephony.call_ring.delay 1000;
setprop debug.sf.hw 1;
setprop video.accelerate.hw 1;
setprop debug.performance.tuning 1;

# IPv4 Tweaks
echo "4096 32768 65536" > /sys/proc/net/ipv4/tcp_rmem;
echo "4096 32768 65536" > /sys/proc/net/ipv4/tcp_wmem;

# Drop caches
sync;
echo 3 > /proc/sys/vm/drop_caches;
sleep 1;
echo 0 > /proc/sys/vm/drop_caches;
echo "Caches are dropped!";

# Optimize Non-Rotational Readahead (Thunderbolt)
MMC=`ls -d /sys/block/mmc*`;

# Optimize non-rotating storage; 
for i in $STL $BML $MMC $ZRM $MTD;
do
	#IMPORTANT!
	if [ -e $i/queue/rotational ]; 
	then
		echo 0 > $i/queue/rotational; 
	fi;
	if [ -e $i/queue/nr_requests ];
	then
		echo 1024 > $i/queue/nr_requests; # for starters: keep it sane
	fi;
	#CFQ specific
	if [ -e $i/queue/iosched/back_seek_penalty ];
	then 
		echo 1 > $i/queue/iosched/back_seek_penalty;
	fi;
	#CFQ specific
	if [ -e $i/queue/iosched/low_latency ];
	then
		echo 1 > $i/queue/iosched/low_latency;
	fi;
	#CFQ Specific
	if [ -e $i/queue/iosched/slice_idle ];
	then 
		echo 1 > $i/queue/iosched/slice_idle; # previous: 1
	fi;
	#CFQ specific
	if [ -e $i/queue/iosched/quantum ];
	then
		echo 8 > $i/queue/iosched/quantum;
	fi;
#disable iostats to reduce overhead  # idea by kodos96 - thanks !
	if [ -e $i/queue/iostats ];
	then
		echo "0" > $i/queue/iostats;
	fi;
# Optimize for read- & write-throughput; 
# Optimize for readahead; 
	if [ -e $i/queue/read_ahead_kb ];
	then
		echo "256" >  $i/queue/read_ahead_kb;
	fi;
done;
# Specifically for NAND devices where reads are faster than writes, writes starved 2:1 is good
for i in $STL $BML $ZRM $MTD;
do
	if [ -e $i/queue/iosched/writes_starved ];
	then
		echo 2 > $i/queue/iosched/writes_starved;
	fi;
done;

# Optimize SQlite databases of apps
echo "";
echo "*********************************************";
echo "Optimizing and defragging your database files (*.db)";
echo "Ignore the 'database disk image is malformed' error";
echo "Ignore the 'no such collation sequence' error";
echo "*********************************************";
echo "";

for i in \
`busybox find /data -iname "*.db"`; 
do \
	/system/xbin/sqlite3 $i 'VACUUM;';
	/system/xbin/sqlite3 $i 'REINDEX;';
done;

if [ -d "/dbdata" ]; then
	for i in \
	`busybox find /dbdata -iname "*.db"`; 
	do \
		/system/xbin/sqlite3 $i 'VACUUM;';
		/system/xbin/sqlite3 $i 'REINDEX;';
	done;
fi;


if [ -d "/datadata" ]; then
	for i in \
	`busybox find /datadata -iname "*.db"`; 
	do \
		/system/xbin/sqlite3 $i 'VACUUM;';
		/system/xbin/sqlite3 $i 'REINDEX;';
	done;
fi;


for i in \
`busybox find /sdcard -iname "*.db"`; 
do \
	/system/xbin/sqlite3 $i 'VACUUM;';
	/system/xbin/sqlite3 $i 'REINDEX;';
done;

# Automatic ZipAlign by Wes Garner
# ZipAlign files in /data that have not been previously ZipAligned (using md5sum)
# Thanks to oknowton for the changes
# Credits to doctorcete system/app and /system/framework 

LOG_FILE=/data/broodkernel-zipalign.log

if [ -n $zipalign ] && [ $zipalign = "true" ];
  then
    busybox mount -o remount,rw /;
    busybox mount -o remount,rw -t auto /system;
    busybox mount -o remount,rw -t auto /data;
fi;
busybox mount -t tmpfs -o size=70m none /mnt/tmp;
echo "Starting broodKernel Automatic ZipAlign " `date` | tee -a $LOG_FILE;

    if [ -e $LOG_FILE ]; then
    	rm $LOG_FILE;
    fi;
    	
echo "Starting Automatic ZipAlign $( date +"%m-%d-%Y %H:%M:%S" )" | tee -a $LOG_FILE;
    for apk in /data/app/*.apk ; do
	zipalign -c 4 $apk;
	ZIPCHECK=$?;
	if [ $ZIPCHECK -eq 1 ]; then
		echo ZipAligning $(basename $apk)  | tee -a $LOG_FILE;
		zipalign -f 4 $apk /cache/$(basename $apk);
			if [ -e /cache/$(basename $apk) ]; then
				cp -f -p /cache/$(basename $apk) $apk  | tee -a $LOG_FILE;
				rm /cache/$(basename $apk);
			else
				echo ZipAligning $(basename $apk) Failed  | tee -a $LOG_FILE;
			fi;
	else
		echo ZipAlign already completed on $apk  | tee -a $LOG_FILE;
	fi;
       done;

  for apk in /system/app/*.apk ; do
	zipalign -c 4 $apk;
	ZIPCHECK=$?;
	if [ $ZIPCHECK -eq 1 ]; then
		echo ZipAligning $(basename $apk)  | tee -a $LOG_FILE;
		zipalign -f 4 $apk /cache/$(basename $apk);
			if [ -e /cache/$(basename $apk) ]; then
				cp -f -p /cache/$(basename $apk) $apk  | tee -a $LOG_FILE;
				rm /cache/$(basename $apk);
			else
				echo ZipAligning $(basename $apk) Failed  | tee -a $LOG_FILE;
			fi;
	else
		echo ZipAlign already completed on $apk  | tee -a $LOG_FILE;
	fi;
       done;

  for apk in /system/framework/*.apk ; do
	zipalign -c 4 $apk;
	ZIPCHECK=$?;
	if [ $ZIPCHECK -eq 1 ]; then
		echo ZipAligning $(basename $apk)  | tee -a $LOG_FILE;
		zipalign -f 4 $apk /cache/$(basename $apk);
			if [ -e /cache/$(basename $apk) ]; then
				cp -f -p /cache/$(basename $apk) $apk  | tee -a $LOG_FILE;
				rm /cache/$(basename $apk);
			else
				echo ZipAligning $(basename $apk) Failed  | tee -a $LOG_FILE;
			fi;
	else
		echo ZipAlign already completed on $apk  | tee -a $LOG_FILE;
	fi;
       done;

echo "Automatic ZipAlign finished at $( date +"%m-%d-%Y %H:%M:%S" )" | tee -a $LOG_FILE;



if [ -e "/system/etc/init.d/01screenstatescaling" ]; then
   su -c "chmod 777 /system/etc/init.d/01screenstatescaling"
fi;	



# start ril-daemon only for targets on which radio is present
#
baseband=`getprop ro.baseband`
netmgr=`getprop ro.use_data_netmgrd`

case "$baseband" in
    "msm" | "csfb" | "svlte2a" | "unknown")
    start ril-daemon
    start qmuxd
    case "$netmgr" in
        "true" | "True" | "TRUE")
        start netmgrd
    esac
esac

#
# Allow unique persistent serial numbers for devices connected via usb
# User needs to set unique usb serial number to persist.usb.serialno
#
serialno=`getprop persist.usb.serialno`
case "$serialno" in
    "") ;; #Do nothing here
    * )
    mount -t debugfs none /sys/kernel/debug
    echo "$serialno" > /sys/kernel/debug/android/serial_number
esac

#
# Allow persistent usb charging disabling
# User needs to set usb charging disabled in persist.usb.chgdisabled
#
target=`getprop ro.product.device`
usbchgdisabled=`getprop persist.usb.chgdisabled`
case "$usbchgdisabled" in
    "") ;; #Do nothing here
    * )
    case $target in
        "msm8660_surf" | "msm8660_csfb")
        echo "$usbchgdisabled" > /sys/module/pmic8058_charger/parameters/disabled
    esac
esac

case "$target" in
    "msm7630_surf" | "msm7630_1x" | "msm7630_fusion")
        insmod /system/lib/modules/ss_mfcinit.ko
        insmod /system/lib/modules/ss_vencoder.ko
        insmod /system/lib/modules/ss_vdecoder.ko
        chmod 0666 /dev/ss_mfc_reg
        chmod 0666 /dev/ss_vdec
        chmod 0666 /dev/ss_venc

        case "$target" in
        "msm7630_fusion")
        start gpsone_daemon
        esac

        value=`cat /sys/devices/system/soc/soc0/hw_platform`

        case "$value" in
            "FFA" | "SVLTE_FFA")
             # linking to surf_keypad_qwerty.kcm.bin instead of surf_keypad_numeric.kcm.bin so that
             # the UI keyboard works fine.
             ln -s  /system/usr/keychars/surf_keypad_qwerty.kcm.bin /system/usr/keychars/surf_keypad.kcm.bin;;
            "Fluid")
             setprop ro.sf.lcd_density 240
             setprop qcom.bt.dev_power_class 2
             /system/bin/profiler_daemon&;;
            *)
             ln -s  /system/usr/keychars/surf_keypad_qwerty.kcm.bin /system/usr/keychars/surf_keypad.kcm.bin;;
        esac

# Dynamic Memory Managment (DMM) provides a sys file system to the userspace
# that can be used to plug in/out memory that has been configured as unstable.
# This unstable memory can be in Active or In-Active State.
# Each of which the userspace can request by writing to a sys file.

# ro.dev.dmm = 1; Indicates that DMM is enabled in the Android User Space. This
# property is set in the Android system properties file.

# ro.dev.dmm.dpd.start_address is set when the target has a 2x256Mb memory
# configuration. This is also used to indicate that the target is capable of
# setting EBI-1 to Deep Power Down or Self Refresh.

        mem="/sys/devices/system/memory"
        op=`cat $mem/movable_start_bytes`
        case "$op" in
           "0" )
                log -p i -t DMM DMM Disabled. movable_start_bytes not set: $op
            ;;

            "$mem/movable_start_bytes: No such file or directory " )
                log -p i -t DMM DMM Disabled. movable_start_bytes does not exist: $op
            ;;

            * )
                log -p i -t DMM DMM available. movable_start_bytes at $op
                movable_start_bytes=0x`cat $mem/movable_start_bytes`
                block_size_bytes=0x`cat $mem/block_size_bytes`
                block=$(($movable_start_bytes/$block_size_bytes))

                echo $movable_start_bytes > $mem/probe
                case "$?" in
                    "0" )
                        log -p i -t DMM $movable_start_bytes to physical hotplug succeeded.
                    ;;
                    * )
                        log -p e -t DMM $movable_start_bytes to physical hotplug failed.
                        return 1
                    ;;
                esac

               chown system system $mem/memory$block/state

                echo online > $mem/memory$block/state
                case "$?" in
                    "0" )
                        log -p i -t DMM \'echo online\' to logical hotplug succeeded.
                    ;;
                    * )
                        log -p e -t DMM \'echo online\' to logical hotplug failed.
                        return 1
                    ;;
                esac

                setprop ro.dev.dmm.dpd.start_address $movable_start_bytes
                setprop ro.dev.dmm.dpd.block $block
            ;;
        esac

        op=`cat $mem/low_power_memory_start_bytes`
        case "$op" in
            "0" )
                log -p i -t DMM Self-Refresh-Only Disabled. low_power_memory_start_bytes not set:$op
            ;;

            "$mem/low_power_memory_start_bytes No such file or directory " )
                log -p i -t DMM Self-Refresh-Only Disabled. low_power_memory_start_bytes does not exist:$op
            ;;

            * )
                log -p i -t DMM Self-Refresh-Only available. low_power_memory_start_bytes at $op
            ;;
        esac
        ;;
    "msm8660_surf")
        platformvalue=`cat /sys/devices/system/soc/soc0/hw_platform`
        case "$platformvalue" in
         "Fluid")
         setprop ro.sf.lcd_density 240;;
         esac

esac
