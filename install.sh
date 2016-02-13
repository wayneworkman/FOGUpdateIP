#---- Set variables ----#

currentDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
utilsDir=/opt/fog/utils
targetDir=/opt/fog/utils/FOGUpdateIP
fogsettings=/opt/fog/.fogsettings
packages="$(grep 'packages=' $fogsettings | cut -d \' -f2 )"

#---- Check if FOG is installed ----#

if [[ ! -f $fogsettings ]]; then
        echo /opt/fog/.fogsettings file not found.
        echo Please install FOG first.
        exit
fi


#---- Create directory and copy files ----#

#Correcting for FOG sourceforge revision 4580 where the utils directory is no longer created.
if [[ ! -d $utilsDir ]]; then
	mkdir $utilsDir
fi	


#If the target directory already exists, delete it. Then remake it.
if [[ -d $targetDir ]]; then
	rm -rf $targetDir
fi
mkdir $targetDir

cp $currentDir/README $targetDir/README
cp $currentDir/license.txt $targetDir/license.txt
cp $currentDir/MainScript.sh $targetDir/FOGUpdateIP.sh

#---- Add this system's $PATH contents to main script ----#

echo " " | cat - $targetDir/FOGUpdateIP.sh > $targetDir/temp && mv $targetDir/temp $targetDir/FOGUpdateIP.sh
echo myPATHS=$PATH | cat - $targetDir/FOGUpdateIP.sh > $targetDir/temp && mv $targetDir/temp $targetDir/FOGUpdateIP.sh
echo '#Below is this systems PATH variable set as myPATHS' | cat - $targetDir/FOGUpdateIP.sh > $targetDir/temp && mv $targetDir/temp $targetDir/FOGUpdateIP.sh

#make the main script executable.
chmod +x $targetDir/FOGUpdateIP.sh

#---- Add dnsmasq to packages list & Install dnsmasq ----#

#Note this mearly makes sure it's installed and gets updated along with everything else.
#If the dodnsmasq setting located in .fogsettings is not set to 1, then dnsmasq is never activated.


#if dnsmasq is not in the packages list, add it.
if ! [[ $packages == *"dnsmasq"* ]]; then
	sed -i -e 's/packages=" /packages=" dnsmasq /g' $fogsettings
fi

yum install dnsmasq -y >/dev/null 2>&1

#---- Create the cron event ----#

crontab -l -u root | grep -v FOGUpdateIP.sh | crontab -u root -
# */3 for every three minutes.
newline="*/3 * * * * $targetDir/FOGUpdateIP.sh"
(crontab -l -u root; echo "$newline") | crontab -

