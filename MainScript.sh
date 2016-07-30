# Variable definitions
## Custom configuration stuff
[[ -z $fogsettings ]] && fogsettings="/opt/fog/.fogsettings"
[[ -z $customfogsettings ]] && customfogsettings="/opt/fog/.fogsettings"
## Log to write information to
[[ -z $log ]] && log="/opt/fog/log/FOGUpdateIP.log"
## Storage Node Name
[[ -z $storageNode ]] && storageNode="DefaultMember"
[[ -z $database ]] && database="fog"
[[ -z $tftpfile ]] && tftpfile="/tftpboot/default.ipxe"

#---- Set Required Command Paths ----#
grep=$(command -v grep)
awk=$(command -v awk)
cut=$(command -v cut)
sed=$(command -v sed)
mysql=$(command -v mysql)
cp=$(command -v cp)
echo=$(command -v echo)
mv=$(command -v mv)
rm=$(command -v rm)
date=$(command -v date)

#---- Set non-required command paths ----#
ip=$(command -v ip)
systemctl=$(command -v systemctl)

# Function simply checks if the variable is defined.
# Parameter 1 is the variable to check is set.
# Parameter 2 is the message of what couldn't be found.
# Parameter 3 is the log to send information to.
checkCommand() {
    local cmd="$1"
    local msg="$2"
    local log="$3"
    if [[ -z $cmd ]]; then
        echo "The path for $msg was not found, exiting" >> $log
        exit 1
    fi
}

#---- Check command variables required ----#
checkCommand "$grep" "grep" "$log"
checkCommand "$awk" "awk" "$log"
checkCommand "$ip" "ip" "$log"
checkCommand "$sed" "sed" "$log"
checkCommand "$mysql" "mysql" "$log"
checkCommand "$cp" "cp" "$log"
checkCommand "$echo" "echo" "$log"
checkCommand "$mv" "mv" "$log"
checkCommand "$date" "date" "$log"

#Record the date.
NOW=$($date '+%d/%m/%Y %H:%M:%S')
$echo -------------------- >> $log
$echo $NOW >> $log
$echo -------------------- >> $log

# Function checks if file is present.
# Parameter 1 is the file to check for
# Parameter 2 is the log to write to
checkFilePresence() {
    local file="$1"
    local log="$2"
    if [[ ! -f $file ]]; then
        $echo "The file $file does not exist, exiting" >> $log
        exit 2
    fi
}

# Check fogsettings existence
checkFilePresence "$fogsettings" "$log"
checkFilePresence "$tftpfile" "$log"

# Function checks if the variables needed are set
# Parameter 1 is the variable to test
# Parameter 2 is what the variable is testing for (msg string)
# Parameter 3 is the config file (msg string)
# Parameter 4 is the log file to write to
checkFogSettingVars() {
    local var="$1"
    local msg="$2"
    local cfg="$3"
    local log="$4"
    if [[ -z $var ]]; then
        echo "The $msg setting inside $cfg is not set, cannot continue, exiting" >> $log
        exit 3
    fi
}
. $fogsettings

# Check our required checks first
checkFogSettingVars "$interface" "interface" "$fogsettings" "$log"
checkFogSettingVars "$ipaddress" "ipaddress" "$fogsettings" "$log"

#---- Wait for an IP address ----#
while [[ -z $IP ]]; do
    ip=$($ip -4 addr show $interface | awk -F'[ /]+' '/global/ {print $3}')
    [[ -n $ip ]] && break
    $echo "The IP Address for $interface was not found, waiting 5 seconds to test again" >> $log
    sleep 5
done

# If the IP from fogsettings doesn't match what the system returned #
#    Make the change so system can still function #
if [[ $ip != $ipaddress ]]; then
    #---- Update the IP Setting ----#
    $echo "The IP Address for $interface does not match the ipaddress setting in $fogsettings, updating the IP Settings server-wide." >> $log
    statement1="UPDATE \`globalSettings\` SET \`settingValue\`='$ip' WHERE \`settingKey\` IN ('FOG_TFTP_HOST','FOG_WOL_HOST','FOG_WEB_HOST');"
    statement2="UPDATE \`nfsGroupMembers\` SET \`ngmHostname\`='$ip' WHERE \'ngmMemberName\`='$storageNode' OR \'ngmHostname\`='$ipaddress';"
	sqlStatements="$statement1$statement2"

    # Builds proper SQL Statement and runs.
    # If no user defined, assume root
    [[ -z $snmysqluser ]] && $snmysqluser='root'
    # If no host defined, assume localhost/127.0.0.1
    [[ -z $snmysqlhost ]] && $snmysqlhost='127.0.0.1'
    # No password set, run statement without pass authentication
    if [[ -z $snmysqlpass ]]; then
        $echo "A password was not set in $fogsettings for mysql use" >> $log
        $mysql -u"$snmysqluser" -e "$sqlStatements" "$database" 2>> $log
    # Else run with password authentication
    else
        $echo "A password was set in $fogsettings for mysql use" >> $log
        $mysql -u"$snmysqluser" -p"${snmysqlpass}" -e "$sqlStatements" "$database" 2>> $log
    fi

	#---- Update IP address in file default.ipxe ----#
	$echo "Updating the IP in $tftpfile" >> $log
	$sed -i "s|http://\([^/]\+\)/|http://$ip/|" $tftpfile
	$sed -i "s|http:///|http://$ip/|" $tfptfile

    #---- Check docroot and webroot is set ----#
    checkFogSettingVars "$docroot" "docroot" "$fogsettings" "$log"
    checkFogSettingVars "$webroot" "docroot" "$fogsettings" "$log"

    #---- Set config file location and check----#
    configfile="${docroot}${webroot}lib/fog/config.class.php"
    checkFilePresence "$configfile" "$log"

	#---- Backup config.class.php ----#
    $echo "Backing up $configfile" >> $log
    $cp -f "$configfile" "${configfile}.old"

    #---- Update IP in config.class.php ----#
    $echo "Updating the IP inside $configfile" >> $log
    $sed -i "s|\".*\..*\..*\..*\"|\$_SERVER['SERVER_ADDR']|" $configfile

	#---- Update .fogsettings IP ----#
    $echo "Updating the ipaddress field inside of $fogsettings" >> $log
    $sed -i "s|ipaddress='.*'|ipaddress='$ip'|g" $fogsettings

	# check if customfogsettings exists, if not, create it.
	if [[ ! -f $customfogsettings ]]; then
		$echo $customfogsettings was not found, creating it. >> $log
		touch $customfogsettings
	fi

    checkFilePresence "$customfogsettings" "$log"

    # Source custom fogsettings
    . $customfogsettings
    if [[ -z $dodnsmasq ]]; then
        $echo "The dodnsmasq setting was not found in $customfogsettings, adding it." >> $log
        # Add dodnsmasq setting
        $echo "dodnsmasq='1'" >> $customfogsettings
    fi
    if [[ -z $bldnsmasq ]]; then
        $cho "The bldnsmasq setting was not found in $customfogsettings, adding it." >> $log
        # Add bldnsmasq
		$echo "bldnsmasq='1'" >> $customfogsettings
	fi
    # Resource both settings files
    . $fogsettings
    . $customfogsettings

    # Verify dodnsmasq and bldnsmasq are indeed set
    checkFogSettingVars "$dodnsmasq" 'dodnsmasq' "$fogsettings or $customfogsettings" "$log"
    checkFogSettingVars "$bldnsmasq" 'bldnsmasq' "$fogsettings or $customfogsettings" "$log"

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
		$echo pxe-prompt="Press F8 for boot menu", 60 >> $ltsp
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
