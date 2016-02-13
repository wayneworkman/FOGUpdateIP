#Fog settings location.
fogsettings=/opt/fog/.fogsettings

#Custom settings location.
customfogsettings=/opt/fog/.fogsettings

#Log for this script, to store messages and such in.
log=/opt/fog/log/FOGUpdateIP.log

#This is the storage node's name that will be updated. If you have a custom name you can set it here.
storageNode=DefaultMember


#---- Set Command Paths ----#

#Store previous contents of IFS.
previousIFS=$IFS

IFS=:
  for p in $myPATHS; do
	
	#Get grep path
	if [[ -f $p/grep ]]; then
		grep=$p/grep
	fi
	
	#Get awk path
	if [[ -f $p/awk ]]; then
		awk=$p/awk
	fi
	
	#Get cut path
	if [[ -f $p/cut ]]; then
		cut=$p/cut
	fi
	
	#Get ip path
	if [[ -f $p/ip ]]; then
		ip=$p/ip
	fi

	#Get sed path
	if [[ -f $p/sed ]]; then
		sed=$p/sed
	fi

	#Get mysql path
	if [[ -f $p/mysql ]]; then
		mysql=$p/mysql
	fi

	#Get cp path
	if [[ -f $p/cp ]]; then
		cp=$p/cp
	fi

	#Get echo path
	if [[ -f $p/echo ]]; then
		echo=$p/echo
	fi
	
	#Get mv path
	if [[ -f $p/mv ]]; then
		mv=$p/mv
	fi

	#Get rm path
	if [[ -f $p/rm ]]; then
		rm=$p/rm
	fi

	#Get systemctl path
	if [[ -f $p/systemctl ]]; then
		systemctl=$p/systemctl
	fi

	#Get date path
	if [[ -f $p/date ]]; then
		date=$p/date
	fi
			
  done

#Restore previous contents of IFS
IFS=$previousIFS


#---- Check contents of command variables ----#
	
if [[ -z $echo ]]; then
	echo The path for grep was not found, exiting. >> $log
	exit
fi

if [[ -z $grep ]]; then
        $echo The path for grep was not found, exiting. >> $log
        exit
fi

if [[ -z $awk ]]; then
	$echo The path for awk was not found, exiting. >> $log
	exit
fi

if [[ -z $cut ]]; then
	$echo The path for cut was not found, exiting. >> $log
	exit
fi

if [[ -z $ip ]]; then
	$echo The path for ip was not found, exiting. >> $log
	exit
fi

if [[ -z $sed ]]; then
	$echo The path for sed was not found, exiting. >> $log
	exit
fi

if [[ -z $mysql ]]; then
	$echo The path for mysql was not found, exiting. >> $log
	exit
fi

if [[ -z $cp ]]; then
	$echo The path for cp was not found, exiting. >> $log
	exit
fi

if [[ -z $mv ]]; then
	$echo The path for mv was not found, exiting. >> $log
	exit
fi

if [[ -z $rm ]]; then
	$echo The path for rm was not found, exiting. >> $log
	exit
fi

if [[ -z $systemctl ]]; then
	$echo The path for systemctl was not found, exiting. >> $log
	exit
fi

if [[ -z $date ]]; then
	$echo The path for date was not found, exiting. >> $log
	exit
fi



#Record the date.
NOW=$($date '+%d/%m/%Y %H:%M:%S')
$echo -------------------- >> $log
$echo $NOW >> $log
$echo -------------------- >> $log



#check for .fogsettings existence, if it isn't there, exit the script.
if ! [[ -f $fogsettings ]]; then
        $echo The file $fogsettings does not exist, exiting. >> $log
        exit
fi



#---- Get interface name and last IP from .fogsettings ---#

interface="$($grep 'interface=' $fogsettings | $cut -d \' -f2 )"
fogsettingsIP="$($grep 'ipaddress=' $fogsettings | $cut -d \' -f2 )"

#Check if the interface setting is good.
if [[ -z $interface ]]; then
	$echo The interface setting inside $fogsettings either doesn't exist or isn't as expected, exiting. >> $log
	exit
fi

#Check if the ipaddress setting is good.
if [[ -z $fogsettingsIP ]]; then
	$echo The ipaddress setting inside $fogsettings either doesn't exist or isn't as expected, exiting. >> $log
	exit
fi



#---- Wait for an IP address ----#

IP=`$ip addr list ${interface} | $grep "inet " |$cut -d" " -f6|$cut -d/ -f1`

while [[ -z $IP ]]

do
	$echo The IP address for $interface was not found, waiting 5 seconds. >> $log
	sleep 5
	IP=`$ip addr list ${interface} | $grep "inet " |$cut -d" " -f6|$cut -d/ -f1`
done




if [[ "$IP" != "$fogsettingsIP" ]]; then
#If the interface IP doesn't match the .fogsettings IP, do the below.
	

	#-------------- Update the IP settings --------------#
	
	$echo The IP address for $interface does not match the ipaddress setting in $fogsettings, updating the IP Settings server-wide. >> $log

	#---- SQL ----#

	snmysqluser="$($grep 'snmysqluser=' $fogsettings | $cut -d \' -f2 )"
	snmysqlpass="$($grep 'snmysqlpass=' $fogsettings | $cut -d \' -f2 )"
	
	#These are the SQL statements to run against the DB
	statement1="UPDATE \`globalSettings\` SET \`settingValue\` = '$IP' WHERE \`settingKey\` ='FOG_TFTP_HOST';"
	statement2="UPDATE \`globalSettings\` SET \`settingValue\` = '$IP' WHERE \`settingKey\` ='FOG_WOL_HOST';"
	statement3="UPDATE \`nfsGroupMembers\` SET \`ngmHostname\` = '$IP' WHERE \`ngmMemberName\` ='$storageNode';"
	statement4="UPDATE \`globalSettings\` SET \`settingValue\` = '$IP' WHERE \`settingKey\` ='FOG_WEB_HOST';"


	#This puts all the statements into one variable. If you add more statments above, add the extra ones to this too.
	sqlStatements=$statement1$statement2$statement3$statement4
	

	#This builds the proper MySQL Connection Statement and runs it.
	if [ "$snmysqlpass" != "" ]; then
		#If there is a password set
		$echo A password was set for snmysqlpass in $fogsettings, using the password. >> $log
		$mysql --user=$snmysqluser --password=$snmysqlpass --database='fog' -e "$sqlStatements"
		
	elif [ "$snmysqluser" != "" ]; then
		#If there is a user set but no password
		$echo A username was set for snmysqluser in $fogsettings, but no password was found. Using the username. >> $log
		$mysql --user $snmysqluser --database='fog' -e "$sqlStatements"

	else
		$echo There was no username or password set for the database in $fogsettings, trying without credentials. >> $log
		#If there is no user or password set
		$mysql --database='fog' -e "$sqlStatements"
	fi
	


	#---- Update IP address in file default.ipxe ----#

	$echo Updating the IP in /tftpboot/default.ipxe >> $log
	$sed -i "s|http://\([^/]\+\)/|http://$IP/|" /tftpboot/default.ipxe
	$sed -i "s|http:///|http://$IP/|" /tftpboot/default.ipxe


	#---- Backup config.class.php and then updae IP ----#
	
	#read the docroot and webroot settings.
	docroot="$($grep 'docroot=' $fogsettings | $cut -d \' -f2 )"
	webroot="$($grep 'webroot=' $fogsettings | $cut -d \' -f2 )"


	#check if docroot is blank.
	if [[ -z $docroot ]]; then
		$echo There is no docroot set inside $fogsettings exiting the script. >> $log
		exit
	fi

	#check if webroot is blank.
	if [[ -z $webroot ]]; then
		$echo There is no webroot set inside $fogsettings exiting the script. >> $log
		exit
	fi
	


	$echo Backing up ${docroot}$webroot'lib/fog/config.class.php' >> $log
	$cp -f ${docroot}$webroot'lib/fog/config.class.php' ${docroot}$webroot'lib/fog/config.class.php.old'

	$echo Updating the IP inside ${docroot}$webroot'lib/fog/config.class.php' >> $log
	$sed -i "s|\".*\..*\..*\..*\"|\$_SERVER['SERVER_ADDR']|" ${docroot}$webroot'lib/fog/config.class.php'

	#---- Update .fogsettings IP ----#
	
	$echo Updating the ipaddress field inside of $fogsettings >> $log
        $sed -i "s|ipaddress='.*'|ipaddress='$IP'|" $fogsettings


	#check if customfogsettings exists, if not, create it.
	if [[ ! -f $customfogsettings ]]; then
		$echo $customfogsettings was not found, creating it. >> $log
		touch $customfogsettings
	fi


	#Check if the dodnsmasq setting exists in $customfogsettings If not, create it and set it to false.
	if ! $grep -q dodnsmasq "$customfogsettings"; then
		$echo The dodnsmasq setting was not found in $customfogsettings, adding it. >> $log
		#Remove any blank lines at the end of customfogsettings, then rewrite file.
		$sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' $customfogsettings > $customfogsettings.new
		$mv $customfogsettings.new $customfogsettings
		#Add dodnsmasq setting.
		$echo "dodnsmasq='0'" >> $customfogsettings
		#Add a blank line at the end of customfogsettings.
		$echo "" >> $customfogsettings
	fi
	

	#Check if the bldnsmasq setting exists in $customfogsettings. If not, create it and set it to false.
	if ! grep -q bldnsmasq "$customfogsettings"; then
		$echo The bldnsmasq setting was not found in $customfogsettings, adding it. >> $log
		#Remove any blank lines at the end of customfogsettings, then rewrite file.
                $sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' $customfogsettings > $customfogsettings.new
		$mv $customfogsettings.new $customfogsettings
                #Add bldnsmasq setting.
		$echo "bldnsmasq='1'" >> $customfogsettings
		#Add a blank line at the end of customfogsettings.
                $echo "" >> $customfogsettings
	fi

	
	#Read the dodnsmasq and bldnsmasq settings.
	dodnsmasq="$($grep 'dodnsmasq=' $fogsettings | $cut -d \' -f2 )"
	bldnsmasq="$($grep 'bldnsmasq=' $fogsettings | $cut -d \' -f2 )"

	#If either of the dnsmasq fogsettings are empty, exit the script.
	if [[ -z dodnsmasq ]]; then
		$echo The dodnsmasq setting in $customfogsettings either doesn't exist or isn't as expected, exiting the script. >> $log
		exit
	fi

	if [[ -z bldnsmasq ]]; then
		$echo The bldnsmasq setting in $customfogsettings either doesn't exist or isn't as expected, exiting the script. >> $log
		exit
	fi

	#If bldnsmasq is seto as 1, build the config file.
	if [[ "$bldnsmasq" == "1" ]]; then

		#set the ltsp.conf path.
		ltsp=/etc/dnsmasq.d/ltsp.conf

		$echo bldnsmasq inside $customfogsettings was set to 1, recreating $ltsp >> $log

		#Read what boot file is set in fogsettings, use that in ltsp.conf
		bootfilename="$($grep 'bootfilename=' $fogsettings | $cut -d \' -f2 )"

		#If bootfilename is blank, set it to undionly.kkpxe
		if [[ -z "$bootfilename" ]]; then
			$echo The bootfilename setting inside of $fogsettings is either doesn't exist or isn't as expected, defaulting to undionly.kkpxe >> $log
			bootfilename=undionly.kkpxe
		fi

		#Check for existence of the bootfile copy ".0" file. If it exists, delete it and recreate it.
		bootfileCopy="${bootfilename%.*}.0"
		if [[ -f $bootfileCopy ]]; then
			$echo $bootfileCopy was found, deleting it. >> $log
			$rm -f $bootfileCopy
		fi
		$echo Copying /tftpboot/$bootfilename to /tftpboot/$bootfileCopy for dnsmasq to use. >> $log
		$cp /tftpboot/$bootfilename /tftpboot/$bootfileCopy


		#this config overwrites anything in ltsp.conf because "bldnsmasq" was set to 1.

		$echo Recreating $ltsp for use with dnsmasq. >> $log
		$echo port=0 > $ltsp
		$echo log-dhcp >> $ltsp
		$echo tftp-root=/tftpboot >> $ltsp
		$echo dhcp-boot=$bootfileCopy,$IP,$IP >> $ltsp
		$echo dhcp-option=17,/images >> $ltsp
		$echo dhcp-option=vendor:PXEClient,6,2b >> $ltsp
		$echo dhcp-no-override >> $ltsp
		$echo pxe-prompt="Press F8 for boot menu", 1 >> $ltsp
		$echo pxe-service=X86PC, “Boot from network”, undionly >> $ltsp
		$echo pxe-service=X86PC, "Boot from local hard disk", 0 >> $ltsp
		$echo dhcp-range=$IP,proxy >> $ltsp

	fi



	#if dodnsmasq is set to 1, restart and enable dnsmasq. ELSE disable and stop.
	if [[ "$dodnsmasq" == "1" ]]; then
		$echo dodnsmasq was set to 1 inside of $customfogsettings - starting it and enabling it to run at boot. >> $log
		$echo You may manually set this to 0 if you like, and manually stop and disable dnsmasq with these commands: >> $log
		$echo systemctl disable dnsmasq >> $log
		$echo systemctl stop dnsmasq >> $log
		$systemctl enable dnsmasq
		$systemctl restart dnsmasq
	else
		$echo dodnsmasq was set to 0 inside of $customfogsettings - stopping it and disabling it from running at boot. >> $log
		$echo You may manually set this to 1 if you like, and manually start and enable dnsmasq with these commands: >> $log
		$echo systemctl enable dnsmasq >> $log
		$echo systemctl restart dnsmasq >> $log
		$systemctl disable dnsmasq
		$systemctl stop dnsmasq
		
	fi

else
	$echo The IP address found on $interface matches the IP set in $fogsettings, assuming all is good, exiting. >> $log
	exit	
fi

