#!/bin/bash
#********************************************************************
# *
# *   ctxinstall.sh
# *
# *   Copyright 1998-2016, 2016 Citrix Systems, Inc. All Rights Reserved.
# *
# *   Authors: Guoyi Zhou / Miya Zhao / Yu Xiao,  11 Oct. 2016
# * 
# *   This file performs the following actions:
# *   1. Check current site to see if it meets the condition of installing/configuring Linux VDA
# *   2. Install the packages upon which Linux VDA dependents and Linux VDA itself
# *   3. Customize site, such as Hostname, NTS, DNS etc. and join domain
# *   4. Verify the sanity of the configuration files
# *   5. Commit the installation 
# *   
# *
# *   Return value: 
# *     0 - Normally return
# *     1 - Failed on getting system information 
# *     2 - Failed on precheck phase
# *     3 - Failed on installation phase
# *     4 - Failed on configuration phase
# *     5 - Failed on verfication phase
# *     6 - Failed on commit phase
# *     7 - Failed for misc reason
# *
# *   Change History: 
# *     11 Oct. 2016    Initial version            Guoyi Zhou 
# *     09 Nov. 2016    The 1th offical version    Guoyi Zhou/Yu Xiao/Miya Zhao
# *     30 Nov. 2016    Support SUSE Distro        Guoyi Zhou/Yu Xiao/Miya Zhao
# *     15 Aug. 2017    Support pure IPv6          Qianqian Zu
# *  
# *************************************************************************/

source /var/xdl/configure_common.sh
source /var/xdl/configure_utilities.sh

#####################system commands
MV="/usr/bin/mv"
CP="/usr/bin/cp"
RM="/usr/bin/rm"
RPM="/bin/rpm"
CUT="/usr/bin/cut"
MKDIR="/usr/bin/mkdir"
UNAME="/usr/bin/uname"
UNAMEU="/bin/uname"       # command has different path in Ubuntu
TOUCH="/usr/bin/touch"
PING="/bin/ping"
NSLOOKUP="/usr/bin/nslookup"
YUM="/usr/bin/yum"
SERVICE="/usr/sbin/service"
######################Global variables
fname=$(basename $0)
scriptName=${fname%.*}  # Script name without extension
paramNum=$#
lvdaVersion="1.4"       # Linux VDA version, default value is 1.4
osPlatform=""           # OS platform,  red, centos, suse, ubuntu
osVersion=""            # OS version
osPatchVersion=""       # OS Patch version
osType=""               # legal value is workstation or server
osMajorVersion=""       # OS major versoin
pkgManagement=""        # which kind of command will be used (apt, yum)
coreFileRhel="/etc/redhat-release"  
coreFileCent="/etc/centos-release"
coreFileRocky="/etc/rocky-release"  
coreFileSuse="/etc/SuSE-release"  
coreFileUbuntu="/etc/lsb-release"
coreFilePardus="/etc/lsb-release"
coreFileOS="/etc/os-release"
kernelVersion="`uname -r`"        # Linux Kernel version, got by "uname -r"
hostName="`hostname`"             # Linux VDA host name
hostName="$(echo $hostName |cut -d'.' -f 1)"
hostNameUpper=$(echo $hostName | tr '[a-z]' '[A-Z]')
fqdn=""
realm=""
domain=""
ou=""
workgroup=""
FQDN=""
REALM=""
DOMAIN=""
WORKGROUP=""
user="`whoami`"                # current user 
domainUser=""                  # doamin user
joinDomainWay=""               # legal value is winbind/centrify/quest/sssd 
dns=""                         # DNS: ip address or string 
ntps=""                        # NTP Server
dns1=""
dns2=""
dns3=""
dns4=""
dnsNum=4

pingTimes=5                    # Define the ping times in the function pingAddress()

logFile="/var/log/${scriptName}.log"
backupDir="/var/ctxinstall"
installCfg="/tmp/ctxinstall.conf"   #Holds the configuration entry, format: <key name>=<value>, eg: workgroup=mygroup
filePath="/tmp/ctxinstall"
centrifyPath="${filePath}/Centrify"
pbisPath="${filePath}/Pbis"
isPreCheck="no"
isInstallation="no"
isConfiguration="no"
isVerfication="no"
isCommit="no"
isBackout="no"
isSilent="no"
isFinishing="no"
preCheckStatus="Success"                #Status for preCheck(Success, Error, Warning)
installationStatus="Success"            #Status for installation(Success, Error, Warning)
configurationStatus="Success"           #Status for configuration(Success, Error, Warning)
verficationStatus="Success"             #Status for verfication(Success, Error, Warning)

useIPv6="no"        # Use IPv4 or IPv6 for registration

#In order to simplify user input, some parameters are for developer only
devOnly="no"    # tag flag, yes: some parameters are invisible for end user
                #           no:  all parameters are visible for end user, default value is no

######################Variables relating to RHEL
pkgListRhel=("postgresql-server"\
             "postgresql-jdbc"\
             "redhat-lsb-core"\
             "foomatic"\
             "nautilus"\
             "nautilus-open-terminal"\
             "totem-nautilus"\
             "pulseaudio"\
             "pulseaudio-module-x11"\
             "pulseaudio-gdm-hooks"\
             "pulseaudio-module-bluetooth"\
             "alsa-plugins-pulseaudio"\
             "pciutils"\
             "openssh"\
             "openssh-clients")
#             "net-tools" \                     #pkg for tool ifconfig
#             "bind-utils" \                    #pkg for tool nslookup
#             "gdb"                             #for debug
             
pkgListRhel7=("authconfig-gtk" "chrony" "firewalld" "foomatic-filters")
pkgListRhel8=("chrony" "firewalld" "cups-filters" "authselect" "realmd")
pkgListUpdateRhel7=("java-11-openjdk")
pkgListUpdateRhel8=("java-11-openjdk")
pkgListRhelNum=${#pkgListRhel[@]}   
pkgListRhel7Num=${#pkgListRhel7[@]}
pkgListRhel8Num=${#pkgListRhel8[@]}
pkgListUpdateRhel7Num=${#pkgListUpdateRhel7[@]}
pkgListUpdateRhel8Num=${#pkgListUpdateRhel8[@]}

#Kylin
pkgListKylin=("chrony" "ntpdate" "libsasl2-2" "libgtk2.0-0")
winbindPkgListKylin=("winbind" "samba" "libnss-winbind" "libpam-winbind" "krb5-config" "krb5-locales" "krb5-user" "oddjob-mkhomedir")

pkgListUbuntu=("chrony"\
                 "ntpdate"\
                 "libsasl2-2"\
                 "libgtk2.0-0")

pkgListDebian=("chrony"\
                "ntpdate"\
                "libsasl2-2"\
                "libgtk2.0-0")             

pkgListSuse=("krb5-client" \
             "bind" \
             "postgresql-jdbc" \
             "libcap-progs")  # libcap-progs is added for supporting SSL
             
pkgListSuse11=("libecpg6" \
               "postgresql")
               
pkgListSuse12=("")
              
pkgListUpdateSuse=("java-11-openjdk")

pkgListPardus=("chrony"\
                "ntpdate"\
                "default-jdk"\
                "postgresql"\
                "libpostgresql-jdbc-java"\
                "libsasl2-2"\
                "libsasl2-modules-gssapi-mit"\
                "libldap-2.4-2"\
                "krb5-user"\
                "cups"\
                "curl"\
                "ufw"\
                "python-requests"\
                "libgoogle-perftools4")

winbindPkgList=("samba-winbind"\
                "samba-winbind-clients"\
                "krb5-workstation"\
                "authconfig"\
                "oddjob-mkhomedir")

winbindPkgListRed8=("samba-winbind"\
                "samba-winbind-clients"\
                "krb5-workstation"\
                "oddjob-mkhomedir")

winbindPkgListUbuntu=("winbind"\
                      "samba"\
                      "libnss-winbind"\
                      "libpam-winbind"\
                      "krb5-config"\
                      "krb5-locales"\
                      "krb5-user"\
                      "oddjob-mkhomedir")

winbindPkgListSuse=("samba-winbind")

sssdPkgListSuse=("sssd"\
                 "sssd-ad")

# ctxinstall.sh environment variable array
ctxInstallEnvArray=("CTX_EASYINSTALL_HOSTNAME"\
                    "CTX_EASYINSTALL_DNS"\
                    "CTX_EASYINSTALL_NTPS"\
                    "CTX_EASYINSTALL_DOMAIN"\
                    "CTX_EASYINSTALL_REALM"\
                    "CTX_EASYINSTALL_FQDN"\
                    "CTX_EASYINSTALL_ADINTEGRATIONWAY"\
                    "CTX_EASYINSTALL_USERNAME"\
                    "CTX_EASYINSTALL_PASSWORD")
ctxInstallEnvArrayNum=${#ctxInstallEnvArray[@]}
# ctxsetup.sh environment variable array
ctxSetupEnvArray=("CTX_XDL_SUPPORT_DDC_AS_CNAME"\
                  "CTX_XDL_DDC_LIST"\
                  "CTX_XDL_VDA_PORT"\
                  "CTX_XDL_TELEMETRY_SOCKET_PORT"\
                  "CTX_XDL_TELEMETRY_PORT"\
                  "CTX_XDL_REGISTER_SERVICE"\
                  "CTX_XDL_ADD_FIREWALL_RULES"\
                  "CTX_XDL_HDX_3D_PRO"\
                  "CTX_XDL_VDI_MODE"\
                  "CTX_XDL_SITE_NAME"\
                  "CTX_XDL_LDAP_LIST"\
                  "CTX_XDL_SEARCH_BASE"\
                  "CTX_XDL_DOTNET_RUNTIME_PATH"\
                  "CTX_XDL_DESKTOP_ENVIRONMENT"\
                  #"CTX_XDL_SMART_CARD"\
                  "CTX_XDL_START_SERVICE")
ctxSetupEnvArrayNum=${#ctxSetupEnvArray[@]}

function get_str {
    /opt/Citrix/VDA/bin/getstr "$@"
}

#
# print script usage
#
function usage()
{    
    
    get_str CTXINSTALL_USAGE "$fname"
: <<'COMMENT'
    echo "$scriptName - set up Linux VDA running environment."
    if [[ "$devOnly" -eq "yes" ]]; then
         echo "Available Parameters:"
         echo ""
         echo "Usage: $scriptName"
         echo "       set up Linux VDA running environment."
         echo "Usage: $scriptName -p <path>"
         echo "       set up Linux VDA environment by specification in $filePath under <path>"
         echo "Usage: $scriptName -c"
         echo "       Perform preCheck only."
         echo "Usage: $scriptName -i"
         echo "       Install packages only."
         echo "Usage: $scriptName -n"
         echo "       Set up configuration only."
         echo "Usage: $scriptName -v"
         echo "       Verify configuration only."  
         echo "Usage: $scriptName -m"
         echo "       Commit the setup, no backout can be performed after that."
         echo "Usage: $scriptName -b" 
         echo "       Backout the changed configuration file(s) to the original version."
    fi
    echo "Usage: $scriptName -h"
    echo "       display this help and exit" 
COMMENT
    exit 1 
}

#
# Check user, only root user has the permission to run this script
#
function checkUser()
{
    if [ "$(id -u)" != 0 ]; then        
        get_str CTXINSTALL_MUST_ROOT         
        exit 1
    fi
}

#
# Create log file
#
function createLogFile()
{
    if [[ ! -f "$logFile" ]]; then
        touch "$logFile"      
        if [[ "$?" -ne "0" ]]; then           
           get_str CTXINSTALL_CREAT_LOG_FAIL "$logFile"
        fi
    fi 

    echo "#################### Begin $scriptName ####################">>$logFile
    str="`date "+%Y-%m-%d %H:%M:%S"`"
    echo $str>>$logFile  
       
    # Make sure backup directory is  here
    if [[ ! -d "$backupDir" ]]; then
        mkdir -p "$backupDir"
        if [[ "$?" -ne "0" ]]; then
            echo "failed to create back up directory:$backupDir[Warning].">>$logFile
            get_str CTXINSTALL_CREAT_BACKUP_DIR_FAIL "$backupDir"
        fi
    else  # backup directory exists, remove all files in it
        rm -f "$backupDir""/*"
    fi 
}

#
# Output the message to both screen and log file
#
function myPrint()
{
    echo -e "$1" | tee -a "$logFile"
}
 
#
# Output the message to log file only
#
function myLog()
{
    echo -e "$1">>"$logFile"
}

#
# Start/restart/enable service
#   $1: service name
#   $2: start - start service
#       restart - restart service
#       status - show status
#
function startService()
{
    service="$1"
    operation="$2"
    retVal=0
    if [[ "${osPlatform}" == "centos" && "$version" == "7" ]]; then
       /usr/bin/systemctl "$operation" "$service"  >> "$logFile"  2>&1   
       retVal="$?"
    elif [[ "${osPlatform}" == "centos" && "$version" == "8" ]]; then
       sudo /usr/bin/systemctl "$operation" "$service" >> "$logFile" 2>&1
       retVal="$?"
    elif [[ "${osPlatform}" == "rocky" && "$version" == "8" ]]; then
       sudo /usr/bin/systemctl "$operation" "$service" >> "$logFile" 2>&1
       retVal="$?"
    elif [[ "${osPlatform}" == "red" && "$version" == "7" ]]; then
       sudo /usr/bin/systemctl "$operation" "$service" >> "$logFile" 2>&1    
       retVal="$?"
    elif [[ "${osPlatform}" == "red" && "$version" == "8" ]]; then
       sudo /usr/bin/systemctl "$operation" "$service" >> "$logFile" 2>&1
       retVal="$?"
    elif [[ "${osPlatform}" == "suse" ]]; then
       sudo /usr/bin/systemctl "$operation" "$service" >> "$logFile" 2>&1    
       retVal="$?"
    elif [[ "${osPlatform}" == "ubuntu" ]]; then
       sudo /bin/systemctl "$operation" "$service" >> "$logFile" 2>&1    
       retVal="$?"
    elif [[ "${osPlatform}" == "amzn" && "$version" == "2" ]]; then
       sudo /usr/bin/systemctl "$operation" "$service" | sudo tee -a "$logFile"
       retVal="$?"
    else
       retVal="-1"
    fi
    return "$retVal"
}

#
# Start/restart/enable service
#   $1: service name
#   $2: enable  - enable service
#
function enableService()
{
    service="$1"    
    retVal=0
    if [[ "${osPlatform}" == "centos" && "$version" == "7" ]]; then
       sudo /usr/bin/systemctl enable "$service"  >> "$logFile"  2>&1   
       retVal="$?"
    elif [[ "${osPlatform}" == "centos" && "$version" == "8" ]]; then
       sudo /usr/bin/systemctl enable "$service" >> "$logFile" 2>&1
       retVal="$?"
    elif [[ "${osPlatform}" == "rocky" && "$version" == "8" ]]; then
       sudo /usr/bin/systemctl enable "$service" >> "$logFile" 2>&1
       retVal="$?"
    elif [[ "${osPlatform}" == "red" && "$version" == "7" ]]; then
       sudo /usr/bin/systemctl enable "$service" >> "$logFile" 2>&1    
       retVal="$?"
    elif [[ "${osPlatform}" == "red" && "$version" == "8" ]]; then
       sudo /usr/bin/systemctl enable "$service" >> "$logFile" 2>&1
       retVal="$?"
    elif [[ "${osPlatform}" == "suse" ]]; then
       sudo /usr/bin/systemctl enable "$service" >> "$logFile" 2>&1    
       retVal="$?"
    elif [[ "${osPlatform}" == "ubuntu" ]]; then
       sudo /bin/systemctl enable "$service" >> "$logFile" 2>&1    
       retVal="$?"
    elif [[ "${osPlatform}" == "amzn" && "$version" == "2" ]]; then
       sudo /bin/systemctl enable "$service" | sudo tee -a "$logFile"
       retVal="$?"
    else
       retVal="-1"
    fi
    return "$retVal"
}
    
    
#
# Global functions
#
function getYesOrNo()
{
    myLog "Debug: Enter function getYesOrNo"
    local str="$1"
    local defaultVal="$2"
    local val=""
    while true ; do
            read -p "$str" val
        [[ -z ${val} ]] && val=${defaultVal}
        local tempUpperToLower=$(echo "$val" | tr '[:upper:]' '[:lower:]')
               case "${tempUpperToLower}" in
                n|no)
            myLog "Debug: Exit function getYesOrNo" 
                return 1
                 ;;
                y|yes)
            myLog "Debug: Exit function getYesOrNo" 
                 return 0
                 ;;
                *)
                 get_str CTXINSTALL_INPUT_CORRECT_VALUE "y" "n"
                 continue
                ;;
            esac
        done
    myLog "Debug: Exit function getYesOrNo" 
}

#
# Set up default Control Parameters
#
function setDefaultControlParameter()
{
    myLog "Debug: Enter function setDefaultControlParameter"
    isPreCheck="yes"
    isInstallation="yes"
    isConfiguration="yes"
    isVerfication="yes"
    isCommit="no"
    isBackout="no"
    isFinishing="yes"
    myLog "Debug: Exit function setDefaultControlParameter"
}

#
# Parse parameter
#
function parameterParse()
{
    myLog "Debug: Enter function parameterParse" 
    # No parameter, which means to perform all actions except for backout 
    if [[ $paramNum == 0 ]]; then
        setDefaultControlParameter         
    fi
    
    while getopts 'p:cinvmsbh' OPT; do
          case $OPT in
             p)
               filePath="$OPTARG"
               if [[ $paramNum == 2 ]]; then
                  setDefaultControlParameter
               fi
               ;;
             c)
               isPreCheck="yes"
               ;;
             i)
               isInstallation="yes"
               ;;
             n)
               isConfiguration="yes"
               ;;
             v)
               isVerfication="yes"
               ;;
             m)
               isCommit="yes"
               ;;
             s)
               isSilent="yes"
               ;;
             b)
               if [[ "$isPreCheck" == "yes"  || \
                     "$isInstallation" == "yes" || \
                     "$isConfiguration" == "yes" || \
                     "$isVerfication" == "yes" || \
                     "$isCommit" == "yes" ]]; then
                  myLog "parameter 'b' can not be used together with parameter 'c' or 'i' or 'n' or 'v' or 'm'[Error]."
                  exit 1;
               fi
               isBackout="yes"
               ;;            
             h|H|help|?)
               usage
          esac
    done   
    
    myLog "Info: isPreCheck=$isPreCheck"
    myLog "Info: isInstallation=$isInstallation"
    myLog "Info: isConfiguration=$isConfiguration"
    myLog "Info: isVerfication=$isVerfication"
    myLog "Info: isCommit=$isCommit"
    myLog "Info: isBackout=$isBackout"    

    myLog "Debug: Exit function parameterParse" 
}

#
# Get current system information
# populate the following variables:
#    osPlatform
#    osVersion
#    osType
#
function getSysInfo()
{
    myLog "Debug: Enter function getSysInfo"

    infoOS="$(get_str CTXINSTALL_OS_PLATFORM_FAIL)"
    infoVersion="$(get_str CTXINSTALL_OS_VERSION_FAIL)"
    systemKernel="$(uname -v |grep -i Ubuntu 2>&1)"

    #Check Core file, checking sequence is suse, cent, rhel, ubuntu, pardus
    if [[ -f "$coreFileSuse" ]]; then
        osPlatform="suse"
        osVersion="$(cat "$coreFileSuse" |grep "SUSE Linux Enterprise" |cut -d" " -f5|tr A-Z a-z  2>&1)"
        if [[ "$?" -ne "0" || -z "$osVersion" ]]; then           
           myPrint "$infoVersion"
           exit 1
        fi
        
        if [[ "$osVersion" == "12" ]]; then
           osPatchVersion="$(cat "$coreFileSuse" |grep "PATCHLEVEL" |cut -d" " -f3 2>&1)"            
           if [[ "$?" -ne "0" || -z "$osVersion" ]]; then           
               myPrint "$infoVersion"
               exit 1
           fi
        fi
        
        osType="$(cat /etc/SuSE-release |grep "SUSE Linux Enterprise" |cut -d" " -f4|tr A-Z a-z  2>&1)"
        if [[ "$?" -ne "0" || -z "$osType" ]]; then           
           myPrint "$infoOS"
           exit 1
        fi
    elif [[ -f "$coreFileRocky" ]]; then 
        osPlatform="rocky"
        osVersion="$(cat $coreFileRocky |cut -d ' ' -f4 |cut -d '.' -f1-2  2>&1)"    
        if [[ "$?" -ne "0" || -z "$osVersion" ]]; then           
            return 1
        fi
    elif [[ -f $coreFileCent ]]; then 
       osPlatform="$(cat $coreFileCent |cut -d ' ' -f1 |tr A-Z a-z  2>&1)"
       if [[ "$?" -ne "0" || "$osPlatform" -ne "centos" ]]; then           
           myPrint "$infoOS"
           exit 1
       fi
      
       # the contants of $coreFileCent may be 
       # "CentOS release 6.8 (Final)"
       # or "CentOS Linux release 7.2.1511 (Core)"
       # we need to adjust the field  
       num="$(cat $coreFileCent |wc -w 2>&1)"
       if [[ $num -lt 5 ]]; then
           num=`expr $num`
       else
           num=`expr $num - 1`
       fi

       osVersion="$(cat $coreFileCent |cut -d ' ' -f$num |cut -d '.' -f1-2  2>&1)"
       if [[ "$?" -ne "0" || -z "$osVersion" ]]; then           
           myPrint "$infoVersion"
           exit 1
       fi

       osType="" # all cent is one type
      
    elif [[ -f $coreFileRhel ]]; then
       osPlatform="$(cat $coreFileRhel |cut -d ' ' -f1 |tr A-Z a-z  2>&1)"
       if [[ "$?" -ne "0" || "$osPlatform" -ne "red" ]]; then           
           myPrint "$infoOS"
           exit 1
       fi
       osVersion="$(cat $coreFileRhel |cut -d ' ' -f7  2>&1)"

       if [[ $osVersion =~ ^[0-9.]*$ ]]; then
           myLog "$osVersion"
       else
           osVersion="$(cat $coreFileRhel |cut -d ' ' -f6  2>&1)"
           myLog "$osVersion"
       fi

       if [[ "$?" -ne "0" || -z "$osVersion" ]]; then           
           myPrint "$infoVersion"
           exit 1
       fi

       num="$(cat $coreFileRhel |grep -i server |wc -l 2>&1)"

       if [[ "$num" -ne "0" ]]; then
          osType="server"
       else
          osType="workstation"
       fi
 
    elif [[ -f $coreFileUbuntu  && -n "$systemKernel" ]]; then
       osPlatform="$(cat $coreFileUbuntu |grep DISTRIB_ID |cut -d '=' -f2 |tr A-Z a-z  2>&1)"
       if [[ "$?" -ne "0" || "$osPlatform" -ne "ubuntu" ]]; then           
           myPrint "$infoOS"
           exit 1
       fi
       osVersion="$(cat $coreFileUbuntu |grep DISTRIB_RELEASE |cut -d '=' -f2 |tr A-Z a-z  2>&1)" 
       if [[ "$?" -ne "0" || -z "${osVersion}" ]]; then           
           myPrint "$infoVersion"
           exit 1
       fi  
    # MUST follow Ubuntu, because Pardus utilizes the same file(lsb-release) as Ubuntu.
    elif [[ -f $coreFilePardus ]]; then
       osPlatform="$(cat $coreFilePardus |grep DISTRIB_ID |cut -d '=' -f2 |tr A-Z a-z  2>&1)"
       if [[ "$?" -ne "0" || "$osPlatform" -ne "pardus" ]]; then           
           myPrint "$infoOS"
           exit 1
       fi
       osVersion="$(cat $coreFilePardus |grep DISTRIB_RELEASE |cut -d '=' -f2 |tr A-Z a-z  2>&1)" 
       if [[ "$?" -ne "0" || -z "${osVersion}" ]]; then           
           myPrint "$infoVersion"
           exit 1
       fi
    elif [[ -f "$coreFileOS" ]]; then
        osPlatform="$(< $coreFileOS grep ^ID= |cut -d '=' -f2 |tr '[:upper:]' '[:lower:]' |tr -d '"'  2>&1)"
        if [[ "$?" -ne "0" || -z "$osPlatform" ]]; then           
            myPrint "$infoOS"
            exit 1
        fi

        if [[ $osPlatform == "sles" || $osPlatform == "sled" ]]; then
            osPlatform="suse"
        fi

        osVersion="$(< $coreFileOS grep VERSION_ID |cut -d '=' -f2 |tr '[:upper:]' '[:lower:]' |sed 's/\"//g' 2>&1)" 
        #Kylin
		[[ "$$ osPlatform" == "kylin" ]] && osVersion=" $${osVersion#v}"   # 去掉 v10 中的 v
        if [[ "$?" -ne "0" || -z "${osVersion}" ]]; then           
            myPrint "$infoVersion"
            exit 1
        fi  
    fi 
   
    # Change all strings to be lower case
    osPlatform="$(tr '[:upper:]' '[:lower:]' <<< "${osPlatform}")"
    osVersion="$(tr '[:upper:]' '[:lower:]' <<< "${osVersion}")"
    osType="$(tr '[:upper:]' '[:lower:]' <<< "${osType}")"
    osMajorVersion="$(sed 's/\..*//' <<< "${osVersion}")"

    # Set packagemanagement according to osPlatform
    if [[ "${osPlatform}" == "red" || "${osPlatform}" == "centos" || "${osPlatform}" == "amzn" || "${osPlatform}" == "rocky" ]]; then
        pkgManagement="yum"
	#Kylin
    #elif [[ "${osPlatform}" == "ubuntu" ]] || [[ "${osPlatform}" == "pardus" ]] || [[ "${osPlatform}" == "debian" ]]; then
    elif [[ "$$ {osPlatform}" == "ubuntu" || " $${osPlatform}" == "kylin" || "$$ {osPlatform}" == "pardus" || " $${osPlatform}" == "debian" ]]; then
        pkgManagement="apt"
    elif [[ "${osPlatform}" == "suse" ]]; then
        pkgManagement="zypper"
    else
        pkgManagement="unknow"
    fi

    myLog "Info: osPlatform=$osPlatform"
    myLog "Info: osVersion=$osVersion"
    myLog "Info: osPatchVersion=$osPatchVersion"
    myLog "Info: osType=$osType"    
    myLog "Info: pkgManagement=$pkgManagement"

    myLog "Debug: Exit function getSysInfo"
}

#
# OS Platform check, make sure the platform is in the support list.
#
function osPlatformCheck()
{
    myLog "Debug: Enter function osPlatformCheck"
    
    # Check the architecture
    if [[ "$(uname -m)" != "x86_64" && "$(uname -s)" != "Linux" ]]; then        
        info="$(get_str CTXINSTALL_UNSUPPORT_PLATFORM_PRECHECK  1  $(uname -s))"
        myPrint "$info"
        preCheckStatus="Error"
    else        
        info="$(get_str CTXINSTALL_SUPPORT_PLATFORM_PRECHECK  1)"
        myPrint "$info"        
    fi

    # Check the Linux distribution type and version
    if [[ "$osPlatform" == "red" ]]; then
        if [[ "${osVersion}" == "7.9" || "${osVersion}" == "7.8" || "${osVersion}" == "8.1" || "${osVersion}" == "8.2" || "${osVersion}" == "8.3" || "${osVersion}" == "8.6" || "${osVersion}" == "8.4" || "${osVersion}" == "8.7" || "${osVersion}" == "8.8" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK  2  'RedHat' ${osVersion})"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_VERSION_INFO_PRECHECK 2 'RedHat' ${osVersion})"
            myPrint "$info"
            preCheckStatus="Warning" 
        fi
    elif [[ "$osPlatform" = "centos" ]]; then
        if [[ "${osVersion}" == "7.9" || "${osVersion}" == "7.8" || "${osVersion}" == "8.1" || "${osVersion}" == "8.2" || "${osVersion}" == "8.3" || "${osVersion}" == "8.4" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK  2  'CentOS' ${osVersion})"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_VERSION_INFO_PRECHECK 2 'CentOS' ${osVersion})"
            myPrint "$info"
            preCheckStatus="Warning"
        fi
    elif [[ "$osPlatform" = "rocky" ]]; then
        if [[ "${osVersion}" == "8.6" || "${osVersion}" == "8.7" || "${osVersion}" == "8.8" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK  2  'Rocky' ${osVersion})"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_VERSION_INFO_PRECHECK 2 'Rocky' ${osVersion})"
            myPrint "$info"
            preCheckStatus="Warning"
        fi
    elif [[ "${osPlatform}" == "ubuntu" ]]; then
        if [[ "${osVersion}" == "16.04" || "${osVersion}" == "18.04" || "${osVersion}" == "20.04" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK  2  'Ubuntu' ${osVersion})"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_VERSION_INFO_PRECHECK 2 'Ubuntu' ${osVersion})"
            myPrint "$info"
            preCheckStatus="Warning"
        fi
    elif [[ "${osPlatform}" == "suse" ]]; then
        if [[ "${osMajorVersion}" = "15" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK  2  'SUSE' "${osVersion}")"
            myPrint "$info"
        elif [[ "${osVersion}" = "12" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK  2  'SUSE' "${osVersion}")"
            myPrint "$info"
        elif [[ "${osVersion}" = "11" || "${osType}" == "server" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK  2  'SUSE' "${osVersion}")"
            myPrint "$info"
            preCheckStatus="Warning"
        else
            info="$(get_str CTXINSTALL_VERSION_INFO_PRECHECK 2 'SUSE' "${osVersion}")"
            myPrint "$info"
            preCheckStatus="Error"
        fi
    elif [[ "${osPlatform}" == "pardus" ]]; then
        if [[ "${osVersion}" == "17.5" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK 2 'Pardus' ${osVersion})"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_VERSION_INFO_PRECHECK 2 'Pardus' ${osVersion})"
            myPrint "$info"
            preCheckStatus="Warning"
        fi
    elif [[ "${osPlatform}" == "debian" ]]; then
        if [[ "${osVersion}" == "10" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK 2 'Debian' ${osVersion})"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_VERSION_INFO_PRECHECK 2 'Debian' ${osVersion})"
            myPrint "$info"
            preCheckStatus="Warning"
        fi
	#Kylin	
    elif [[ "${osPlatform}" == "kylin" ]]; then
        if [[ "${osVersion}" == "10" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK  2  'Kylin' ${osVersion})"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_VERSION_INFO_PRECHECK 2 'Kylin' ${osVersion})"
            myPrint "$info"
            preCheckStatus="Warning"
        fi
    elif [[ "${osPlatform}" == "amzn" ]]; then
        if [[ "${osVersion}" == "2" ]]; then
            info="$(get_str CTXINSTALL_PLATFORM_INFO_PRECHECK 2 'Amazon' ${osVersion})"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_VERSION_INFO_PRECHECK 2 'Amazon' ${osVersion})"
            myPrint "$info"
            preCheckStatus="Warning"
        fi
    else
        info="$(get_str CTXINSTALL_UNSUPPORT_PLATFORM_PRECHECK 2 'unknown')"
        myPrint "$info"
        preCheckStatus="Error"
    fi

    myLog "Debug: Exit function osPlatformCheck" 
}

#
# Repository Check: make sure the repository has been configured
#
function repositoryCheck()
{
    myLog "Debug: Enter function repositoryCheck"

    if [[ "${osPlatform}" == "red" || "${osPlatform}" == "centos" || "${osPlatform}" == "amzn" || "${osPlatform}" == "rocky" ]]; then
        repositoryNumbers=$(yum -v repolist enabled | grep Repo-id | awk '{print $3}' | wc -l)
        myLog "Debug: The repository number is ${repositoryNumbers}"
        if [[ ${repositoryNumbers} -eq 0 ]]; then
            info="$(get_str CTXINSTALL_NO_REPOSITORY_PRECHECK 3)"
            myPrint "$info"
            preCheckStatus="Error"
        else
            info="$(get_str CTXINSTALL_NUM_REPOSITORY_PRECHECK 3 ${repositoryNumbers})"
            myPrint "$info"
        fi
	#Kylin
    #elif [[ "${osPlatform}" == "ubuntu" || "${osPlatform}" == "pardus" || "${osPlatform}" == "debian" ]]; then
    elif [[ "$$ {osPlatform}" == "ubuntu" || " $${osPlatform}" == "kylin" || "$$ {osPlatform}" == "pardus" || " $${osPlatform}" == "debian" ]]; then
        repositoryNumbers=$(cat /etc/apt/sources.list |egrep -i "^deb" |wc -l)
        if [[ ${repositoryNumbers} -gt 0 ]]; then
            info="$(get_str CTXINSTALL_NUM_REPOSITORY_PRECHECK 3 ${repositoryNumbers})"
            myPrint "$info"
        elif [[ ${repositoryNumbers} -le 0 ]]; then
            info="$(get_str CTXINSTALL_NO_REPOSITORY_PRECHECK 3)"
            myPrint "$info"
            preCheckStatus="Error"
        fi
    elif [[ "${osPlatform}" == "suse" ]]; then
        repositoryNumbers="$(zypper lr |cut -d "|" -f4 |grep -i "yes" |wc -l 2>&1)"
        if [[ ${repositoryNumbers} -gt 0 ]]; then
            info="$(get_str CTXINSTALL_NUM_REPOSITORY_PRECHECK 3 ${repositoryNumbers})"
            myPrint "$info"
        elif [[ ${repositoryNumbers} -le 0 ]]; then
            info="$(get_str CTXINSTALL_NO_REPOSITORY_PRECHECK 3)"
            myPrint "$info"
            preCheckStatus="Error"
        fi
    else
        info="$(get_str CTXINSTALL_UNSUPPORT_PLATFORM_PRECHECK 3 ${osPlatform})"
        myPrint "$info"               
        preCheckStatus="Error"
    fi
    myLog "Debug: Exit function repositoryCheck"
}

#
# Desktop type check: make sure Desktop has been installed. 
#
function DesktopTypeCheck()
{
    myLog "Debug: Enter function DesktopTypeCheck"

    if [[ "${pkgManagement}" == "yum" ]]; then
        result="$(rpm -qa|egrep -i "^gnome-desktop|^kde|^unity|^mate-desktop")"
        if [[ -z "${result}" ]]; then
            info="$(get_str CTXINSTALL_NO_DESKTOP_PRECHECK 4)"
            myPrint "$info"            
            preCheckStatus="Error"
        else
            info="$(get_str CTXINSTALL_DESKTOP_PRECHECK 4)"
            myPrint "$info"            
        fi
    elif [[ "${pkgManagement}" == "apt" ]]; then           
        result="$(dpkg -l|egrep -i "gnome-desktop|kde|unity|mate-desktop")"
        if [[ -z "${result}" ]]; then
            info="$(get_str CTXINSTALL_NO_DESKTOP_PRECHECK 4)"
            myPrint "$info"            
            preCheckStatus="Error"
        else
            info="$(get_str CTXINSTALL_DESKTOP_PRECHECK 4)"
            myPrint "$info"            
        fi        
    elif [[ "${pkgManagement}" == "zypper" ]]; then      
        result="$(zypper se|egrep -i "gnome-desktop|kde|mate-desktop")"
        if [[ -z "${result}" ]]; then
            info="$(get_str CTXINSTALL_NO_DESKTOP_PRECHECK 4)"
            myPrint "$info"            
            preCheckStatus="Error"
        else
            info="$(get_str CTXINSTALL_DESKTOP_PRECHECK 4)"
            myPrint "$info"            
        fi
    else
        myLog "The package manager(${pkgManagement}) is not supported"
    fi
    myLog "The package manager is ${pkgManagement}"

    myLog "Debug: Exit function DesktopTypeCheck"
}

#
# This function is used to check the hostname 
#
function hostnameCheck()
{ 
    myLog "Debug: Enter function hostnameCheck"
    
    myLog "Debug: Change cloud cfg file"
    cloud_cfg_file="/etc/cloud/cloud.cfg"
    if [[ -f "$cloud_cfg_file" ]]; then
        sed -i "s/preserve_hostname:.*/preserve_hostname: true/g" "$cloud_cfg_file"
    fi
    
    local hostName=$1
    local len=$(echo $hostName |wc -L)
    # Check hostName length
    if [[ ${len} -eq 0 || ${len} -ge 16 ]]; then
        local info="$(get_str CTXINSTALL_HOSTNAME_TOO_LONG)"
        myPrint "${info}"
        myLog "Debug: Exit function hostnameCheck"
        return 1
    fi
    # Check hostName characters 
    local hostNameAfterCheck=$(echo ${hostName} |egrep "[^a-zA-Z0-9\-]|^[0-9]|\-$")
    if [[ -n ${hostNameAfterCheck} ]]; then
        local info="$(get_str CTXINSTALL_HOSTNAME_CHARACTER_ERROR)"
        myPrint "${info}"
        myLog "Debug: Exit function hostnameCheck"
        return 1
    fi
    myLog "Debug: Exit function hostnameCheck"
    return 0
}

#
# This function is used to check the hostname environment variable CTX_EASYINSTALL_HOSTNAME 
#
function hostnameEnvCheck()
{
    myLog "Debug: Enter function hostnameEnvCheck"
    if [[ -z $1 ]]; then
        myLog "Debug: The environment variable CTX_EASYINSTALL_HOSTNAME is empty."  
        return 0 
    fi

    hostnameCheck $1
    local ret=$?    
    if [[ ${ret} -ne 0 ]]; then
        myLog "Debug: Exit function hostnameEnvCheck"
        exit 2
    fi
    myLog "Debug: Exit function hostnameEnvCheck"
    return 0
}

#
# This function is used to check IP address format
#
function pingAddress()
{   
    myLog "Debug: Enter function pingAddress"
    local address="$1"

    # Check address type
    if [ "$useIPv6" == "no" ]
    then
        # Use ping to cover ipv4 format
        local i=0
        local ret=1
        myLog "Info: Use ping to cover ipv4 format"
        for((i=0;i<${pingTimes};i++)); do
            ping -c 1 "${address}" >> "${logFile}" 2>&1
            ret=$?    
            if [[ ${ret} -eq 0 ]]; then
                myLog "Debug: Exit function pingAddress"
                return 0
            fi
        done
      #elif [ "$address" != "${1#*:[0-9a-fA-F]}" ]
      #then
    # Use ping6 to cover ipv6 format
      else
        local i=0
        local ret=1
        myLog "Info: Use ping6 to cover ipv6 format"
        for((i=0;i<${pingTimes};i++)); do
            ping6 -c 1 "${address}" >> "${logFile}" 2>&1
            ret=$?    
            if [[ ${ret} -eq 0 ]]; then
                myLog "Debug: Exit function pingAddress"
                return 0
            fi    
        done
      fi

    myLog "Debug: Exit function pingAddress"
    return 1
}

#
# This function is used to check the CTX_EASYINSTALL_DNS
#
function dnsEnvCheck()
{
    myLog "Debug: Enter function dnsEnvCheck"
    if [[ -z "$1" ]]; then    
        myLog "Debug: The environment variable CTX_EASYINSTALL_DNS is empty."
        return 0 
    fi

    # Store CTX_EASYINSTALL_DNS with array format in dnsList
    local ret=0
    oIFS=$IFS
    IFS=' '
    local dnsList=($1)
    IFS=$oIFS

    # Check dns numbers if it is greater than dnsNum
    local dnsListLength=${#dnsList[@]}
    if [[ "${dnsListLength}" -gt "${dnsNum}" ]]; then
        local info="$(get_str CTXINSTALL_ENV_VARIABLE_DNS_NUM_PRECHECK ${dnsListLength} ${dnsNum})"
        myPrint "${info}"
        exit 2 
    fi

    # Check whether every characters in CTX_EASYINSTALL_DNS is valid 
    local val=""
    for val in ${dnsList[*]}
    do
        pingAddress "${val}"
        local ret=$?
        if [[ "${ret}" -ne 0 ]]; then
            myLog "Debug: Exit function dnsEnvCheck"
            local info="$(get_str CTXINSTALL_UNREACHABLE_ADDRESS ${val})"
          myPrint "${info}"            
            exit 2 
        fi
    done

    myLog "Debug: Exit function dnsEnvCheck"
    return 0
}

#
# Check the environment variables of ctxsetup.sh assignment with "yes" or "no" 
#
function checkYesOrNo()
{
    myLog "Debug: Enter function checkYesOrNo"
    if [[ -z $1    ]]; then
        myLog "Debug: This parameter is empty"
        return 0
    fi
    local tempUpperToLower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "${tempUpperToLower}" in
        n|no)
        myLog "Debug: Exit function checkYesOrNo"
        return 0
        ;;
        y|yes)
        myLog "Debug: Exit function checkYesOrNo"
        return 0
        ;;
        *)
        myLog "Debug: Exit function checkYesOrNo"
        return 1
        ;;
    esac
    myLog "Debug: Exit function checkYesOrNo"
}

#
# Check the environment variables CTX_XDL_VDA_PORT which is Greater than 0 and less than 65536
#
function checkPortNum()
{
    myLog "Debug: Enter function checkPortNum"
    if [[ -z "$1" ]]; then
        myLog "Debug: The parameter is empty"
        return 0
    fi

    # make sure the parameter is a number
    local ref='^[0-9]+$'
    if ! [[ $1 =~ ${ref} ]]; then
        myLog "Debug : The parameter is not a number"
        return 1    
    fi

    if ! [[ "$1" -ge 0 && "$1" -le 65535 ]]; then
        myLog "Debug : The parameter is not greater than 0 and less than 65536"
        return 1
    fi

    myLog "Debug: Exit function checkPortNum"
    return 0
}

#
# Check the CTX_EASYINSTALL_ADINTEGRATIONWAY which can only be "winbind" "centrify" "sssd" or "pbis"
#
function checkEnvCtxADWay()
{
    version="${osVersion:0:1}"
    myLog "Debug :Enter function checkEnvCtxADWay"
    if [[ -z $1 ]]; then
        myLog "Debug: This parameter is empty"  
        myLog "Debug: Exit function checkEnvCtxADWay"
        return 0
    fi

    if [[ "${osPlatform}" == "pardus" ]]; then
        if ! [[ $1 == "winbind" || $1 == "sssd" ]]; then
            myLog "Debug: The parameter($1) is invalid on checkEnvCtxADWay()."
            local info="$(get_str CTXINSTALL_ENV_VARIABLE_AD_WAY_WINBIND_SSSD_PRECHECK ${osPlatform})"
            myPrint "${info}"            
            exit 2                            
        fi 
    else
        if ! [[ $1 == "winbind" || $1 == "centrify" || $1 == "sssd" || $1 == "pbis" ]]; then    
            myLog "Debug: The parameter($1) is invalid on checkEnvCtxADWay()."
            local info="$(get_str CTXINSTALL_ENV_VARIABLE_AD_WAY_WINBIND_SSSD_CENTRIFY_PBIS_PRECHECK ${osPlatform})"
            myPrint "${info}"    
            exit 2
        fi
    fi
    myLog "Debug: Exit function checkEnvCtxADWay"
    return 0
}

function ctxinstallEnvVariableCheck()
{
########## Check the ctxinstall.sh environment variables ###########
    # Check host name environment variable
    hostnameEnvCheck "${CTX_EASYINSTALL_HOSTNAME}"    
    local ret=$?
    if [[ "${ret}" -ne 0 ]]; then 
        local info="$(get_str CTXINSTALL_HOSTNAME_ENV_ERROR)"
        myPrint "${info}"
        envVariableCheckStatus=1
    fi

    # Check dns environment variable  
    dnsEnvCheck "${CTX_EASYINSTALL_DNS}"
    local ret=$?
    if [[ "${ret}" -ne 0 ]]; then 
        local info="$(get_str CTXINSTALL_DNS_ENV_ERROR "${CTX_EASYINSTALL_DNS}" )"
        myPrint "${info}" 
        envVariableCheckStatus=1
    fi

    # Check the CTX_EASYINSTALL_ADINTEGRATIONWAY which can only be "winbind" "centrify" "sssd" or "pbis"
    checkEnvCtxADWay "${CTX_EASYINSTALL_ADINTEGRATIONWAY}"
    local ret=$?
    if [[ "${ret}" -ne 0 ]]; then
        local info="$(get_str CTXINSTALL_CHECK_SETUPENV_ADINTEGRATIONWAY)"
        myPrint "${info}"
        envVariableCheckStatus=1
    fi
}

function ctxsetupEnvVariableCheck()
{
############# Check ctxsetup.sh environment variables #################  
    # Check the variables value that can only be "yes" or "no"
    local checkYesOrNoArray=("CTX_XDL_SUPPORT_DDC_AS_CNAME"\
                             "CTX_XDL_REGISTER_SERVICE"\
                             "CTX_XDL_ADD_FIREWALL_RULES"\
                             "CTX_XDL_HDX_3D_PRO"\
                             "CTX_XDL_VDI_MODE"\
                             #"CTX_XDL_SMART_CARD"\
                             "CTX_XDL_START_SERVICE")
    local tempSetupEnv="" 
    for tempSetupEnv in ${checkYesOrNoArray[@]}; do
        checkYesOrNo "${!tempSetupEnv}"
        local ret=$?
        if [[ "${ret}" -ne 0 ]]; then
            local info="$(get_str CTXINSTALL_CHECK_SETUPENV_ERROR "${tempSetupEnv}")"
            myPrint "${info}"
            envVariableCheckStatus=1
        fi
    done

    # Check the CTX_XDL_VDA_PORT which is >= 0 && <= 65535 
    checkPortNum "${CTX_XDL_VDA_PORT}"
    local ret=$?
    if [[ "${ret}" -ne 0 ]]; then
        local setupEnvName="CTX_XDL_VDA_PORT"
        local info="$(get_str CTXINSTALL_CHECK_SETUPENV_ERROR "${setupEnvName}")" 
        myPrint "${info}"
        envVariableCheckStatus=1
    fi

    # Check the CTX_XDL_TELEMETRY_SOCKET_PORT which is >= 0 && <= 65535 
    checkPortNum "${CTX_XDL_TELEMETRY_SOCKET_PORT}"
    local ret=$?
    if [[ "${ret}" -ne 0 ]]; then
        local setupEnvName="CTX_XDL_TELEMETRY_SOCKET_PORT"
        local info="$(get_str CTXINSTALL_CHECK_SETUPENV_ERROR "${setupEnvName}")" 
        myPrint "${info}"
        envVariableCheckStatus=1
    fi

    # Check the CTX_XDL_TELEMETRY_PORT which is >= 0 && <= 65535 
    checkPortNum "${CTX_XDL_TELEMETRY_PORT}"
    local ret=$?
    if [[ "${ret}" -ne 0 ]]; then
        local setupEnvName="CTX_XDL_TELEMETRY_PORT"
        local info="$(get_str CTXINSTALL_CHECK_SETUPENV_ERROR "${setupEnvName}")" 
        myPrint "${info}"
        envVariableCheckStatus=1
    fi

    # Check envVariableCheckStatus status   
    if [[ "${envVariableCheckStatus}" -eq 0 ]]; then
        local str="$(get_str CTXINSTALL_ENV_VARIABLE_PRECHECK "5")"
        myPrint "${str}"
    else
        preCheckStatus="Error"
        local str="$(get_str CTXINSTALL_ERROR_ENV_VARIABLE_PRECHECK "5")"
        myPrint "${str}"
    fi
}

#
# Check the Environment Variables to make sure the present environment is correct
#
function  envVariableCheck()
{
    myLog "Debug :Enter function envVariableCheck"

    local envVariableCheckStatus=0

    # traverse the ctxInstallEnvArray if the Environment variable = "<none>" then set this variable to ""
    local tempVal=""
    for tempVal in ${ctxInstallEnvArray[@]}; do
        if [[ "${!tempVal}" == "<none>" ]]; then
            declare "${tempVal}"=""
        fi
    done    

    ctxinstallEnvVariableCheck
    ctxsetupEnvVariableCheck

    myLog "Debug :Exit function envVariableCheck"
}

#
# Check if the environment meets the pre-condition,
# Called it as phase 1 in this script
#
# Following condition should be checked:
# 1. OS Platform and version
# 2. Pkg Repository
# 3. Desktop type
# 4. Environment variables
#
function preCheck()
{
    myLog "Debug: Enter function preCheck"
    info="$(get_str CTXINSTALL_START_PRECHECK)"       
    myPrint "$info"
    
    # check the OS Platform and OS version
    osPlatformCheck

    # Check the repository
    repositoryCheck

    # Check Desktop type(this step will check the key pkg which is essential but was not installed)
    DesktopTypeCheck

    # Check Environment variables
    if [[ "${isSilent}" != "yes" ]]; then
        envVariableCheck
    fi

    if [[ "$preCheckStatus" == "Success" ]]; then 
       info="$(get_str CTXINSTALL_DONE_SUCCESSFULLY_PRECHECK)"        
    else
       info="$(get_str CTXINSTALL_DONE_WITH_ERROR_PRECHECK "${preCheckStatus}" )"             
    fi
    myPrint "$info"
    myLog "Debug: Exit function preCheck"
}

#
# Perform installation for RedHat platform
#
function installationRhel()
{     
    myLog "Debug: Enter function installationRhel"
    # Install the common packages    
    info="$(get_str CTXINSTALL_INSTALL_PKG_STEP_INSTALLATION 1)"
    myPrint "$info"
    for((i=0;i<pkgListRhelNum;i++)); do
         info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "$pkgListRhelNum" "${pkgListRhel[$i]}" )"
         myPrint "$info"
         $YUM -y install "${pkgListRhel[$i]}" >> "$logFile" 2>&1
         if [[ "$?" -ne "0" ]]; then               
              info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${pkgListRhel[$i]}" )"              
              $YUM info "${pkgListRhel[$i]}" >> "$logFile"  2>&1             
              [[ "$?" -ne "0" ]] && myPrint "$info" && installationStatus="Error"
         fi 
    done

    # install gnome packages
    #yum groupinstall "X Window System" "Desktop Platform" Desktop
    version="${osVersion:0:1}"
    info="$(get_str CTXINSTALL_INSTALL_SPECIAL_PKG_STEP_INSTALLATION 2)"
    myPrint "$info"
    if [[ "$version" == "7" || "$version" == "2" ]]; then
        for((i=0;i<pkgListRhel7Num;i++)); do
             info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "$pkgListRhel7Num" "${pkgListRhel7[$i]}")"
             myPrint "$info"
             $YUM -y install "${pkgListRhel7[$i]}" >> "$logFile" 2>&1
             if [[ "$?" -ne "0" ]]; then
                 info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${pkgListRhel7[$i]}")"  
                 $YUM info "${pkgListRhel7[$i]}" >> "$logFile" 2>&1
                 [[ "$?" -ne "0" ]] && myPrint "$info" && installationStatus="Error"
             fi
        done
    
        # update packages for RHEL 7.X
        info="$(get_str CTXINSTALL_UPDATE_PKG_STEP_INSTALLATION 3)"
        myPrint "$info"
        for((i=0;i<pkgListUpdateRhel7Num;i++)); do
             info="$(get_str CTXINSTALL_UPDATE_PKG_INSTALLATION "`expr $i + 1`" "$pkgListUpdateRhel7Num" "${pkgListUpdateRhel7[$i]}")"
             myPrint "$info"
             $YUM -y update "${pkgListUpdateRhel7[$i]}" >> "$logFile" 2>&1
             if [[ "$?" -ne "0" ]]; then
                 info="$(get_str CTXINSTALL_UPDATE_PKG_FAIL_INSTALLATION "${pkgListUpdateRhel7[$i]}")" 
                 myPrint "$info" 
                 installationStatus="Warning"
             fi
        done
        info="$(get_str CTXINSTALL_INIT_DB_INSTALLATION 4)" 
        myPrint "$info" 
        sudo postgresql-setup initdb >> "$logFile" 2>&1

    elif [[ "$version" == "8" ]]; then
        for((i=0;i<pkgListRhel8Num;i++)); do
             info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "$pkgListRhel8Num" "${pkgListRhel8[$i]}")"
             myPrint "$info"
             $YUM -y install "${pkgListRhel8[$i]}" >> "$logFile" 2>&1
             if [[ "$?" -ne "0" ]]; then
                 info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${pkgListRhel8[$i]}")"
                 $YUM info "${pkgListRhel8[$i]}" >> "$logFile" 2>&1
                 [[ "$?" -ne "0" ]] && myPrint "$info" && installationStatus="Error"
             fi
        done

        # update packages for RHEL 8.X
        info="$(get_str CTXINSTALL_UPDATE_PKG_STEP_INSTALLATION 3)"
        myPrint "$info"
        for((i=0;i<pkgListUpdateRhel8Num;i++)); do
             info="$(get_str CTXINSTALL_UPDATE_PKG_INSTALLATION "`expr $i + 1`" "$pkgListUpdateRhel8Num" "${pkgListUpdateRhel8[$i]}")"
             myPrint "$info"
             $YUM -y update "${pkgListUpdateRhel8[$i]}" >> "$logFile" 2>&1
             if [[ "$?" -ne "0" ]]; then
                 info="$(get_str CTXINSTALL_UPDATE_PKG_FAIL_INSTALLATION "${pkgListUpdateRhel8[$i]}")"
                 myPrint "$info"
                 installationStatus="Warning"
             fi
        done
        info="$(get_str CTXINSTALL_INIT_DB_INSTALLATION 4)"
        myPrint "$info"
        sudo postgresql-setup initdb >> "$logFile" 2>&1

    else
        info="$(get_str CTXINSTALL_UNSUPPORT_VERSION_INSTALLATION "${osVersion}")" 
        myPrint "$info"         
        exit 3
    fi

    # set JAVA_HOME environment
    info="$(get_str CTXINSTALL_SET_JAVA_ENV_INSTALLATION 5)" 
    myPrint "$info"
    `sed -i '/JAVA_HOME=.*$/d' ~/.bashrc`
    echo "export JAVA_HOME=/usr/lib/jvm/java">>~/.bashrc
    # start PostgreSQL
    info="$(get_str CTXINSTALL_START_POST_SQL_INSTALLATION 6)" 
    myPrint "$info"
    enableService "postgresql"
    startService "postgresql" "start"
    sudo -u postgres psql -c 'show data_directory' >> "$logFile" 2>&1
    myLog "Debug: Exit function installationRhel"
}

#
# Perform installation for CentOS platform
#
function installationCent()
{
    myLog "Debug: Enter function installationCent()"
    # CentOS has the same installation & configuration procedures
    installationRhel 
    myLog "Debug: Exit function installationCent()"

}

#
# Perform installation for Amazon linux2 platform
#
function installationAmazon()
{
    myLog "Debug: Enter function installationAmazon()"
    # Amazon linux2 has the same installation & configuration procedures
    installationRhel 
    myLog "Debug: Exit function installationAmazon()"

}

#
# Perform installation for SUSE platform
# currently, we do not implement this function, keep it here for expansion later
#
function installationSuse()
{
    myLog "Debug: Enter function installationSuse()"
    
    # Install the common packages    
    info="$(get_str CTXINSTALL_INSTALL_PKG_STEP_INSTALLATION 1)"
    myPrint "$info"
    for((i=0;i<${#pkgListSuse[@]};i++)); do
         info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "${#pkgListSuse[@]}" "${pkgListSuse[$i]}")"
         myPrint "$info"
         zypper -i -n install "${pkgListSuse[$i]}" >> "$logFile" 2>&1
         if [[ "$?" -ne "0" ]]; then               
              info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${pkgListSuse[$i]}")"              
              myPrint "$info"
              installationStatus="Error"
         fi 
    done   

    info="$(get_str CTXINSTALL_INSTALL_SPECIAL_PKG_STEP_INSTALLATION 2)"
    myPrint "$info"    
    if [[ "$osVersion" == "11" ]]; then
        # Install packages for SUSE 11
        for((i=0;i<${#pkgListSuse11[@]};i++)); do
             info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "${#pkgListSuse11[@]}" "${pkgListSuse11[$i]}")"
             myPrint "$info"
             zypper -i -n install "${pkgListSuse11[$i]}" >> "$logFile" 2>&1
             if [[ "$?" -ne "0" ]]; then
                 info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${pkgListSuse11[$i]}")"  
                 myPrint "$info"
                 installationStatus="Error"
             fi
        done          
    fi

    # update package
    info="$(get_str CTXINSTALL_UPDATE_PKG_STEP_INSTALLATION 3)"
    myPrint "$info"
    for((i=0;i<${#pkgListUpdateSuse[@]};i++)); do
        info="$(get_str CTXINSTALL_UPDATE_PKG_INSTALLATION "`expr $i + 1`" "${#pkgListUpdateSuse[@]}" "${pkgListUpdateSuse[$i]}")"
        myPrint "$info"
        zypper -i -n update  "${pkgListUpdateSuse[$i]}" >> "$logFile" 2>&1
        if [[ "$?" -ne "0" ]]; then
            info="$(get_str CTXINSTALL_UPDATE_PKG_FAIL_INSTALLATION "${pkgListUpdateSuse[$i]}")"  
            myPrint "$info"
            installationStatus="Warning"
        fi
    done
    
    info="$(get_str CTXINSTALL_INIT_DB_INSTALLATION 4)"
    myPrint "$info"        
    info1="$(get_str CTXINSTALL_ENABLE_POSTGRESQL_FAIL_INSTALLATION)"
    case "$osVersion" in
        11)
            enableCmd="sudo /sbin/insserv postgresql"
            restartCmd="sudo /etc/init.d/postgresql restart"
            ;;
        12)
            enableCmd="sudo chkconfig postgresql on"
            restartCmd="sudo systemctl restart postgresql"
            ;;
        15.*)
            enableCmd="sudo systemctl enable postgresql"
            restartCmd="sudo systemctl restart postgresql"
            ;;
        *)
            ;;
    esac

    myLog "enableCmd=$enableCmd"
    myLog "restartCmd=$restartCmd"

    eval $enableCmd >> "$logFile"  2>&1
    ret1="$?"     
    eval $restartCmd >> "$logFile" 2>&1
    ret2="$?"
    [[ "$ret1" -ne "0" || "$ret2" -ne "0" ]] && myPrint "$info1" && installationStatus="Error"
    myLog "Debug: Exit function installationSuse()"
}

#
# Perform installation for ubuntu platform
#
function installationUbuntu()
{
    myLog "Debug: Enter function installationUbuntu()"
    # Install all OS software updates.
    info="$(get_str CTXINSTALL_UPDATE_PKG_STEP_INSTALLATION 1)" 
    myPrint "$info"    
    sudo apt-get -y update >> "$logFile" 2>&1
    if [[ "$?" -ne "0" ]]; then
        myLog "Warning: failed to update packages."
        installationStatus="Warning"
    fi
    # Install the common packages
    info="$(get_str CTXINSTALL_INSTALL_PKG_STEP_INSTALLATION 2)" 
    myPrint "$info"
    if [[ "${osVersion}" == "16.04" || "${osVersion}" == "18.04" || "${osVersion}" == "20.04" ]]; then
       for((i=0;i<${#pkgListUbuntu[@]};i++)); do
          info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "${#pkgListUbuntu[@]}" "${pkgListUbuntu[$i]}")"
          myPrint "$info"
          apt-get -y install "${pkgListUbuntu[$i]}" >> "$logFile" 2>&1
          if [[ "$?" -ne "0" ]]; then
             info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${pkgListUbuntu[$i]}")"
             myPrint "$info"
             installationStatus="Error"
          fi
       done
    fi 


    myLog "Debug: Exit function installationUbuntu"
    # Configure bash as default system shell
    #sudo dpkg-reconfigure dash
}

#
# Perform installation for pardus platform
#
function installationPardus()
{
    myLog "Debug: Enter function installationPardus()"
    # Install all OS software updates.
    info="$(get_str CTXINSTALL_UPDATE_PKG_STEP_INSTALLATION 1)" 
    myPrint "$info"    
    sudo apt-get -y update >> "$logFile" 2>&1
    if [[ "$?" -ne "0" ]]; then
        myLog "Warning: failed to update packages."
        installationStatus="Warning"
    fi
    # Install the common packages
    info="$(get_str CTXINSTALL_INSTALL_PKG_STEP_INSTALLATION 2)" 
    myPrint "$info"

    for((i=0;i<${#pkgListPardus[@]};i++)); do
        info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "${#pkgListPardus[@]}" "${pkgListPardus[$i]}")" 
        myPrint "$info"
        DEBIAN_FRONTEND=noninteractive apt-get -q -y install "${pkgListPardus[$i]}" >> "$logFile" 2>&1
        if [[ "$?" -ne "0" ]]; then
            info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${pkgListPardus[$i]}")" 
            myPrint "$info"
            installationStatus="Error"
        fi
    done

    
    myLog "Debug: Exit function installationPardus"
    # Configure bash as default system shell
    #sudo dpkg-reconfigure dash
}

#
# Perform installation for debian platform
#
function installationDebian()
{
    myLog "Debug: Enter function installationDebian()"
    # Install all OS software updates.
    info="$(get_str CTXINSTALL_UPDATE_PKG_STEP_INSTALLATION 1)" 
    myPrint "$info"    
    sudo apt-get -y update >> "$logFile" 2>&1
    if [[ "$?" -ne "0" ]]; then
        myLog "Warning: failed to update packages."
        installationStatus="Warning"
    fi
    # Install the common packages
    info="$(get_str CTXINSTALL_INSTALL_PKG_STEP_INSTALLATION 2)" 
    myPrint "$info"

    for((i=0;i<${#pkgListDebian[@]};i++)); do
        info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "${#pkgListDebian[@]}" "${pkgListDebian[$i]}")" 
        myPrint "$info"
        apt-get -q -y install "${pkgListDebian[$i]}" >> "$logFile" 2>&1
        if [[ "$?" -ne "0" ]]; then
            info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${pkgListDebian[$i]}")" 
            myPrint "$info"
            installationStatus="Error"
        fi
    done

    
    myLog "Debug: Exit function installationDebian()"
}

#
# Install the packages which Linux VDA dependents upon
#
function installation()
{
    myLog "Debug: Enter function installation"
    info="$(get_str CTXINSTALL_START_INSTALLATION )" 

    myPrint "$info"  
    if [[ -n "$osPlatform" && "$osPlatform" == "red" ]]; then
       installationRhel
    elif [[ -n "$osPlatform" && "$osPlatform" == "rocky" ]]; then
       installationRhel
    elif [[ -n "$osPlatform" && "$osPlatform" == "centos" ]]; then
       installationCent
    elif [[ -n "$osPlatform" && "$osPlatform" == "amzn" ]]; then
       installationAmazon
    elif [[ -n "$osPlatform" && "$osPlatform" == "suse" ]]; then
       installationSuse
    #Kylin
	#elif [[ -n "$osPlatform" && "$osPlatform" == "ubuntu" ]]; then
    elif [[ -n "$osPlatform" && ( "$osPlatform" == "ubuntu" || "$osPlatform" == "kylin" ) ]]; then
       installationUbuntu
    elif [[ -n "$osPlatform" && "$osPlatform" == "pardus" ]]; then
       installationPardus
    elif [[ -n "$osPlatform" && "$osPlatform" == "debian" ]]; then
       installationDebian
    else
       info="$(get_str CTXINSTALL_UNSUPPORT_PLATFORM_FAIL $osPlatform )" 
       myPrint "$info" 
       exit 3
    fi
        
    if [[ "$installationStatus" == "Success" ]]; then 
        info="$(get_str CTXINSTALL_END_INSTALLATION )" 
    else
        info="$(get_str CTXINSTALL_END_WITH_WARNING_INSTALLATION "${installationStatus}" )"        
    fi
    myPrint "$info"
                
    myLog "Debug: Exit function installation"
}

#
# prompt for user input
#
function promptVal()
{
    myLog "Debug: Enter function promptVal"
    while true; do
        read -p "$1" val 
        hostnameCheck "${val}"
        local ret=$?
        if [[ "${ret}" -eq 0 ]]; then
           break
        fi      
    done
    hostName=$val
    myLog "Info: hostName=$hostName"
    myLog "Debug: Exit function promptVal"
}

#
# prompt for inputting hostname
#
function getHostName()
{
    myLog "Debug: Enter function getHostName"
    # get HostName from environment variable
    if [[ -n "${CTX_EASYINSTALL_HOSTNAME}" ]]; then
        local tempCtxInstallEnv="CTX_EASYINSTALL_HOSTNAME"
        local str="$(get_str CTX_EASYINSTALL_ENV_BEENSET "${tempCtxInstallEnv}")"
        myPrint "${str}"
        hostName="${CTX_EASYINSTALL_HOSTNAME}"
    # get HostName from User input
    else
        if [[ "${isSilent}" == "yes" ]]; then
            myLog "Debug: Exit function getHostName"
            return
        fi
        local str="$(get_str CTXINSTALL_CHG_HOSTNAME_CONFIGURATION $hostName)"
        local str1="$(get_str CTXINSTALL_NEW_HOSTNAME_CONFIGURATION)"
        getYesOrNo "${str}" "n"
        local ret=$? 
        if [[ ${ret} -eq 0 ]]; then
            promptVal "${str1}"
        fi
    fi
    hostNameUpper=$(echo $hostName | tr '[a-z]' '[A-Z]')
    myLog "Info: Hostname is $hostName"
    myLog "Debug: Exit function getHostName"
}

#
# prompt for inputting DNS
#
function getDNS()
{
    myLog "Debug: Enter function getDNS"
    # get DNS from environment variable    
    if [[ -n "${CTX_EASYINSTALL_DNS}" ]]; then
        local tempCtxInstallEnv="CTX_EASYINSTALL_DNS"
        local str="$(get_str CTX_EASYINSTALL_ENV_BEENSET "${tempCtxInstallEnv}")"
        myPrint "${str}"
        # Store CTX_EASYINSTALL_DNS with array format in dnsList
        oIFS=$IFS
        IFS=' '
        local dnsList=($CTX_EASYINSTALL_DNS)
        IFS=$oIFS
        
        local val=""
        local i=0
        for val in ${dnsList[*]}
        do                    
            ((i++))
            if [[ "${i}" == "1" ]]; then
                dns1="${val}"
            elif [[ "${i}" == "2" ]]; then
                dns2="${val}"
            elif [[ "${i}" == "3" ]]; then
                dns3="${val}"
            elif [[ "${i}" == "4" ]]; then
                dns4="${val}"
            else
                myLog "Warning: we currently support $dnsNum DNS"
                myLog "Debug: Exit function getDNS"
                return
            fi
        done

    # get DNS from user input
    else
        if [[ "${isSilent}" == "yes" ]]; then
            myLog "Debug: Exit function getDNS"
            return
        fi
        local str0=""
        if [[ -n "$dns1" ]]; then              
            [[ -z "$dns2" && -z "$dns3" && -z "$dns4" ]] && str0="$(get_str CTXINSTALL_CHANGE_DNS1_CONFIGURATION $dns1)"
            [[ -n "$dns2" && -z "$dns3" && -z "$dns4" ]] && str0="$(get_str CTXINSTALL_CHANGE_DNS2_CONFIGURATION $dns1 $dns2)"
            [[ -n "$dns2" && -n "$dns3" && -z "$dns4" ]] && str0="$(get_str CTXINSTALL_CHANGE_DNS3_CONFIGURATION $dns1 $dns2 $dns3)"
            [[ -n "$dns2" && -n "$dns3" && -n "$dns4" ]] && str0="$(get_str CTXINSTALL_CHANGE_DNS4_CONFIGURATION $dns1 $dns2 $dns3 $dns4)"       
                getYesOrNo "${str0}" "n"
                local ret=$?
                if [[ "${ret}" -eq 1 ]]; then
                    myLog "Debug: Exit function getDNS"
                    return
                fi
        else 
            local str="$(get_str CTXINSTALL_NEED_CONFIG_DNS_CONFIGURATION)"
            getYesOrNo "${str}" "n"
            local ret=$?
            if [[ "${ret}" -ne 0 ]]; then
                myLog "Debug: No input for DNS"
                myLog "Debug: Exit function getDNS"
                return
            fi
        fi
           
        local i=1   
        local str1="$(get_str CTXINSTALL_INPUT_DNS_CONFIGURATION)"      
        local str2="$(get_str CTXINSTALL_CONFIG_MORE_DNS_CONFIGURATION)"
        
        while [ $i -le $dnsNum ] ; do
             while true ;do
                read -p "$str1" val
                result=`expr index $val '.'`
                if [[ "$result" -ne "0" ]]; then
                    useIPv6="no"
                else
                    useIPv6="yes"
                fi        
                pingAddress $val
                local ret=$?
                
                if [[ "${ret}" -eq 0 ]]; then  # If the dns address is valid then break
                    break
                
                else  # If the dns address is invalid then input again
                    local info="$(get_str CTXINSTALL_UNREACHABLE_ADDRESS "DNS")"
                    myPrint "${info}"
                fi
             done
             if [[ "$i" == "1" ]]; then 
                dns1=$val
                [[ -z "dns1" ]] && dns2="" && dns3="" && dns4="" && break
             fi
             if [[ "$i" == "2" ]]; then 
                dns2=$val
                [[ -z "dns2" ]] && dns3="" && dns4="" && break
             fi
             if [[ "$i" == "3" ]]; then 
                dns3=$val
                [[ -z "dns3" ]] && dns4="" && break
             fi        
             [[ "$i" == "4" ]]&& dns4=$val
             [[ "$i" == "$dnsNum" ]] && break
             i=`expr $i + 1`
             getYesOrNo "$str2" "n"
             local ret="$?"
             if [[ ${ret} -eq 0 ]]; then
                  continue
             else
                  break
             fi
        done
        [[ -n "$dns1" ]] && myLog "Info: DNS Server 1=$dns1"
        [[ -n "$dns2" ]] && myLog "Info: DNS Server 2=$dns2"
        [[ -n "$dns3" ]] && myLog "Info: DNS Server 3=$dns3"
        [[ -n "$dns4" ]] && myLog "Info: DNS Server 4=$dns4" 
    fi
    myLog "Debug: Exit function getDNS"
}

#
# prompt for inputting NTP
#
function getNTPS()
{
    myLog "Debug: Enter function getNTPS"
    # get NTPS from environment variable
    if [[ -n "${CTX_EASYINSTALL_NTPS}" ]]; then
        local tempCtxInstallEnv="CTX_EASYINSTALL_NTPS"
        local str="$(get_str CTX_EASYINSTALL_ENV_BEENSET "${tempCtxInstallEnv}")"
        myPrint "${str}"
        ntps="${CTX_EASYINSTALL_NTPS}"
        # Check ntps address if unreachable then exit
        pingAddress "${ntps}"
        local ret=$?
        if [[ ${ret} -ne 0 ]]; then
            local info1="$(get_str CTXINSTALL_UNREACHABLE_ADDRESS ${ntps})"
            myPrint "${info1}"
            local info2="$(get_str CTXINSTALL_DNS_ENV_ERROR "CTX_EASYINSTALL_NTPS")"
            myPrint "${info2}"
            exit 4    
        fi
    # get NTPS from user input
    else
        if [[ "${isSilent}" == "yes" ]]; then
            myLog "Debug: Exit function getNTPS"
            return
        fi
        if [[ -n "$ntps" ]]; then        
            local str0="$(get_str CTXINSTALL_CHANGE_NTPS_CONFIGURATION $ntps)"
            getYesOrNo "${str0}" "n"
            local ret=$?
            if [[ ${ret} -ne 0 ]]; then
                myLog "Debug: Exit function getNTPS"
                return
            fi
        fi   
        [[ -n "$ntps" ]]&&str1="$(get_str CTXINSTALL_INPUT_NTP1_CONFIGURATION $ntps)"   
        [[ -z "$ntps" ]]&&str1="$(get_str CTXINSTALL_INPUT_NTP0_CONFIGURATION)"
        while true ; do
             read -p "$str1" val
             if [[ -z "$val" && -z "$ntps" ]]; then           
                info="$(get_str CTXINSTALL_ERROR_NTP_CONFIGURATION)"
                myPrint "$info"
                continue
             fi
             pingAddress "${val}"
             local ret=$?
             # If the address ${val} is unreachable then input again
             if [[ ${ret} -ne 0 ]]; then
                local info="$(get_str CTXINSTALL_UNREACHABLE_ADDRESS "NTPS")"
                myPrint "${info}"
                continue
             fi
             break
        done
        ntps="$val"
    fi

    myLog "Info: NTP Server =$ntps"
    myLog "Debug: Exit function getNTPS"
}

#
# prompt for inputting realm
#
function getRealm()
{
    myLog "Debug: Enter function getRealm"    
    if [[ -n "${CTX_EASYINSTALL_REALM}" ]]; then
        local tempCtxInstallEnv="CTX_EASYINSTALL_REALM"
        local str="$(get_str CTX_EASYINSTALL_ENV_BEENSET "${tempCtxInstallEnv}")"
        myPrint "${str}"
        realm="${CTX_EASYINSTALL_REALM}"
        
        pingAddress "${realm}"
        local ret=$?
        if [[ ${ret} -ne 0 ]]; then
                local info="$(get_str CTXINSTALL_UNREACHABLE_ADDRESS ${realm})"
                myPrint "${info}"
                exit 4
        fi
            
        REALM=`tr '[a-z]' '[A-Z]' <<<"$realm"`
    else
        if [[ "${isSilent}" == "yes" ]]; then
            exit 4
        fi
        if [[ -n "$realm" ]]; then       
            local str0="$(get_str CTXINSTALL_CHANGE_REALM_CONFIGURATION $realm)"
            getYesOrNo "${str0}" "n"    
            local ret=$?
            if [[ ${ret} -ne 0 ]]; then
                myLog "Debug: Exit function getRealm"
                return
            fi
        fi
        [[ -n "$realm" ]]&&str1="$(get_str CTXINSTALL_INPUT_REALM1_CONFIGURATION  $realm) "
        [[ -z "$realm" ]]&&str1="$(get_str CTXINSTALL_INPUT_REALM0_CONFIGURATION) "
        while true ; do
            read -p "$str1" val
            #ret="$(validateRealm)"
            # if val is null then continue
            if [[ -z "$val" ]]; then          
               local info="$(get_str CTXINSTALL_ERROR_REALM_CONFIGURATION)"
               myPrint "$info"
               continue
            fi 
            # if the val is not reachable then continue
            pingAddress "${val}"
            local ret=$?
            if [[ ${ret} -ne 0 ]]; then
                local info="$(get_str CTXINSTALL_UNREACHABLE_ADDRESS ${val})"
                myPrint "${info}"
                continue
            fi
            break
        done
        realm="$val" 
        REALM=`tr '[a-z]' '[A-Z]' <<<"$realm"`
    fi
    myLog "Info: realm=$realm"
    myLog "Debug: Exit function getRealm"
}

#
# prompt for inputting fqdn
#
function getFqdn()
{
    myLog "Debug: Enter function getFqdn"
    # get AD controller's Fqdn from environment variable 
    if [[ -n "${CTX_EASYINSTALL_FQDN}" ]]; then
        local tempCtxInstallEnv="CTX_EASYINSTALL_FQDN"
        local str="$(get_str CTX_EASYINSTALL_ENV_BEENSET "${tempCtxInstallEnv}")"
        myPrint "${str}"
        fqdn="${CTX_EASYINSTALL_FQDN}"
        FQDN=`tr '[a-z]' '[A-Z]' <<<"$fqdn"`
        # Check whether the FQDN is reachable
        pingAddress "${FQDN}"
        local ret=$?
        # 
        if [[ "${ret}" -ne 0 ]]; then
            local info1="$(get_str CTXINSTALL_UNREACHABLE_ADDRESS "${fqdn}")"
            myPrint "${info1}"
            local info2="$(get_str CTXINSTALL_CHECK_SETUPENV_ERROR "CTX_EASYINSTALL_FQDN")"
            myPrint "${info2}"
            exit 4
        fi
    # get AD controller's Fqdn from user input
    else
        if [[ "${isSilent}" == "yes" ]]; then
            exit 4
        fi
        if [[ -n "$fqdn" ]]; then       
            local str0="$(get_str CTXINSTALL_CHANGE_FQDN_CONFIGURATION $fqdn)"  
            getYesOrNo "${str0}" "n"    
            local ret=$?
            if [[ ${ret} -eq 1 ]]; then
                myLog "Debug: Exit function getFqdn" 
                return
            fi
        fi    
        [[ -n "$fqdn" ]]&&str1="$(get_str CTXINSTALL_INPUT_FQDN1_CONFIGURATION  $fqdn)"
        [[ -z "$fqdn" ]]&&str1="$(get_str CTXINSTALL_INPUT_FQDN0_CONFIGURATION)"
        while true ; do
           read -p "$str1" val
           #ret="$(validateRealm)"
            if [[ -z "$val" ]]; then
                info="$(get_str CTXINSTALL_ERROR_FQDN_CONFIGURATION)"
                myPrint "$info"
                continue
            else 
                pingAddress "${val}"     
                local ret=$?
                if [[ ${ret} -ne 0 ]]; then
                    local info="$(get_str CTXINSTALL_UNREACHABLE_ADDRESS "FQDN")"
                    myPrint "${info}"
                    continue
                fi
            fi
            break
        done
        fqdn="$val"
        FQDN=`tr '[a-z]' '[A-Z]' <<<"$fqdn"`
    fi
    myLog "Info: fqdn=$fqdn"
    myLog "Debug: Exit function getFqdn" 
}

#
# prompt for inputting domain
#
function getDomain()
{
    myLog "Debug: Enter function getDomain"
    # get domain from environment variable 
    if [[ -n "${CTX_EASYINSTALL_DOMAIN}" ]]; then
        local tempCtxInstallEnv="CTX_EASYINSTALL_DOMAIN"
        local str="$(get_str CTX_EASYINSTALL_ENV_BEENSET "${tempCtxInstallEnv}")"
        myPrint "${str}"
        domain="${CTX_EASYINSTALL_DOMAIN}"
        DOMAIN=`tr '[a-z]' '[A-Z]' <<<"$domain"`
    # get domain from user input
    else
        if [[ "${isSilent}" == "yes" ]]; then
            exit 4
        fi
        if [[ -n "$domain" ]]; then
            local str0="$(get_str CTXINSTALL_CHANGE_DOMAIN_CONFIGURATION $domain)"  
            getYesOrNo "${str0}" "n"    
            local ret=$?
            if [[ ${ret} -eq 1 ]]; then
                myLog "Debug: Exit function getDomain"
                return
            fi
        fi
        [[ -n "$domain" ]]&&str1="$(get_str CTXINSTALL_INPUT_DOMAIN1_CONFIGURATION $domain)"
        [[ -z "$domain" ]]&&str1="$(get_str CTXINSTALL_INPUT_DOMAIN0_CONFIGURATION)"
        while true ; do
           read -p "$str1" val
           #ret="$(validateDomain)"
           if [[ -z "$val" ]]; then
              info="$(get_str CTXINSTALL_ERROR_DOMAIN_CONFIGURATION)"
              myPrint "$info"
              continue
           fi
           break
        done
        domain="$val"
        DOMAIN=`tr '[a-z]' '[A-Z]' <<<"$domain"`
    fi
    myLog "Info: domain=$domain"
    myLog "Debug: Exit function getDomain"
}

#
# Get the workgroup
# Two possibilities to get the value of workgroup:
# 1) If file /tmp/ctxinstall.conf exists and contains string workgroup=<value>, get the value from
#    the file
# 2) If file /tmp/ctxinstall.conf does not exist, directly assign the value of $domain to $workgroup
#
function getWorkgroup()
{
    # Reset variables $workgroup and $WORKGROUP to initial value
    # in case user re-input a different value for $domain when $installCfg does not exist
    # refer to LNXVDA-1623 for the details
    myLog "Debug: Enter function getWorkgroup"
    workgroup=""
    WORKGROUP=""

    if [[ -f "$installCfg" ]]; then
       workgroup="$(cat $installCfg |grep workgroup= |cut -d '=' -f2 2>&1)"
       myLog "Info: file $installCfg exists and the value of workgroup is $workgroup"
    else
       myLog "Info: file $installCfg does not exist!"
    fi
 
    [[ -z "$workgroup" ]] && workgroup="$domain"
    WORKGROUP=`tr '[a-z]' '[A-Z]' <<<"$workgroup"`
    myLog "Info: workgroup=$workgroup"
    myLog "Info: WORKGROUP=$WORKGROUP"
    myLog "Debug: Exit function getWorkgroup"
}

#
# Get the OU
# Two possibilities to get the value of OU:
# 1) If file /tmp/ctxinstall.conf exists and contains string ou=<value>, get the value from 
#    the file
# 2) If file /tmp/ctxinstall.conf does not exist, ignore
#
function getOU()
{
    myLog "Debug: Enter function getOU"
    ou=""

    if [[ -f "$installCfg" ]]; then
       ou="$(cat $installCfg |grep ou= |cut -d '=' -f 2- 2>&1)"
       myLog "Info: file $installCfg exists and the value of ou is $ou"
    else
       myLog "Info: file $installCfg does not exist!"
    fi
 
    myLog "Info: ou=$ou"
    myLog "Debug: Exit function getOU"
}

#
# prompt for inputting AD Integration Way
# currently, we support Winbind and SSSD only
#
function getADIntegrationWay()
{
    myLog "Debug: Enter function getADIntegrationWay"
    # get ADIntegrationWay from environment variable
    if [[ -n "${CTX_EASYINSTALL_ADINTEGRATIONWAY}" ]]; then
        local tempCtxInstallEnv="CTX_EASYINSTALL_ADINTEGRATIONWAY"
        local str="$(get_str CTX_EASYINSTALL_ENV_BEENSET "${tempCtxInstallEnv}")"
        myPrint "${str}"
        joinDomainWay="${CTX_EASYINSTALL_ADINTEGRATIONWAY}"
    # get ADIntegrationWay from user input
    else
        if [[ "${isSilent}" == "yes" ]]; then
            exit 4
        fi
        if [[ -n "$joinDomainWay" ]]; then
                local str0="$(get_str CTXINSTALL_CHANGE_DOMAIN_AD_WAY_CONFIGURATION $joinDomainWay)"  
                getYesOrNo "${str0}" "n"    
                local ret=$?
                if [[ ${ret} -eq 1 ]]; then
                      myLog "Debug: Exit function getADIntegrationWay"
                      return
                fi
        fi
        if [[ "${osPlatform}" == "pardus" ]]; then
              str1="$(get_str CTXINSTALL_SELECT_AD_WAY_CONFIGURATION_PARDUS)"
            while true ; do
                  read -p "$str1" val
                  case "$val" in
                       ""|1 )
                       joinDomainWay="winbind" 
                       break
                       ;;
                       2 ) 
                       joinDomainWay="sssd"
                       break
                       ;;                       
                       * )
                       get_str CTXINSTALL_INPUT_CORRECT_AD_WAY_SELECTION 
                       continue
                       ;;
                  esac
             done     
        else
              str1="$(get_str CTXINSTALL_SELECT_AD_WAY_CONFIGURATION)"
            while true ; do
                  read -p "$str1" val
                  case "$val" in
                       ""|1 )
                       joinDomainWay="winbind" 
                       break
                       ;;
                       2 ) 
                       joinDomainWay="sssd"
                       break
                       ;;
                       3 ) 
                       joinDomainWay="centrify"
                       break
                       ;;
                       4 )
                       joinDomainWay="pbis"
                       break
                       ;;
                       * )
                       get_str CTXINSTALL_INPUT_CORRECT_AD_WAY_SELECTION 
                       continue
                       ;;
                  esac
             done
      fi
    fi
    myLog "Info: Active Directory integration way is $joinDomainWay"
    myLog "Debug: Exit function getADIntegrationWay"
}

#
# Configure Host Name
# common function for RHEL/CentOS/Ubuntu platforms
#
function confHostNameRhel()
{
    myLog "Debug: Enter function confHostNameRhel"
    confFile1="/etc/hostname"
    contants1="$hostName"
    local confFile2="/etc/hosts"
    local contants2IPV4="127.0.0.1  $hostName"."$realm $hostName localhost localhost.localdomain localhost4 localhost4.localdomain4"
    local contants2IPV6="::1  $hostName"."$realm $hostName localhost localhost.localdomain localhost6 localhost6.localdomain6"
    # Backup configuration files
    `cp "$confFile1" "$backupDir"`
    `cp /etc/hosts "$backupDir"`
    # update the contents
    # configure hostname
    echo "$contants1">"$confFile1"

    # configure hosts
    sed -i "s/^127.0.0.1/#127.0.0.1/" "${confFile2}"
    sed -i "s/^::1/#::1/" "${confFile2}"
    echo "${contants2IPV4}" >> "${confFile2}"
    echo "${contants2IPV6}" >> "${confFile2}"

    sysctl -w kernel.hostname="$hostName"  2>&1 >> "$logFile"
    if [[ "$?" -ne "0" ]]; then
        local info="$(get_str CTXINSTALL_SET_HOSTNAME_FAIL ${hostName})"
        myPrint "${info}"
        exit 4        
    fi
    myLog "Debug: $confFile1: $contants1"
    myLog "Debug: $confFile2: $contants2"
    myLog "Debug: Exit function confHostNameRhel"
}

function disableMultiDNSbyNSS()
{
    local mdnsConfigFile="/etc/nsswitch.conf"
    [[ ! -f "${mdnsConfigFile}" ]] && myLog "Warning: file $mdnsConfigFile does not exist!" && myLog "Debug: Exit function disableMultiDNSbyNSS" && return
    `cp "$mdnsConfigFile" "$backupDir"`
    `sed -i 's/^hosts:.*\[NOTFOUND=return\].*$/hosts:          files dns/I;/dns/!s/^hosts:.*$/hosts:          files dns/' "$mdnsConfigFile"`
    [[ "$?" -ne "0" ]] && myLog "Failed to disable Multicast DNS[Warning]."
}

function overrideResolvByNetworkManager()
{
    local nmDir="/etc/NetworkManager/dispatcher.d"
    [[ ! -d "${nmDir}" ]] && myLog "Debug: directory $nmDir does not exist!" && myLog "Debug: Exit function overrideResolvByNetworkManager" && return

    local customFile="/etc/resolv.conf.custom"
    [[ -n "$dns1" ]] && echo "nameserver $dns1">"$customFile"
    [[ -n "$dns2" ]] && echo "nameserver $dns2">>"$customFile"
    [[ -n "$dns3" ]] && echo "nameserver $dns3">>"$customFile"
    [[ -n "$dns4" ]] && echo "nameserver $dns4">>"$customFile"

    local resolvFile="${nmDir}/15-resolv"
    echo "#!/bin/bash
    #
    # Description : script to override default resolv.conf file
    # with customized file.
    cp -f /etc/resolv.conf.custom /etc/resolv.conf">"$resolvFile"
    chmod +x "$resolvFile"
}

function overrideResolvByDhclient()
{
    local dhcpClientFile="/etc/dhcp/dhclient.conf"
    [[ ! -f "${dhcpClientFile}" ]] && myLog "Warning: file $dhcpClientFile does not exist!" && myLog "Debug: Exit function overrideResolvByDhclient" && return
    `cp "$dhcpClientFile" "$backupDir"`
    `sed -i '/^prepend.*domain-name-servers.*$/d' "$dhcpClientFile"`
    [[ -n "$dns1" ]] && echo "prepend domain-name-servers $dns1">>"$dhcpClientFile"
    [[ -n "$dns2" ]] && echo "prepend domain-name-servers $dns2">>"$dhcpClientFile"
    [[ -n "$dns3" ]] && echo "prepend domain-name-servers $dns3">>"$dhcpClientFile"
    [[ -n "$dns4" ]] && echo "prepend domain-name-servers $dns4">>"$dhcpClientFile"
}

function overrideResolvByInterface()
{
    local interfaceConfigFile="/etc/network/interfaces"
    `sed -i '/dns-nameservers.*$/d' "$interfaceConfigFile"`
    [[ -n "$dns1" ]] && echo "dns-nameservers $dns1">>"$interfaceConfigFile"
    [[ -n "$dns2" ]] && echo "dns-nameservers $dns2">>"$interfaceConfigFile"
    [[ -n "$dns3" ]] && echo "dns-nameservers $dns3">>"$interfaceConfigFile"
    [[ -n "$dns4" ]] && echo "dns-nameservers $dns4">>"$interfaceConfigFile"
}

function stopDHCPChangingResolv()
{ 
    local dhcpHookDir="/etc/dhcp/dhclient-enter-hooks.d/"
    if [[ ! -d "${dhcpHookDir}" ]]; then
        mkdir -p "${dhcpHookDir}"
    fi
    local dhcpHook="/etc/dhcp/dhclient-enter-hooks.d/nodnsupdate"
    [[ -f "$dhcpHook" ]] && `cp "$dhcpHook" "$backupDir"`
    echo "#!/bin/bash
make_resolv_conf(){
    :
}" > $dhcpHook
}

#
# Configure DNS
# common function for RHEL/CentOS/Ubuntu/Pardus platforms
#
function confDNS()
{
    myLog "Debug: Enter function confDNS"
    [[ -z "$dns1" && -z "$dns2" && -z "$dns3" && -z "$dns4" ]] && myLog "Debug: No dns" && myLog "Debug: Exit function confDNS" && return
    version=${osVersion:0:1}
    dnsFile="/etc/resolv.conf"
    
    [[ -f "$dnsFile" ]] && `cp "$dnsFile" "$backupDir"`   
    `sed -i '/^nameserver.*$/d' "$dnsFile"`   
    [[ -n "$dns1" ]] && str1="nameserver $dns1" && echo "$str1">>"$dnsFile"
    [[ -n "$dns2" ]] && str1="nameserver $dns2" && echo "$str1">>"$dnsFile"
    [[ -n "$dns3" ]] && str1="nameserver $dns3" && echo "$str1">>"$dnsFile"
    [[ -n "$dns4" ]] && str1="nameserver $dns4" && echo "$str1">>"$dnsFile"
    
    # Disable Multicast DNS
    if [[ "$osPlatform" == "red" || "$osPlatform" == "centos" || "$osPlatform" == "amzn" || "$osPlatform" == "rocky" ]]; then    
        dir="/etc/sysconfig/network-scripts"
        FILELIST=`ls $dir/ifcfg-eth* 2>>"$logFile" | grep -v "\."`
        #In case of Predictable Network Interface Names(from Systemd v197 )
        [[ -z $FILELIST ]] && FILELIST=`ls $dir/ifcfg-en* 2>>"$logFile" | grep -v "\."`
        [[ -z $FILELIST ]] && myLog "Warning: Network Interface configuration file does not exist!" && myLog "Debug: Exit function confDNS" && return
        for file in $FILELIST
        do
            `sed -i '/^PEERDNS=*/s/^/#/' $file`
            `sed -i '/^DNS./s/^/#/' "$file"`
            if [[ -f "$file" ]]; then
                    echo "PEERDNS=no">>"$file"           
                    [[ -n "$dns1" ]] && echo "DNS1=$dns1">>"$file"
                    [[ -n "$dns2" ]] && echo "DNS2=$dns2">>"$file"
                    [[ -n "$dns3" ]] && echo "DNS3=$dns3">>"$file"
                    [[ -n "$dns4" ]] && echo "DNS4=$dns4">>"$file"
            fi
        done 
        
        # on RHEL workstation, service NetworkManager will automatically fetch DHCP DNS 
        # and insert into /etc/resolv.conf, this will block DNS search, in order to solve this issue, 
        # we create a new /etc/resolv.conf.custom file and put the correct DNS entries to it, when
        # NetworkManager restarted, we will use this file to overwrite /etc/resolv.conf.
        #if [[  "$version" == "7" && "$osType" == "workstation" ]]; then
            customFile="/etc/resolv.conf.custom"           
            [[ -n "$dns1" ]] && echo "nameserver $dns1">"$customFile"
            [[ -n "$dns2" ]] && echo "nameserver $dns2">>"$customFile"
            [[ -n "$dns3" ]] && echo "nameserver $dns3">>"$customFile"
            [[ -n "$dns4" ]] && echo "nameserver $dns4">>"$customFile"
            copyFile="/etc/NetworkManager/dispatcher.d/15-resolv"
            echo "#!/bin/bash
            #
            # Description : script to override default resolv.conf file
            # with customized file.
            cp -f /etc/resolv.conf.custom /etc/resolv.conf">"$copyFile"     
            chmod +x "$copyFile"
            #fi
        
        
    elif [[ "$osPlatform" == "ubuntu" ]]; then
        # DNS has different configuration between on-premise and azure
        if [[ "$osVersion" == "18.04" || "$osVersion" == "20.04" ]]; then
            customFile="/etc/resolv.conf.custom"           
            [[ -n "$dns1" ]] && echo "nameserver $dns1">"$customFile"
            [[ -n "$dns2" ]] && echo "nameserver $dns2">>"$customFile"
            [[ -n "$dns3" ]] && echo "nameserver $dns3">>"$customFile"
            [[ -n "$dns4" ]] && echo "nameserver $dns4">>"$customFile"
            copyFile="/etc/NetworkManager/dispatcher.d/15-resolv"
            echo "#!/bin/bash
            #
            # Description : script to override default resolv.conf file
            # with customized file.
            cp -f /etc/resolv.conf.custom /etc/resolv.conf">"$copyFile"     
            chmod +x "$copyFile"
        fi

        disableMultiDNSbyNSS

        if [[ ! -d "/dev/disk/azure" ]]; then
            configFile="/etc/network/interfaces"

            if [[ -f "/etc/systemd/system/multi-user.target.wants/google-accounts-daemon.service" ]] &&
                [[ "$osVersion" == "16.04" ]]; then
                # This file is unique to Google Cloud Platform. Add dns-nameservers in $configFile will cause network failed.
                myLog "Debug: in GCP not config"
            elif [[ -f "/etc/systemd/system/snap.amazon-ssm-agent.amazon-ssm-agent.service" ]] &&
                [[ "$osVersion" == "16.04" ]]; then
                # This file is unique to AWS. Add dns-nameservers in $configFile will cause network failed.
                myLog "Debug: in AWS not config"
            else
                `sed -i '/dns-nameservers.*$/d' "$configFile"`
                [[ -n "$dns1" ]] && echo "dns-nameservers $dns1">>"$configFile"
                [[ -n "$dns2" ]] && echo "dns-nameservers $dns2">>"$configFile"
                [[ -n "$dns3" ]] && echo "dns-nameservers $dns3">>"$configFile"
                [[ -n "$dns4" ]] && echo "dns-nameservers $dns4">>"$configFile"
            fi
        else
            configFile="/etc/dhcp/dhclient.conf"
            [[ ! -f "${configFile}" ]] && myLog "Warning: file $configFile does not exist!" && myLog "Debug: Exit function confDNS" && return
            `cp "$configFile" "$backupDir"`
            `sed -i '/^prepend.*domain-name-servers.*$/d' "$configFile"`
            [[ -n "$dns1" ]] && echo "prepend domain-name-servers $dns1">>"$configFile"
            [[ -n "$dns2" ]] && echo "prepend domain-name-servers $dns2">>"$configFile"
            [[ -n "$dns3" ]] && echo "prepend domain-name-servers $dns3">>"$configFile"
            [[ -n "$dns4" ]] && echo "prepend domain-name-servers $dns4">>"$configFile"
        fi
    elif [[ "$osPlatform" == "suse" ]]; then
        # Disable Multicast DNS
        configFile="/etc/nsswitch.conf"
        [[ ! -f "${configFile}" ]] && myLog "Warning: file $configFile does not exist!" && myLog "Debug: Exit function confDNS" && return
        `cp "$configFile" "$backupDir"`   
        `sed -i 's/^.*mdns_minimal.*$/hosts:       files dns/g' "$configFile"`
        [[ "$?" -ne "0" ]] && myLog "Failed to disable Multicast DNS[Warning]." && configurationStatus="Warning"
 
        # Name Server - Add the IP address of the DNS server. This is typically the IP address of the AD Domain Controller.
        # Domain Search list - Add the DNS domain name.
        configFile="/etc/sysconfig/network/config"
        [[ ! -f "${configFile}" ]] && myLog "Warning: file $configFile does not exist!" && myLog "Debug: Exit function confDNS" && return
        [[ -f "$configFile" ]] && `cp "$configFile" "$backupDir"`   
        
        sed -i 's/^NETCONFIG_DNS_POLICY.*$/NETCONFIG_DNS_POLICY=\"STATIC\"/g' "$configFile"
        sed -i "s/^NETCONFIG_DNS_STATIC_SEARCHLIST.*$/NETCONFIG_DNS_STATIC_SEARCHLIST=\"$realm\"/g" "$configFile"
        sed -i 's/^NETCONFIG_DNS_FORWARDER.*$/NETCONFIG_DNS_FORWARDER=\"bind\"/g' "$configFile"
        sed -i '/NETCONFIG_DNS_STATIC_SERVERS.*$/d' "$configFile"
        #ret="$(validIP $dns2)"
        #ipAddr="$dns2"
        #ipAddr="$(getent hosts $dns2 | awk '{ print $1 }')"
        [[ -n "$dns1" ]] && echo "NETCONFIG_DNS_STATIC_SERVERS=$dns1">>"$configFile"
        [[ -n "$dns2" ]] && echo "NETCONFIG_DNS_STATIC_SERVERS=$dns2">>"$configFile"
        [[ -n "$dns3" ]] && echo "NETCONFIG_DNS_STATIC_SERVERS=$dns3">>"$configFile"
        [[ -n "$dns4" ]] && echo "NETCONFIG_DNS_STATIC_SERVERS=$dns4">>"$configFile" 

    elif [[ "$osPlatform" == "pardus" ]]; then
        disableMultiDNSbyNSS

        overrideResolvByDhclient

        overrideResolvByNetworkManager
    elif [[ "$osPlatform" == "debian" ]]; then
        disableMultiDNSbyNSS
        overrideResolvByNetworkManager
        if [[ -d "/etc/cloud" || -f "/etc/google_instance_id" ]]; then
            # Cloud platforms
            cloudCfg="/etc/cloud/cloud.cfg"
            if [[ -f "$cloudCfg" ]]; then
                `sed -i '/manage_etc_hosts.*$/d' "$cloudCfg"` 
                echo "manage_etc_hosts:false">>"$cloudCfg"
            fi
            overrideResolvByDhclient
        else
            overrideResolvByInterface
        fi
        stopDHCPChangingResolv
    fi
    
    myLog "Debug: Check if env uses IPv6 dns server"
    useIPv6

    myLog "Debug: Exit function confDNS"
}

#
# Configure NTP
# common function for RHEL/CentOS platforms
#
function confNTPSRhel()
{
    myLog "Debug: Enter function confNTPSRhel"
    version="${osVersion:0:1}"
    [[ "$version" == "7" || "$version" == "8" || "$version" == "2" ]]&&ntpFile="/etc/chrony.conf"
    [[ -f "$ntpFile" ]] && `cp -f "$ntpFile" "$backupDir"`
    `sed -i 's/^server.*$/#&/g' "$ntpFile"`
    `sed -i 's/^pool.*$/#&/g' "$ntpFile"`
    [[ -n "$ntps" ]] && echo "server $ntps iburst">>"$ntpFile"
    if [[ "$version" == "7" || "$version" == "8" || "$version" == "2" ]]; then
        `sed -i 's/^maxdistance.*$/#&/g' "$ntpFile"`
	[[ -n "$ntps" ]] && echo "maxdistance 16">>"$ntpFile"
    fi

    # stop,  sync date, Restart the service
    
    [[ "${osPlatform}" == "centos" && "$version" == "7" ]] && startCmd="/usr/bin/systemctl start chronyd" && stopCmd="/usr/bin/systemctl stop chronyd"
    [[ "${osPlatform}" == "red" && "$version" == "7" ]] && startCmd="/usr/bin/systemctl start chronyd" && stopCmd="/usr/bin/systemctl stop chronyd"
    [[ "${osPlatform}" == "red" && "$version" == "8" ]] && startCmd="/usr/bin/systemctl start chronyd" && stopCmd="/usr/bin/systemctl stop chronyd"
    [[ "${osPlatform}" == "rocky" && "$version" == "8" ]] && startCmd="/usr/bin/systemctl start chronyd" && stopCmd="/usr/bin/systemctl stop chronyd"
    [[ "${osPlatform}" == "amzn" && "$version" == "2" ]] && startCmd="/usr/bin/systemctl start chronyd" && stopCmd="/usr/bin/systemctl stop chronyd"

    $stopCmd >> "$logFile" 2>&1
    if [[ "$version" == "7" || "$version" == "8" || "$version" == "2" ]]; then
        [[ -n "$ntps" ]] && chronyc -a makestep >> "$logFile" 2>&1
    fi
    [[ "$?" -ne "0" ]] && myLog "failed to sync time with NTP server($ntps)[Warning]." && configurationStatus="Warning"
    $startCmd >> "$logFile" 2>&1
    [[ "$?" -ne "0" ]] && configurationStatus="Error"
    myLog "Debug: Exit function confNTPSRhel"
}

#
# Configure NTP
# Dedicated for Ubuntu platforms
#
function confNTPSUbuntu()
{
    myLog "Debug: Enter function confNTPSUbuntu"
    ntpFile="/etc/chrony/chrony.conf"
    [[ -f "$ntpFile" ]] && `cp -f "$ntpFile" "$backupDir"`
    #`sed -i 's/^server.*iburst$/#&/g' "$ntpFile"`
    #`sed -i 's/^pool.*iburst$/#&/g' "$ntpFile"`
    `sed -i 's/^server.*$/#&/g' "$ntpFile"`
    `sed -i 's/^pool.*$/#&/g' "$ntpFile"`
    [[ -n "$ntps" ]] && echo "server $ntps iburst">>"$ntpFile"

    # stop,  sync date, Restart the service
    sudo systemctl stop chrony >>"$ntpFile" 2>&1
    [[ -n "$ntps" ]] && /usr/sbin/ntpdate "$ntps" >> "$logFile" 2>&1
    [[ "$?" -ne "0" ]] && myLog "failed to sync time with NTP server($ntps)[Warning]." && configurationStatus="Warning"
    sudo systemctl start chrony >>"$ntpFile" 2>&1
    [[ "$?" -ne "0" ]] && myLog "Error: failed to start service chrony." && configurationStatus="Error"
    myLog "Debug: Exit function confNTPSUbuntu"
}

#
# Customize configuration for Winbind AD Integration
# common function for RHEL/CentOS platforms
#
function confADRhelWinbind()
{
    myLog "Debug: Enter function confADRhelWinbind" 
    # Install package
    winbindPkgListTmp=""
    if [[ "${osPlatform}" == "red" && "$version" == "8" ]]; then
        winbindPkgListTmp=(${winbindPkgListRed8[@]})
    else
        winbindPkgListTmp=(${winbindPkgList[@]})
    fi

    winbindPkgListNum=${#winbindPkgListTmp[@]}
    for((i=0;i<winbindPkgListNum;i++)); do
        info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "$winbindPkgListNum" "${winbindPkgListTmp[$i]}")"
        myPrint "$info"
        $YUM -y install "${winbindPkgListTmp[$i]}" >> "$logFile" 2>&1
        if [[ "$?" -ne "0" ]]; then
           info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${winbindPkgListTmp[$i]}")"
           configurationStatus="Error"
           $YUM info "${winbindPkgListTmp[$i]}" >> "$logFile" 2>&1
           [[ "$?" -ne "0" ]] && myPrint "$info" && exit 4
        fi
    done
    # Enable Winbind Daemon
    #`sudo chkconfig winbind on`
    enableService "winbind"
    [[ "$?" -ne "0" ]] && myLog "Error: failed to enable service winbind." && configurationStatus="Error"
    #Configure Winbind Authentication
    local val=""

    if [[ "$version" == "8" ]]; then
       str="authselect select winbind with-mkhomedir --force"
       myLog "Execute command: \" ${str} \" "
       authselect select winbind with-mkhomedir --force >/dev/null 2>&1
       val="$?"
    else
        if [[ -z "$dns1" && -z "$dns2" && -z "$dns3" && -z "$dns4" ]]; then
           str="authconfig --disablecache --disablesssd --disablesssdauth --enablewinbind --enablewinbindauth --disablewinbindoffline --smbsecurity=ads --smbworkgroup=$workgroup --smbrealm=$REALM --krb5realm=$REALM --krb5kdc=$FQDN --winbindtemplateshell=/bin/bash --enablemkhomedir --updateall"
           myLog "Execute command: \" ${str} \" "
           authconfig --disablecache --disablesssd --disablesssdauth --enablewinbind --enablewinbindauth --disablewinbindoffline --smbsecurity=ads --smbworkgroup=$workgroup --smbrealm=$REALM --krb5realm=$REALM --krb5kdc=$FQDN --winbindtemplateshell=/bin/bash --enablemkhomedir --updateall >> "$logFile" 2>&1
           val="$?"
        else
            str="authconfig --disablecache --disablesssd --disablesssdauth --enablewinbind --enablewinbindauth --disablewinbindoffline --smbsecurity=ads --smbworkgroup=$workgroup --smbrealm=$REALM --krb5realm=$REALM --krb5kdc=$FQDN --winbindtemplateshell=/bin/bash --enablemkhomedir --updateall --enablekrb5kdcdns --enablekrb5realmdns"
            myLog "Execute command: \" ${str} \" "
            authconfig --disablecache --disablesssd --disablesssdauth --enablewinbind --enablewinbindauth --disablewinbindoffline --smbsecurity=ads --smbworkgroup=$workgroup --smbrealm=$REALM --krb5realm=$REALM --krb5kdc=$FQDN --winbindtemplateshell=/bin/bash --enablemkhomedir --updateall --enablekrb5kdcdns --enablekrb5realmdns >> "$logFile" 2>&1
            val="$?"
        fi
    fi

    if [[ "$val" -ne "0" ]]; then
        info="$(get_str CTXINSTALL_FAIL_TO_EXECUTE)"
        myPrint "$info \" $str\"" 
        exit 4
    fi 
    smbFile="/etc/samba/smb.conf"
    krbFile="/etc/krb5.conf"
    pamFile="/etc/security/pam_winbind.conf"

    [[ -f "$smbFile" ]] && `cp -f "$smbFile" "$backupDir"`
    [[ -f "$krbFile" ]] && `cp -f "$krbFile" "$backupDir"`
    [[ -f "$pamFile" ]] && `cp -f "$pamFile" "$backupDir"`
    # Customize /etc/samba/smb.conf
    if [[ "$version" != "8" ]]; then
        `sed -i '/kerberos method =.*$/d' "$smbFile"`
        `sed -i '/winbind refresh tickets =.*$/d' "$smbFile"`      # del line in case user execute the script multi times
        `sed -i '/\[global\]/a winbind refresh tickets = true' "$smbFile"`
        `sed -i '/\[global\]/a kerberos method = secrets and keytab' "$smbFile"`
    fi

    # Customize /etc/krb5.conf
    #`sed -i 's#default_ccache_name.*$#default_ccache_name = FILE:/tmp/krb5cc_%{uid}#g' "$krbFile"`
    `sed -i '/default_ccache_name.*$/d' "$krbFile"`
    `sed -i '/\[libdefaults\]/a default_ccache_name = FILE:/tmp/krb5cc_%{uid}' "$krbFile"`

    if [[ "$version" == "8" ]]; then
        `sed -i '/[^#].*default_realm/d' "$krbFile"`
        `sed -i '/[^#].*dns_lookup_kdc/d' "$krbFile"`
        `sed -i "/^\[realms\]/i\    default_realm = $REALM\n    dns_lookup_kdc = true\n" "$krbFile"`

        `sed -i '/^.*\[realms\]/{:a;n;/^.*\[domain_realm\]/q;s/^[^#]/#&/;ba}' "$krbFile"`
        `sed -i "/^\[domain_realm\]/i\ $REALM = {\n     kdc = $fqdn\n }\n" "$krbFile"`

        `sed -i '/^.*\[domain_realm\]/{:a;n;/$/s/^[^#].*/#&/;ba}' "$krbFile"`
        `sed -i '$a\ '$realm' = '$REALM'\n .'$realm' = '$REALM'' "$krbFile"`
    fi

    # under certain case, some lines are not commented out, we need to remove them

    # Customize /etc/security/pam_winbind.conf
    `sed -i 's/.*krb5_auth =.*$/krb5_auth = yes/g' "$pamFile"`
    `sed -i 's/.*krb5_ccache_type =.*$/krb5_ccache_type = FILE/g' "$pamFile"`
    `sed -i 's/.*mkhomedir =.*$/mkhomedir = yes/g' "$pamFile"`
    myLog "Debug: Exit function confADRhelWinbind" 
}

#
# Customize configuration for Winbind AD Integration
# Dedicated for Ubuntu platforms
#
function confADUbuntuWinbind()
{
    myLog "Debug: Enter function confADUbuntuWinbind" 
     # Install package
     winbindPkgListNum=${#winbindPkgListUbuntu[@]}
     for((i=0;i<winbindPkgListNum;i++)); do
          info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "$winbindPkgListNum" "${winbindPkgListUbuntu[$i]}")"
          myPrint "$info"          
          info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${winbindPkgListUbuntu[$i]}")"          
          apt-get -y install "${winbindPkgListUbuntu[$i]}" >> "$logFile" 2>&1
          [[ "$?" -ne "0" ]] && myPrint "$info" && exit 4
     done

     # customize configuration files
     krbFile="/etc/krb5.conf"
     smbFile="/etc/samba/smb.conf"
     nsswitchFile="/etc/nsswitch.conf"
  
     # backup configuration 
     [[ -f "$krbFile" ]] && `cp -f "$krbFile" "$backupDir"` >> "$logFile"
     [[ -f "$smbFile" ]] && `cp -f "$smbFile" "$backupDir"` >> "$logFile"
     [[ -f "$nsswitchFile" ]] && `cp -f "$nsswitchFile" "$backupDir"` >> "$logFile"

     # Customize /etc/krb5.conf
     ## Following lines are to Customize the krb5.conf file(keep other entries that has nothing to do with 
     ## winbind unchanged, keep them here in case we need to use them later. 
     #`sed -i '/default_realm = .*$/d' "$krbFile"`    # delete line default_realm = *
     #`sed -i '/dns_lookup_kdc = .*$/d' "$krbFile"`   # delete line dns_lookup_kdc = false 
     #`sed -i '/\[libdefaults\]/a dns_lookup_kdc = false' "$krbFile"`
     #`sed -i "/\[libdefaults\]/a default_realm = $REALM" "$krbFile"`
     #`sed -i '/^.*\[realms\].*$/,$d'  "$krbFile"` # delete all lines after [realms]
     #echo "[realms]
     #$REALM = {
     # admin_server = $FQDN
     # kdc = $FQDN
     # }
     #[domain_realm]
     #$realm = $REALM
     #.$realm = $REALM">>"$krbFile"

     echo "[libdefaults]
     default_realm = $REALM
     dns_lookup_kdc = false
 
     [realms]
     $REALM = {
        admin_server = $FQDN
        kdc = $FQDN
     }

     [domain_realm]
        $realm = $REALM
        .$realm = $REALM">"$krbFile"
 
     # Customize /etc/samba/smb.conf
     ## Following lines are to Customize the smb.conf file(keep other entries that has nothing to do with
     ## winbind unchanged, keep them here in case we need to use them later.

     #`sed -i '/workgroup = .*$/d' "$smbFile"` 
     #`sed -i "/\[global\]/a workgroup = $REALM" "$smbFile"`
     #`sed -i '/realm = .*$/d' "$smbFile"`
     #`sed -i "/\[global\]/a realm = $REALM" "$smbFile"`
     #`sed -i '/kerberos method = .*$/d' "$smbFile"`
     #`sed -i "/\[global\]/a kerberos method = secrets and keytab" "$smbFile"` 
     #`sed -i '/winbind refresh tickets =.*$/d' "$smbFile"`
     #`sed -i '/\[global\]/a winbind refresh tickets = true' "$smbFile"` 
     #`sed -i '/template shell = .*$/d' "$smbFile"`
     #`sed -i '#\[global\]#a template shell = \/bin\/bash' "$smbFile"`
     echo "[global]
     workgroup = $WORKGROUP
     security = ADS
     realm = $REALM
     encrypt passwords = yes
     idmap config *:range = 16777216-33554431
     winbind trusted domains only = no
     winbind use default domain = yes
     kerberos method = secrets and keytab
     winbind refresh tickets = yes
     template shell = /bin/bash">"$smbFile"

     if [[ "${osVersion}" == "20.04" ||  "${osPlatform}" == "debian" ]]; then
        sed -i '/winbind trusted domains only/d' "$smbFile"
     fi

     # Customize /etc/nsswitch.conf
     passwdLine="$(cat $nsswitchFile |grep passwd |grep winbind 2>&1)"
     groupLine="$(cat $nsswitchFile |grep group |grep winbind 2>&1)"
     
     [[ -z "$passwdLine" ]] && `sed -i 's/passwd:.*$/& winbind/g' "$nsswitchFile"`
     [[ -z "$groupLine" ]] && `sed -i 's/group:.*$/& winbind/g' "$nsswitchFile"`

    myLog "Debug: Exit function confADUbuntuWinbind"
}

#
# Customize configuration for SSSD AD Integration
# common function for RHEL/CentOS platforms
#
function confADRhelSssd()
{
    myLog "Debug: Enter function confADRhelSssd"
    krbFile="/etc/krb5.conf"
    sssdFile="/etc/sssd/sssd.conf"
    krbConfFile="/etc/krb5.conf.d/kcm_default_ccache"
    smbFile="/etc/samba/smb.conf"

    #Configure the machine for Samba and Kerberos authentication
    local val=""
    if [[ "$version" == "8" ]]; then
        # comment "default_ccache_name = KCM:" line in /etc/krb5.conf.d/kcm_default_ccache, sssd will use FILE
        `sed -i 's/.*default_ccache_name = KCM:.*/#&/g' "${krbConfFile}"`
        str="authselect select sssd with-mkhomedir --force"
        myLog "Execute command: \" ${str} \" "
        authselect select sssd with-mkhomedir --force >> "$logFile" 2>&1
        val="$?"
    else
        if [[ -z "$dns1" && -z "$dns2" && -z "$dns3" && -z "$dns4" ]]; then
           str="authconfig --smbsecurity=ads --smbworkgroup=$workgroup --smbrealm=$REALM --krb5realm=$REALM --krb5kdc=$FQDN --update"
           myLog "Execute command: \" $str \" "
           authconfig --smbsecurity=ads --smbworkgroup=$workgroup --smbrealm=$REALM --krb5realm=$REALM --krb5kdc=$FQDN --update >> "$logFile" 2>&1
           val="$?"
        else
           str="authconfig --smbsecurity=ads --smbworkgroup=$workgroup --smbrealm=$REALM --krb5realm=$REALM --krb5kdc=$FQDN --update --enablekrb5kdcdns --enablekrb5realmdns"
           myLog "Execute command: \" $str \" "
           authconfig --smbsecurity=ads --smbworkgroup=$workgroup --smbrealm=$REALM --krb5realm=$REALM --krb5kdc=$FQDN --update --enablekrb5kdcdns --enablekrb5realmdns  >> "$logFile" 2>&1
           val="$?"
        fi
    fi
    if [[ "$val" -ne "0" ]]; then
        info="$(get_str CTXINSTALL_FAIL_TO_EXECUTE)"
        myPrint "$info \" ${str} \" "
        exit 4
    fi

     # Customize /etc/samba/smb.conf
     [[ -f "$smbFile" ]] && `cp -f "$smbFile" "$backupDir"` >> "$logFile"
     `sed -i '/kerberos method =.*$/d' "$smbFile"`
     `sed -i '/\[global\]/a kerberos method = secrets and keytab' "$smbFile"`
  
     # Customize /etc/krb5.conf 
     [[ -f "$krbFile" ]] && `cp -f "$krbFile" "$backupDir"` >> "$logFile"
     `sed -i '/default_ccache_name.*$/d' "$krbFile"`
     `sed -i '/\[libdefaults\]/a default_ccache_name = FILE:/tmp/krb5cc_%{uid}' "$krbFile"`
     if [[ "$version" == "8" ]]; then
        `sed -i '/[^#].*default_realm/d' "$krbFile"`
        `sed -i '/[^#].*dns_lookup_kdc/d' "$krbFile"`
        `sed -i "/^\[realms\]/i\    default_realm = $REALM\n    dns_lookup_kdc = true\n" "$krbFile"`

        `sed -i '/^.*\[realms\]/{:a;n;/^.*\[domain_realm\]/q;s/^[^#]/#&/;ba}' "$krbFile"`
        `sed -i "/^\[domain_realm\]/i\ $REALM = {\n     kdc = $fqdn\n }\n" "$krbFile"`

        `sed -i '/^.*\[domain_realm\]/{:a;n;/$/s/^[^#].*/#&/;ba}' "$krbFile"`
        `sed -i '$a\ '$realm' = '$REALM'\n .'$realm' = '$REALM'' "$krbFile"`
    fi

     # setup SSSD
     # 1) Install or Update Required Packages
     if [[ $osVersion == 7.* || $osVersion == 2 ]]
     then
         sssdPkgList=("krb5-workstation" "sssd" "authconfig" "oddjob-mkhomedir" "samba-common-tools")
     elif [[ $osVersion == 8.* ]]
     then   
         sssdPkgList=("krb5-workstation" "sssd" "oddjob" "oddjob-mkhomedir" "samba-common" "adcli" "samba-common-tools")
     fi
     sssdPkgNum=${#sssdPkgList[@]}
     for((i=0;i<sssdPkgNum;i++)); do
         info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "$sssdPkgNum" "${sssdPkgList[$i]}")"
         myPrint "$info"
         info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${sssdPkgList[$i]}" )"
         sudo yum -y install "${sssdPkgList[$i]}" >> "$logFile" 2>&1
         retVal="$?"
     done

     # 2) Modify SSSD Configuration(/etc/sssd/sssd.conf)
     # back up /etc/sssd/sssd.conf if it exists
     [[ -f "$sssdFile" ]] && `cp -f "$sssdFile" "$backupDir"`
     [[ ! -d '/etc/sssd' ]] && mkdir  /etc/sssd
     [[ ! -f "$sssdFile" ]] && touch "$sssdFile"
    
     echo "[sssd] 
config_file_version = 2
domains = $realm  
services = nss,pam

[domain/$realm]
id_provider = ad 
auth_provider = ad       
access_provider = ad
ldap_id_mapping = true 
ldap_schema = ad

ad_server = $fqdn
ad_domain = $realm
  
# Kerberos settings
krb5_ccachedir = /tmp
krb5_ccname_template = FILE:%d/krb5cc_%U
override_homedir = /home/%d/%u
fallback_homedir = /home/%d/%u
default_shell = /bin/bash">"${sssdFile}"

     # Set the file ownership and permissions on sssd.conf
     chown root:root "$sssdFile"
     chmod 0600 "$sssdFile"
     restorecon  "$sssdFile"

     if [[ "$version" != "8" ]]; then
         sudo authconfig --enablesssdauth --enablesssd --enablemkhomedir --update >> "$logFile" 2>&1
     fi
     [[ "$?" -ne "0" ]] && configurationStatus="Error"
     myLog "Debug: Exit function confADRhelSssd"
}

#
# Customize configuration for SSSD AD Integration
# Dedicated for Ubuntu platforms
#
function confADUbuntuSssd()
{
     myLog "Debug: Enter function confADUbuntuSssd"
     krbFile="/etc/krb5.conf"
     sssdFile="/etc/sssd/sssd.conf"
     smbFile="/etc/samba/smb.conf"

     # back up configuration files
     [[ -f "$sssdFile" ]] && `cp -f "$sssdFile" "$backupDir"`
     [[ -f "$smbFile" ]] && `cp -f "$smbFile" "$backupDir"`
     pkgList=("krb5-user" "samba" "sssd")
     for((i=0;i<${#pkgList[@]};i++)); do
         info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" ${#pkgList[@]} ${pkgList[$i]})"
         myPrint "$info" 
         apt-get -y install "${pkgList[$i]}">> "$logFile"
         [[ "$?" -ne "0" ]] && myLog "failed to install package ${pkgList[$i]}[Error]" && exit 4
     done

     # Customize /etc/krb5.conf
     [[ -f "$krbFile" ]] && cp -f "$krbFile" "$backupDir" >> "$logFile"
     if [[ "$osPlatform" == "debian" ]]; then
        echo "[libdefaults]
     default_realm = $REALM
        dns_lookup_kdc = false
        rdns = false

     [realms]
     $REALM = {
        admin_server = $FQDN
        kdc = $FQDN
     }

     [domain_realm]
        $realm = $REALM
        .$realm = $REALM">"$krbFile"
    else
        echo "[libdefaults]
     default_realm = $REALM
        dns_lookup_kdc = false

     [realms]
     $REALM = {
        admin_server = $FQDN
        kdc = $FQDN
     }

     [domain_realm]
        $realm = $REALM
        .$realm = $REALM">"$krbFile"
    fi

     # Customize /etc/samba/smb.conf
     echo "[global]
       workgroup = $WORKGROUP
       security = ADS
       realm = $REALM
       client signing = yes
       client use spnego = yes
       kerberos method = secrets and keytab">"$smbFile"

     # Update sssd package
     myLog "update all installed packages"
     apt-get -y update >> "$logFile"
  
     # Customize /etc/sssd/sssd.conf
     [[ ! -d "/etc/sssd" ]] && mkdir  /etc/sssd
     [[ ! -f "$sssdFile" ]] && touch "$sssdFile"

     echo "[sssd]
services = nss,pam
config_file_version = 2
domains = $realm

[domain/$realm]
id_provider = ad
access_provider = ad
auth_provider = krb5
krb5_realm = $REALM
# Set krb5_renewable_lifetime higher if TGT renew lifetime is longer than 14 days
krb5_renewable_lifetime = 14d
# Set krb5_renew_interval to lower value if TGT ticket lifetime is shorter than 2 hours
krb5_renew_interval = 1h
krb5_ccachedir = /tmp
krb5_ccname_template = FILE:%d/krb5cc_%U
override_homedir = /home/%d/%u
fallback_homedir = /home/%d/%u
ldap_id_mapping = true
default_shell = /bin/bash
ad_gpo_map_remote_interactive = +ctxhdx, +ctxfas
ad_gpo_access_control = permissive">"${sssdFile}"

    chmod 0600 "$sssdFile"
    # command will pop-up a window and wait for usr to input, in order to reduce user interaction, 
    # we use the following code lines to change the configuration directly.
    #sudo pam-auth-update  
    local configFile="/etc/pam.d/common-session"
    mkhomedirLine="$(cat $configFile |grep session |grep pam_mkhomedir 2>&1)"           
      [[ -z "$mkhomedirLine" ]] && echo "session optional            pam_mkhomedir.so" >> "${configFile}"
      
      myLog "Debug: Exit function confADUbuntuSssd"
}

#
# Customize configuration for SSSD AD Integration
# Dedicated for Suse platforms
#
function confADSuseSssd () {
    myLog "Debug: Enter function confADSuseSssd"
    krbFile="/etc/krb5.conf"
    sssdFile="/etc/sssd/sssd.conf"
    smbFile="/etc/samba/smb.conf"
    accountFile="/etc/pam.d/common-account-pc"
    passwordFile="/etc/pam.d/common-password-pc"
    sessionFile="/etc/pam.d/common-session-pc"
    authFile="/etc/pam.d/common-auth-pc"

    # Disable nscd service
    startService "nscd" "stop"   
    startService "nscd" "disable"  

    # Install samba-client
    info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "1" "1" "samba-client")"
    myPrint "$info"
    zypper -i -n install "samba-client" >> "$logFile" 2>&1

    # Customize /etc/krb5.conf
    [[ -f "$krbFile" ]] && cp -f "$krbFile" "$backupDir" >> "$logFile"
    echo "[libdefaults]
    dns_canonicalize_hostname = false
    rdns = false
    default_realm = $REALM 
    forwardable = true

[realms]
    $REALM = {
    admin_server = $FQDN
    kdc = $FQDN
    default_domain = $realm
    }

[domain_realm]
    $realm = $REALM
    .$realm = $REALM">"$krbFile"

    # Customize /etc/samba/smb.conf
    [[ -f "$smbFile" ]] && cp -f "$smbFile" "$backupDir" >> "$logFile"
    echo "[global]
    workgroup = $WORKGROUP
    security = ADS
    realm = $REALM
    client signing = yes
    client use spnego = yes
    kerberos method = secrets and keytab">"$smbFile"

    # Configure /etc/nsswitch.conf
    configFile="/etc/nsswitch.conf"
    [[ -f "${configFile}" ]] && cp "$configFile" "$backupDir" >> "$logFile"   
    sed -i 's/^passwd:.*$/passwd: compat sss/g' "$configFile"
    sed -i 's/^group:.*$/group:  compat sss/g' "$configFile"
    
    # Install sssd packages
    sssdPkgListSuseNum=${#sssdPkgListSuse[@]}
    for((i=0;i<sssdPkgListSuseNum;i++)); do
        info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "$sssdPkgListSuseNum" "${sssdPkgListSuse[$i]}")"
        myPrint "$info"
        info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${sssdPkgListSuse[$i]}")"
        zypper -i -n install "${sssdPkgListSuse[$i]}" >> "$logFile" 2>&1
        [[ "$?" -ne "0" ]] && myPrint "$info" && exit 4
    done 

    # Configure PAM configurations
    [[ -f "$accountFile" ]] && cp -f "$accountFile" "$backupDir" >> "$logFile"
    [[ -f "$passwordFile" ]] && cp -f "$passwordFile" "$backupDir" >> "$logFile"
    [[ -f "$sessionFile" ]] && cp -f "$sessionFile" "$backupDir" >> "$logFile"
    [[ -f "$authFile" ]] && cp -f "$authFile" "$backupDir" >> "$logFile"

    pam-config --add --sss >> "$logFile" 2>&1  
    pam-config --add --mkhomedir >> "$logFile" 2>&1    

    # Configure /etc/sssd/sssd.conf
    [[ -f "$sssdFile" ]] && cp -f "$sssdFile" "$backupDir" >> "$logFile"
    [[ ! -d '/etc/sssd' ]] && mkdir  /etc/sssd
    [[ ! -f "$sssdFile" ]] && touch "$sssdFile"
    
    echo "[sssd] 
    config_file_version = 2
    domains = $realm  
    services = nss,pam

[domain/$realm]
    id_provider = ad 
    auth_provider = ad       
    access_provider = ad
    ldap_id_mapping = true 
    ldap_schema = ad

    ad_server = $fqdn
    ad_domain = $realm
  
    krb5_ccachedir = /tmp
    krb5_ccname_template = FILE:%d/krb5cc_%U
    fallback_homedir = /home/%d/%u
    default_shell = /bin/bash

    ad_gpo_access_control = permissive">"${sssdFile}"

    chmod 0600 "$sssdFile"

    local ntpservice="chronyd"
    [[ "$osMajorVersion" -lt "15" ]] && ntpservice="ntpd"

    myLog "Info: Enable $ntpservice service"
    systemctl enable "$ntpservice"  >> "$logFile" 2>&1
    [[ "$?" -ne "0" ]] && myLog "Error: Failed to enable $ntpservice service" && configurationStatus="Error"
    myLog "Info: Restart $ntpservice service"
    systemctl restart "$ntpservice" >> "$logFile"  2>&1
    [[ "$?" -ne "0" ]] && myLog "Error: Failed to restart $ntpservice service" && configurationStatus="Error"

    myLog "Debug: Exit function confADSuseSssd"
}

function enablePbisUpdateDNS {
    local service_name="pbis-update-dns"
    local service_conf="/etc/systemd/system/${service_name}.service"

    [ -f "${service_conf}" ] || echo "# System unit that update this host's Active Directory DNS record on boot
[Unit]
Description=Update Active Directory DNS with current IP address
Requires=lwsmd.service
After=lwsmd.service

[Service]
ExecStart=/opt/pbis/bin/update-dns --show
ExecReload=/opt/pbis/bin/update-dns --show

[Install]
WantedBy=multi-user.target" > "$service_conf"
    enableService "$service_name"
}

#
# Check download file integrity with sha256sum
# Dedicated for PBIS/Centrify 
#
function downloadedFileIntegrityCheck() 
{
    downloadedfile=$1
    expectedresult=$2
    result="$(sha256sum $downloadedfile | awk '{print $1}')"
    if [ "$expectedresult" == "$result" ]; then
        myLog "Info: $downloadedfile passed integrity check"
    else
        info="$(get_str CTXINSTALL_FAILED_TO_VERIFY_VALUE "sha256sum")"
        myPrint "$info"
        exit 4
    fi
}


#
# Customize configuration for Centrify AD Integration
# Dedicated for RHEL/CentOS platforms
#
function confADRhelCentrify()
{
    myLog "Debug: Enter function confADRhelCentrify"
      
    if [[ -f "$installCfg" ]]; then
        centrifypkgpath="$(cat $installCfg |grep centrifypkgpath= |cut -d '=' -f2 2>&1)"
        myLog "Info: file $installCfg exists and the value of centrifypkgpath is $centrifypkgpath"
    else
        myLog "Info: file $installCfg does not exist!"
    fi    
    
    # downloadPkg is used to indicate if the package should be download from network or not:  
    #   0: don't download
    #   1: download(default value)
    downloadPkg="1" 
    # validate pkg path and files under pkg path     
    if [[ -n "$centrifypkgpath" ]]; then
       if [[ -d "$centrifypkgpath" ]]; then
          countAdcheck="$(ls $centrifypkgpath/adcheck*x86_64 |wc -l 2>&1)"
          countInstall="$(ls $centrifypkgpath/install.sh |wc -l 2>&1)"
          if [[ "$countAdcheck" -eq "0" ]]; then
              myLog "Error: No adcheck*x86_64 file under $centrifypkgpath." 
              downloadPkg="1"
          elif [[ "$countAdcheck" -gt "1" ]]; then
              myLog "Error: More than one adcheck*x86_64 file under $centrifypkgpath." 
              downloadPkg="1"
          fi          
          if [[ "$countInstall" -eq "0" ]]; then
              myLog "Error: No install.sh file under $centrifypkgpath." 
              downloadPkg="1"
          elif [[ "$countInstall" -gt "1" ]]; then
              myLog "Error: More than one install.sh file under $centrifypkgpath." 
              downloadPkg="1"
          fi
          if [[ "$countAdcheck" -eq "1" && "$countInstall" -eq "1" ]]; then
              downloadPkg="0"
              centrifyPath="$centrifypkgpath"
              myLog "Info: Centrify package under $centrifypkgpath will be used." 
          fi
       else  # directory $centrifypkgpath does not exit
           myLog "Error: directory($centrifypkgpath) does not exist, try to download Centrify pacakge from network!"
           configurationStatus="Error"          
           downloadPkg="1"
       fi
    
    fi
    
    if [[ "$downloadPkg" -eq "1" ]]; then
        # RHEL8 & Rocky8
        [[ "${osPlatform}" == "red" || "${osPlatform}" == "rocky" ]] && [[ "$version" == "8" ]] && str="https://downloads.centrify.com/products/server-suite/2021/centrify-server-suite-2021-rhel6-x86_64.tgz" && expectedSha256Sum="066e92804fce4af1b49f3d28a42375642769ec57d4363108cfc9413faf23ee30" >>"$logFile" 2>&1
        #Centrify for RHEL4.0-7.2(64bit)
        [[ "${osPlatform}" == "red" && "$version" != "8" ]] && str="http://edge.centrify.com/products/centrify-suite/2016-update-1/installers/centrify-suite-2016.1-rhel4-x86_64.tgz?_ga=1.178323680.558673738.1478847956" && expectedSha256Sum="a68aae10d96ff97ba8914c5ea77936ed200c636a5ae1a5344af8c202b7686cac" >>"$logFile" 2>&1  
        #Centrify for CentOS 5.0-7.2(64bit)
        [[ "${osPlatform}" == "centos" ]] && str="http://edge.centrify.com/products/centrify-suite/2016-update-1/installers/centrify-suite-2016.1-rhel4-x86_64.tgz?_ga=1.186648044.558673738.1478847956" && expectedSha256Sum="a68aae10d96ff97ba8914c5ea77936ed200c636a5ae1a5344af8c202b7686cac" >>"$logFile" 2>&1
        #Centrify for Amazon2 (64bit)
        [[ "${osPlatform}" == "amzn" ]] && str="https://downloads.centrify.com/products/infrastructure-services/2020.1/centrify-infrastructure-services-2020.1-rhel5-x86_64.tgz" && expectedSha256Sum="f5dbe6a8e0f1898c9669a5de2def02423e32654b57dce758c41e6003d1ea1bb1" >>"$logFile" 2>&1
        #Centrify for Ubuntu (64bit)
        [[ "${osPlatform}" == "ubuntu" || "${osPlatform}" == "debian" ]] && str="https://downloads.centrify.com/products/infrastructure-services/19.9/centrify-infrastructure-services-19.9-deb8-x86_64.tgz?_ga=2.151462329.1042350071.1592881996-604509155.1572850145" && expectedSha256Sum="9fe1ac255bcff8e45123f6bb127eacb49805f2b69bc79372bf1f37049bf0c469" >>"$logFile" 2>&1
        #Centrify for SUSE 11, 12, 15
        [[ "${osPlatform}" == "suse" ]] && str="https://downloads.centrify.com/products/infrastructure-services/2020.1/centrify-infrastructure-services-2020.1-suse11-x86_64.tgz" && expectedSha256Sum="94fe332b7a4ce95075fa4f909bce8b092f8c6e52b3d6321f7187738e6ebdfee6" >>"$logFile" 2>&1 
        myLog "Info: str=$str"
        [[ ! -d "$centrifyPath" ]] && mkdir -p "$centrifyPath"
        rm -rf $centrifyPath/*
        info="$(get_str CTXINSTALL_FAILED_TO_DOWNLOAD_CENTRIFY_FILES)"
        wget -nc --directory-prefix=$centrifyPath $str >>"$logFile" 2>&1
        if [[ "$?" -ne "0" ]]; then
            myPrint "$info"
            exit 4
        fi
        downloadedFileIntegrityCheck $centrifyPath/centrify*.tgz* $expectedSha256Sum
    
        tar zxvf $centrifyPath/centrify* -C $centrifyPath >>"$logFile" 2>&1
        [[ "$?" -ne "0" ]] && myPrint "$info" && exit 4 
    fi

    $centrifyPath/adcheck* "${REALM}" >> "$logFile" 2>&1
    if [[ "$?" -gt "2" ]]; then
        # Under certain case, the DNS configuration(/etc/resolv.conf) was overwritten, this causes the failure
        # of joining domain, in order to remove this problem, we need to reconfigure DNS.
        myLog "Info: calling confDNS() to reconfigure DNS and then re-execute adcheck."
        confDNS
        sudo $centrifyPath/adcheck* "${REALM}" >> "$logFile" 2>&1
        if [[ "$?" -gt "2" ]]; then
            info="$(get_str CTXINSTALL_FAILED_TO_ADCHECK_READINESS_TO_JOIN_DOMAIN)"
            myPrint "$info" 
            exit 4
        fi
    fi

    $centrifyPath/install.sh --express >>"$logFile" 2>&1
    if [[ "$?" -eq "1" || "$?" -gt "25" ]]; then
        info="$(get_str CTXINSTALL_FAIL_TO_EXECUTE)"
        myPrint "$info \"install.sh --express\""
    exit 4
    fi
    myLog "Debug: Exit function confADRhelCentrify"
}

#
# Customize configuration for PBIS AD Integration
# Dedicated for RHEL 7/CentOS 7 and RHEL 8/CentOS 8 platforms
#
function confADRhelPbis()
{
    myLog "Debug: Enter function confADRhelPbis"

    if [[ -f "$installCfg" ]]; then
        pbispkgpath="$(cat $installCfg |grep pbispkgpath= |cut -d '=' -f2 2>&1)"
        myLog "Info: file $installCfg exists and the value of pbispkgpath is $pbispkgpath"
    else
        myLog "Info: file $installCfg does not exist!"
    fi

    # libnsl should be installed for RHEL8/CentOS8
    if [[ "${osPlatform}" == "red" || "${osPlatform}" == "centos" || "${osPlatform}" == "rocky" ]] && [[ "$version" == "8" ]]; then
        info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "1" "1" "libnsl")"
        myPrint "$info"
        $YUM -y install "libnsl" >> "$logFile" 2>&1
        if [[ "$?" -ne "0" ]]; then               
            info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "libnsl" )"              
            $YUM info "libnsl" >> "$logFile" 2>&1             
            [[ "$?" -ne "0" ]] && myPrint "$info" && installationStatus="Error"
        fi 
    fi

    # downloadPkg is used to indicate if the package should be download from network or not:
    #   0: don't download
    #   1: download(default value)
    downloadPkg="1"

    if [[ -n "$pbispkgpath" ]]; then
       if [[ -d "$pbispkgpath" ]]; then
          countInstall="$(ls $pbispkgpath/*x86_64*.sh |wc -l 2>&1)"
          if [[ "$countInstall" -eq "0" ]]; then
              myLog "Error: No install.sh file under $pbispkgpath."
              downloadPkg="1"
          elif [[ "$countInstall" -gt "1" ]]; then
              myLog "Error: More than one install.sh file under $pbispkgpath."
              downloadPkg="1"
          fi
          if [[ "$countInstall" -eq "1" ]]; then
              downloadPkg="0"
              pbisPath="$pbispkgpath"
              myLog "Info: Pbis package under $pbispkgpath will be used."
          fi
       else  # directory $pbispkgpath does not exit
           myLog "Error: directory($pbispkgpath) does not exist, try to download Pbis pacakge from network!"
           configurationStatus="Error"
           downloadPkg="1"
       fi

    fi

    if [[ "$downloadPkg" -eq "1" ]]; then
        local pbisDownloadURL="https://github.com/BeyondTrust/pbis-open/releases/download"
        local pbisDownloadExpectedSHA256="f37555abf22f453c3865f06eba3c5f913605c300917be29663b23941087137f6"
        local pbisDownloadFMT="rpm"
        local pbisDownloadRelease="9.1.0"
        local pbisDonwloadBuild="551"

        case "$osPlatform" in
            "ubuntu" | "debian")
                pbisDownloadFMT="deb"
                pbisDownloadExpectedSHA256="b89183e31f0893033c57e0ca4934c596bc7bff51ca5a36f9d09b511153c5ff83"
                ;;
            *)
                # amazon linux 2
                # centos 7/8
                # red 7/8
                # rocky 8
                # suse 12.5/15.2/15.3
                ;;
        esac

        local pbisFileName="pbis-open-${pbisDownloadRelease}.${pbisDonwloadBuild}.linux.x86_64.${pbisDownloadFMT}.sh"

        pbisDownloadPath="${pbisDownloadURL}/${pbisDownloadRelease}/${pbisFileName}"
        myLog "Info: pbisDownloadPath=$pbisDownloadPath"
        [[ ! -d "$pbisPath" ]] && mkdir -p "$pbisPath"
        [[ -d "$pbisPath" ]] && sudo rm -rf "${pbisPath}/*"
        info="$(get_str CTXINSTALL_FAILED_TO_DOWNLOAD_PBIS_FILES)"
        wget -nc --directory-prefix="$pbisPath" "$pbisDownloadPath" >>"$logFile" 2>&1
        if [[ "$?" -ne "0" ]]; then
            myPrint "$info"
            exit 4
        fi

        local pbisLocalPath="${pbisPath}/${pbisFileName}"

        downloadedFileIntegrityCheck "$pbisLocalPath" "$pbisDownloadExpectedSHA256"

        if ! chmod +x "$pbisLocalPath" >>"$logFile" 2>&1; then
            info="$(get_str CTXINSTALL_FAIL_TO_EXECUTE)"
            myPrint "$info"
            exit 4
        fi
    fi

    if [[ -z "${LD_LIBRARY_PATH}" && -z "${LD_PRELOAD}" && -z "${LIBPATH}" && -z "${SHLIB_PATH}" ]]; then
        # install Pbis script
        if ! sh "$pbisLocalPath" >>"$logFile" 2>&1; then
            info="$(get_str CTXINSTALL_FAIL_TO_EXECUTE)"
            myPrint "$info"
            exit 4
        fi
    else
        # Environment Variables
        #
        # Before you install the AD Bridge agent, make sure that the following environment variables are not set:
        #
        #   LD_LIBRARY_PATH
        #   LIBPATH
        #   SHLIB_PATH
        #   LD_PRELOAD
        # Setting any of these environment variables violates best practices for managing Unix and Linux computers
        # because it causes AD Bridge to use non-AD Bridge libraries for its services.

        myLog "Before you install the AD Bridge agent, make sure that the following environment variables are not set:
    LD_LIBRARY_PATH
    LIBPATH
    SHLIB_PATH
    LD_PRELOAD"

        info="$(get_str CTXINSTALL_FAIL_TO_EXECUTE)"
        myPrint "$info"
        exit 4
    fi

    myLog "Debug: Exit function confADRhelPbis"
}


#
# Customize configuration for AD Integration
# common function for RHEL/CentOS platforms
#
function confADRhel()
{
    myLog "Debug: Enter function confADRhel"
    myLog "Info: joinDomainWay=$joinDomainWay"
    if [[ "$joinDomainWay" == "winbind" ]]; then
       confADRhelWinbind 
    elif [[ "$joinDomainWay" == "sssd" ]]; then
       confADRhelSssd
    elif [[ "$joinDomainWay" == "centrify" ]]; then
       confADRhelCentrify
    elif [[ "$joinDomainWay" == "pbis" ]]; then
       confADRhelPbis
    else
       info="$(get_str CTXINSTALL_SUPPORT_AD_ERROR_INFO_CONFIGURATION)"
       myPrint "$info"
       exit 4
    fi 
    myLog "Debug: Exit function confADRhel"
}

#
# Customize configuration for Centrify AD Integration
# Dedicated for Ubuntu platforms
#
function confADUbuntuCentrify()
{
    myLog "Debug: Enter function confADUbuntuCentrify, reuse confADRhelCentrify"
    confADRhelCentrify
    myLog "Debug: Exit function confADUbuntuCentrify"
}

#
# Customize configuration for Centrify AD Integration
# Dedicated for SUSE platforms
#
function confADSuseCentrify()
{
    myLog "Debug: Enter function confADSuseCentrify, reuse confADRhelCentrify()"
    confADRhelCentrify
    myLog "Debug: Exit function confADSuseCentrify"
}

function confADUbuntuPbis()
{
    myLog "Debug: Enter function confADUbuntuPbis, reuse confADRhelPbis"
    confADRhelPbis
    myLog "Debug: Exit function confADUbuntuPbis"
}

function confADSusePbis()
{
    myLog "Debug: Enter function confADSusePbis, reuse confADRhelPbis"
    confADRhelPbis
    myLog "Debug: Exit function confADSusePbis"
}

#
# Customize configuration for AD Integration
# Dedicated for Ubuntu platforms
#
function confADUbuntu()
{
    myLog "Debug: Enter function confADUbuntu"
    myLog "Info: joinDomainWay=$joinDomainWay"
    if [[ "$joinDomainWay" == "winbind" ]]; then
       confADUbuntuWinbind
    elif [[ "$joinDomainWay" == "sssd" ]]; then
       confADUbuntuSssd
    elif [[ "$joinDomainWay" == "centrify" ]]; then
       confADUbuntuCentrify
    elif [[ "$joinDomainWay" == "pbis" ]]; then
       confADUbuntuPbis
    else
       #myPrint "Error: only winbind and sssd can be supported currently!"
       info="$(get_str CTXINSTALL_SUPPORT_AD_ERROR_INFO_CONFIGURATION)"
       myPrint "$info"
       exit 4
    fi
    myLog "Debug: Exit function confADUbuntu"
}

function confADSuseWinbindKrb5()
{
    myLog "Debug: Enter function confADSuseWinbindKrb5"
    krbFile="/etc/krb5.conf"
    [[ -f "$krbFile" ]] && `cp -f "$krbFile" "$backupDir"`
    echo "[libdefaults]
        default_realm = $REALM
        clockskew = 300
        default_ccache_name = FILE:/tmp/krb5cc_%{uid}

[realms]
$REALM = {
        kdc = $FQDN
        default_domain = $realm
        admin_server = $FQDN
}

[logging]
        kdc = FILE:/var/log/krb5/krb5kdc.log
        admin_server = FILE:/var/log/krb5/kadmind.log
        default = SYSLOG:NOTICE:DAEMON
[domain_realm]
        .${realm} = $REALM
[appdefaults]
pam = {
        ticket_lifetime = 1d
        renew_lifetime = 1d
        forwardable = true
        proxiable = false
        minimum_uid = 1
}">"$krbFile"
    myLog "Debug: Exit function confADSuseWinbindKrb5"
}

function confADSuseWinbindSmb()
{
    myLog "Debug: Enter function confADSuseWinbindSmb"
    smbFile="/etc/samba/smb.conf"
    [[ -f "$smbFile" ]] && `cp -f "$smbFile" "$backupDir"`
    
    ipAddr="$(getent hosts $realm | awk 'NR==1 { print $1 }')"
    
    echo "[global]
        workgroup = $WORKGROUP
        passdb backend = tdbsam
        printing = cups
        printcap name = cups
        printcap cache time = 750
        cups options = raw
        map to guest = Bad User
        include = /etc/samba/dhcp.conf
        logon path = '\\%L\profiles\.msprofile'
        logon home = '\\%L\%U\.9xprofile'
        logon drive = P:
        usershare allow guests = No
        idmap gid = 10000-20000
        idmap uid = 10000-20000
        kerberos method = secrets and keytab
        security = ADS
        realm = $REALM
        template homedir = /home/%D/%U
        template shell = /bin/bash
        winbind refresh tickets = yes
[homes]
        comment = Home Directories
        valid users = %S, %D%w%S
        browseable = No
        read only = No
        inherit acls = Yes
[profiles]
        comment = Network Profiles Service
        path = %H
        read only = No
        store dos attributes = Yes
        create mask = 0600
        directory mask = 0700
[users]
        comment = All users
        path = /home
        read only = No
        inherit acls = Yes
        veto files = /aquota.user/groups/shares/
[groups]
        comment = All groups
        path = /home/groups
        read only = No
        inherit acls = Yes
[printers]
        comment = All Printers
        path = /var/tmp
        printable = Yes
        create mask = 0600
        browseable = No
[print$]
        comment = Printer Drivers
        path = /var/lib/samba/drivers
        write list = @ntadmin root
        force group = ntadmin
        create mask = 0664
        directory mask = 0775" >"$smbFile"
    
    myLog "Debug: Exit function confADSuseWinbindSmb"
}


#
# Customize configuration for Winbind AD Integration
# common function for SUSE platform
#
function confADSuseWinbind()
{
    myLog "Debug: Enter function confADSuseWinbind" 

    # Install package
    winbindPkgListNum=${#winbindPkgListSuse[@]}
    for((i=0;i<winbindPkgListNum;i++)); do
        info="$(get_str CTXINSTALL_INSTALL_PKG_INSTALLATION "`expr $i + 1`" "$winbindPkgListNum" "${winbindPkgListSuse[$i]}")"
        myPrint "$info"
        info="$(get_str CTXINSTALL_INSTALL_PKG_FAIL_INSTALLATION "${winbindPkgListSuse[$i]}")"
        zypper -i -n install "${winbindPkgListSuse[$i]}" >> "$logFile" 2>&1
        [[ "$?" -ne "0" ]] && myPrint "$info" && exit 4
    done

    # back up configuration files
    displaymanagerFile="/etc/sysconfig/displaymanager"
    accountFile="/etc/pam.d/common-account-pc"
    passwordFile="/etc/pam.d/common-password-pc"
    sessionFile="/etc/pam.d/common-session-pc"
    authFile="/etc/pam.d/common-auth-pc"
    sshFile="/etc/ssh/ssh_config"
    sshdFile="/etc/ssh/sshd_config"
    pamFile="/etc/security/pam_winbind.conf"

    [[ -f "$displaymanagerFile" ]] && `cp -f "$displaymanagerFile" "$backupDir"`
    [[ -f "$accountFile" ]] && `cp -f "$accountFile" "$backupDir"`
    [[ -f "$passwordFile" ]] && `cp -f "$passwordFile" "$backupDir"`
    [[ -f "$sessionFile" ]] && `cp -f "$sessionFile" "$backupDir"`
    [[ -f "$authFile" ]] && `cp -f "$authFile" "$backupDir"`
    [[ -f "$sshFile" ]] && `cp -f "$sshFile" "$backupDir"`
    [[ -f "$sshdFile" ]] && `cp -f "$sshdFile" "$backupDir"`   
    [[ -f "$pamFile" ]] && `cp -f "$pamFile" "$backupDir"`
  
     
    # Customize /etc/sysconfig/displaymanager
    `sed -i 's/^DISPLAYMANAGER_AD_INTEGRATION.*$/DISPLAYMANAGER_AD_INTEGRATION="yes"/g' "$displaymanagerFile"`
 
    # Customize /etc/pam.d/common-account-pc
    `sed -i 's/^account.*required.*pam_unix.so.*try_first_pass/account requisite       pam_unix.so     try_first_pass/g' "$accountFile"`    
    `sed -i '/^account *sufficient *pam_localuser.so.*$/d' "$accountFile"`
    `sed -i '/^account *required *pam_winbind.so *use_first_pass.*$/d' "$accountFile"`
    
    echo "account sufficient      pam_localuser.so
account required        pam_winbind.so  use_first_pass">>"$accountFile"

    # Customize /etc/pam.d/common-password-pc
    `sed -i '/^password *sufficient *pam_winbind.so.*$/d' "$passwordFile"`
    echo "password        sufficient      pam_winbind.so">>"$passwordFile"
        
    # Customize /etc/pam.d/common-session-pc
    `sed -i '/^session *optional *pam_mkhomedir.so.*$/d' "$sessionFile"`
    `sed -i '/^session *required *pam_winbind.so.*$/d' "$sessionFile"`
    echo "session  optional       pam_mkhomedir.so">>"$sessionFile"
    echo "session required        pam_winbind.so">>"$sessionFile"

    # Customize /etc/pam.d/common-auth-pc
    `sed -i '/^auth.*required.*pam_unix.so.*try_first_pass.*$/d' "$authFile"`
    `sed -i '/^auth *sufficient *pam_unix.so *try_first_pass.*$/d' "$authFile"`
    `sed -i '/^auth *required *pam_winbind.so *use_first_pass.*$/d' "$authFile"`  
    `sed -i '/^auth *sufficient *pam_winbind.so *use_first_pass.*$/d' "$authFile"` 
    echo "auth    sufficient      pam_unix.so  try_first_pass">>"$authFile" 
    echo "auth    required        pam_winbind.so  use_first_pass">>"$authFile"

    # Customize /etc/ssh/ssh_config
    `sed -i '/^SendEnv *LANG *LC_CTYPE *LC_NUMERIC *LC_TIME *LC_COLLATE *LC_MONETARY *LC_MESSAGES.*$/d' "$sshFile"`    
    `sed -i '/^SendEnv *LC_PAPER *LC_NAME *LC_ADDRESS *LC_TELEPHONE *LC_MEASUREMENT.*$/d' "$sshFile"`    
    `sed -i '/^SendEnv *LC_IDENTIFICATION *LC_ALL.*$/d' "$sshFile"`    
    `sed -i '/^Protocol *2.*$/d' "$sshFile"`    
    `sed -i '/^SendEnv *LC_IDENTIFICATION *LC_ALL.*$/d' "$sshFile"`    
    `sed -i '/^GSSAPIAuthentication *yes.*$/d' "$sshFile"`    
    `sed -i '/^GSSAPIDelegateCredentials *yes.*$/d' "$sshFile"`        
    echo "Protocol 2
SendEnv LC_IDENTIFICATION LC_ALL
GSSAPIAuthentication yes
GSSAPIDelegateCredentials yes">>"$sshFile"


    # Customize /etc/ssh/sshd_config
    `sed -i '/^GSSAPIAuthentication *yes.*$/d' "$sshdFile"` 
    `sed -i '/^GSSAPICleanupCredentials *yes.*$/d' "$sshdFile"`
    `sed -i '/^ChallengeResponseAuthentication *yes.*$/d' "$sshdFile"`
    echo "GSSAPIAuthentication yes
GSSAPICleanupCredentials yes
ChallengeResponseAuthentication yes">>"$sshdFile"

    # Customize /etc/nsswitch.conf
    local nsswitch_conf="/etc/nsswitch.conf"
    sed -i 's/^passwd:.*$/passwd: compat winbind/g' $nsswitch_conf
    sed -i 's/^group:.*$/group:  compat winbind/g' $nsswitch_conf

    # Customize /etc/samba/smb.conf
    #`sed -i '/kerberos method =.*$/d' "$smbFile"`
    #`sed -i '/winbind refresh tickets =.*$/d' "$smbFile"`      # del line in case user execute the script multi times
    #`sed -i '/\[global\]/a winbind refresh tickets = true' "$smbFile"`
    #`sed -i '/\[global\]/a kerberos method = secrets and keytab' "$smbFile"`
    confADSuseWinbindSmb

    # Customize /etc/krb5.conf
    #`sed -i '/default_ccache_name.*$/d' "$krbFile"`
    #`sed -i '/\[libdefaults\]/a default_ccache_name = FILE:/tmp/krb5cc_%{uid}' "$krbFile"`
    confADSuseWinbindKrb5


    # under certain case, some lines are not commented out, we need to remove them

    # Customize /etc/security/pam_winbind.conf
    `sed -i 's/.*krb5_auth =.*$/krb5_auth = yes/g' "$pamFile"`
    `sed -i 's/.*krb5_ccache_type =.*$/krb5_ccache_type = FILE/g' "$pamFile"`
    `sed -i 's/.*mkhomedir =.*$/mkhomedir = yes/g' "$pamFile"`
    
    # Enable Winbind Daemon
    myLog "Info: Enable winbind service"
    sudo systemctl enable winbind >> "$logFile" 2>&1
    [[ "$?" -ne "0" ]] && myLog "Error: Failed to enable winbind service" && configurationStatus="Error"

    local ntpservice="chronyd"
    [[ "$osMajorVersion" -eq "12" ]] && ntpservice="ntpd"

    myLog "Info: Enable $ntpservice service"
    systemctl enable "$ntpservice"  >> "$logFile" 2>&1
    [[ "$?" -ne "0" ]] && myLog "Error: Failed to enable $ntpservice service" && configurationStatus="Error"
    myLog "Info: Restart $ntpservice service"
    systemctl restart "$ntpservice" >> "$logFile"  2>&1
    [[ "$?" -ne "0" ]] && myLog "Error: Failed to restart $ntpservice service" && configurationStatus="Error"

    myLog "Debug: Exit function confADSuseWinbind" 
}

#
# Customize configuration for AD Integration
# common function for RHEL/CentOS platforms
#
function confADSuse()
{
    myLog "Debug: Enter function confADSuse"
    myLog "Info: joinDomainWay=$joinDomainWay"
    if [[ "$joinDomainWay" == "winbind" ]]; then
       confADSuseWinbind 
    elif [[ "$joinDomainWay" == "centrify" ]]; then
       confADSuseCentrify
    elif [[ "$joinDomainWay" == "sssd" ]]; then
       confADSuseSssd
    elif [[ "$joinDomainWay" == "pbis" ]]; then
       confADSusePbis
    else
       info="$(get_str CTXINSTALL_SUPPORT_AD_ERROR_INFO_CONFIGURATION)"
       myPrint "$info"
       exit 4
    fi 
    myLog "Debug: Exit function confADSuse"
}

function joinDomainSuse()
{
    myLog "Debug: Enter function joinDomainSuse"
    HOSTNAME=`tr '[a-z]' '[A-Z]' <<<"$hostName"`
    
    if [[ "${joinDomainWay}" == "winbind" ||  "${joinDomainWay}" == "sssd" ]]; then  
       joinDomainWinbindOrSssd   
       if [[ "${joinDomainWay}" == "sssd" ]]; then
            # Enable and start sssd service
            enableService "sssd"
            startService "sssd" "start" 
            systemctl status sssd >> "$logFile" 2>&1
       fi
    elif [[ "${joinDomainWay}" == "centrify" ]]; then   
       joinDomainCentrify
    elif [[ "${joinDomainWay}" == "pbis" ]]; then
       joinDomainPbis
    fi    
    info="$(get_str CTXINSTALL_JOIN_DOMAIN_SUCCESSFULLY_CONFIGURATION)"
    myPrint "$info"
    myLog "Debug: Exit function joinDomainSuse"
}


#
# prompt for domain user name
# Common function for RHEL/CentOS/Ubuntu
# 
function getUserName()
{
    myLog "Debug: Enter function getUserName"
    # get domain user name from environment variable
    if [[ -n "${CTX_EASYINSTALL_USERNAME}" ]]; then
        local tempCtxInstallEnv="CTX_EASYINSTALL_USERNAME"
        local str="$(get_str CTX_EASYINSTALL_ENV_BEENSET "${tempCtxInstallEnv}")"
        myPrint "${str}"
        domainUser=${CTX_EASYINSTALL_USERNAME}
    # get domain user name from user input
    else
        if [[ "${isSilent}" == "yes" ]]; then
            exit 4
        fi
        if [[ -n "$domainUser" ]]; then
            local str0="$(get_str CTXINSTALL_CHANGE_DOMAIN_USER_CONFIGURATION $domainUser)"  
            getYesOrNo "${str0}" "n"
            local ret=$?
            if [[ ${ret} -eq 1 ]]; then
                myLog "Debug: Exit function getUserName"
                return
            fi
        fi
        str1="$(get_str CTXINSTALL_INPUT_DOMAIN_USER_CONFIGURATION)"    
        while true ; do
           read -p "$str1" val
           #ret="$(validateDomain)"
           if [[ -z "$val" ]]; then
              info="$(get_str CTXINSTALL_INPUT_DOMAIN_USER_ERROR_CONFIGURATION)"
              myPrint "$info"
              continue
           fi
           break
        done
        domainUser="$val"
    fi
    myLog "Info: domainUser=$domainUser"
    myLog "Debug: Exit function getUserName"
}

#
# Execute join domain with Winbind/SSSD for RHEL/CentOS/Ubuntu 
#
function joinDomainWinbindOrSssd()
{
    myLog "Debug: Enter funcion joinDomainWinbindOrSssd"

    myLog "please input the password of $domainUser"
    while true; do 
        local result=""
        local ou_para=""
        local str=""
        local info="$(get_str CTXINSTALL_JOINING_DOMAIN_VIA_CMD)"
        if [[ "$version" == "8" ]]; then
            smbFile='/etc/samba/smb.conf'
            realm leave
            [[ -n "$ou" ]] && ou_para="--computer-ou=$ou"
            local ad_method_para=""
            if [[ "$joinDomainWay" == "winbind" ]]; then
                ad_method_para="--client-software=winbind"
            elif [[ "$joinDomainWay" == "sssd" ]]; then
                ad_method_para="--client-software=sssd"
            fi
            str="realm join $REALM -U $domainUser $ad_method_para $ou_para"
            myPrint "$info $str"
            if [[ -n ${CTX_EASYINSTALL_PASSWORD} ]]; then
                set +o history
                str="echo ${CTX_EASYINSTALL_PASSWORD}| $str"
                eval "${str}"
                set -o history
            else
                if [[ "${isSilent}" == "yes" ]]; then
                    exit 4
                fi
                eval "${str}"
            fi
            result="$?"
            `sed -i 's/.*winbind offline logon =.*$/winbind offline logon =no/g' "$smbFile"`

            if [[ "$joinDomainWay" == "sssd" ]]; then
                sssdFile="/etc/sssd/sssd.conf"          
                # Set ad_gpo_access_control value in RHEL8
                `sed -i '/ad_gpo_access_control =.*$/d' "$sssdFile"`
                `sed -i "/\[domain\/"$realm"]/a ad_gpo_access_control = permissive" "$sssdFile"`
                # To fix LNXVDA-7618, we need to change the format of logged in user for sssd
                # default format is user@domain, we need to change it to domain\user
                # refer to issue page for details
                `sed -i '/.*fallback_homedir =.*$/d' "$sssdFile"`
                `sed -i '/.*full_name_format =.*$/d' "$sssdFile"`
                echo 'full_name_format = %2$s\%1$s
fallback_homedir = /home/%d/%u' >> "$sssdFile"
            fi
        else
            if [[ "${isSilent}" == "yes" && -z ${CTX_EASYINSTALL_PASSWORD} ]]; then
                exit 4
            fi        
            [[ -n "$ou" ]] && ou_para="createcomputer=$ou"
            str="net ads join ${REALM} $ou_para -U ${domainUser}"
            myPrint "$info $str"
            # Amazon Linux2 would reveal password in eval script
            if [[ -n ${CTX_EASYINSTALL_PASSWORD} ]]; then
                str="$str"%"${CTX_EASYINSTALL_PASSWORD}"
            else
                if [[ "$osPlatform" == "amzn" ]]; then
                    echo -n "Enter ${domainUser}'s password:"
                    echo -n -e "\033[30;40;25m"
                    echo -n -e "\033[?25l"
                    read -r -s CTX_EASYINSTALL_PASSWORD
                    echo -n -e "\033[?25h"
                    echo -n -e "\033[0m"
                    str="$str"%"${CTX_EASYINSTALL_PASSWORD}"
                fi
            fi
            eval "${str}" 
            result="$?"
        fi

        if [[ "$result" != "0" ]]; then
	        check_results=$(tail -1 /var/log/ctxinstall.log)
            if [[ $check_results =~ "realm: Already joined to this domain" ]]; then
                break
            else
                if [[ "${isSilent}" == "yes" ]]; then
                    exit 4
                fi
                local info="$(get_str CTXINSTALL_JOIN_DOMAIN_RETRY_CONFIGURATION)"             
                getYesOrNo "${info}" "y"
                local ret=$?
                if [[ ${ret} -eq 0 ]]; then
                # Under certain case, the DNS configuration(/etc/resolv.conf) was overwritten, this causes the failure
                # of joining domain, in order to remove this problem, we need to reconfigure DNS.
                    myLog "Info: calling confDNS() to reconfigure DNS."
                    confDNS
                    continue
                else
                    info="$(get_str CTXINSTALL_JOIN_DOMAIN_EXIT_INFO_CONFIGURATION $fname)" 
                    myPrint "$info"
                    exit 4
                fi
            fi	
        else
            break
        fi
    done
    myLog "Debug: Exit function joinDomainWinbindOrSssd"
}

# Execute join domain with Pbis for RHEL7/CentOS7/RHEL8/CentOS8/Ubuntu/Suse
#
function joinDomainPbis()
{
    myLog "Debug: Enter funcion joinDomainPbis"

    myLog "please input the password of $domainUser"
    while true; do
        local result=""
        local ou_para=""
        local passwd_para=""
        [[ -n "$ou" ]] && ou_para="--ou $ou"
        local str="/opt/pbis/bin/domainjoin-cli join ${ou_para} ${REALM} ${domainUser}"
        local info="$(get_str CTXINSTALL_JOINING_DOMAIN_VIA_CMD)"
        myPrint "$info $str"
        [[ -n "${CTX_EASYINSTALL_PASSWORD}" ]] && passwd_para="${CTX_EASYINSTALL_PASSWORD}"
        str="${str} $passwd_para"
        eval "${str}"
        result="$?"
        # Clear CTX_EASYINSTALL_PASSWORD so that if the password is error user can input manually
        CTX_EASYINSTALL_PASSWORD=""
        if [[ "$result" != "0" ]]; then
            if [[ "${isSilent}" == "yes" ]]; then
                exit 4
            fi
            local info="$(get_str CTXINSTALL_JOIN_DOMAIN_RETRY_CONFIGURATION)"
            getYesOrNo "${info}" "y"
            local ret=$?
            if [[ ${ret} -eq 0 ]]; then
                # Under certain case, the DNS configuration(/etc/resolv.conf) was overwritten, this causes the failure
                # of joining domain, in order to remove this problem, we need to reconfigure DNS.
                myLog "Info: calling confDNS() to reconfigure DNS."
                confDNS

                continue
            else
                info="$(get_str CTXINSTALL_JOIN_DOMAIN_EXIT_INFO_CONFIGURATION $fname)"
                myPrint "$info"
                exit 4
            fi
        else
            /opt/pbis/bin/update-dns --show
            enablePbisUpdateDNS
            break
        fi
    done
    myLog "Debug: Exit function joinDomainPbis"
}

#
# Execute join domain with Centrify for RHEL7/CentOS7/RHEL8/CentOS8/Ubuntu/Suse
#
function joinDomainCentrify()
{
    myLog "Debug: Enter function joinDomainCentrify"

    local centrify_conf="/etc/centrifydc/centrifydc.conf"

    sed -i '/^adclient.dynamic.dns.enabled: */d' "$centrify_conf"
    echo 'adclient.dynamic.dns.enabled: true' >>"$centrify_conf"

    # Try to join the domain
    while true; do
        local ou_para=""
        local passwd_para=""
        [[ -n "$ou" ]] && ou_para="-c $ou"
        local str="adjoin $REALM -w -V $ou_para -u $domainUser -n $hostNameUpper"
        local info="$(get_str CTXINSTALL_JOINING_DOMAIN_VIA_CMD)"
        myPrint "$info $str"
        [[ -n "${CTX_EASYINSTALL_PASSWORD}" ]] && passwd_para="-p ${CTX_EASYINSTALL_PASSWORD}"
        str="${str} $passwd_para"
        eval "${str}" 

        # adret=11:  already in the domain
        #       19:  wrong password
        #        0:  successful
        local adret=$?
        myLog "Info:adret=$adret"
        if [ "$adret" = "11" ]; then
            if [[ "${isSilent}" == "yes" ]]; then
                ret=0
            else
                # server is already in the domain, ask user to leave the domain then rejoin
                local info="$(get_str CTXINSTALL_ASK_IF_LEAVE_BEFORE_RE_JOIN_DOMAIN)"
                getYesOrNo "$info" "n"
                ret=$?
            fi
            if [[ ${ret} -eq 0 ]]; then
                info="$(get_str CTXINSTALL_LEAVING_DOMAIN_BY_ADLEAVE $domainUser)"
                myPrint "$info"
                while true; do
                    local str="adleave -r -u ${domainUser} $passwd_para"
                    eval ${str} >>"$logFile" 2>&1 
                    ret=$?
                    if [[ "$ret" = "0" ]]; then
                        info="$(get_str CTXINSTALL_HAVE_LEFT_DOMAIN)"
                        myPrint "$info"
                        break
                    elif [[ "$ret" = "19" ]]; then
                        info="$(get_str CTXINSTALL_INVALID_USER_OR_PASSWORD)" 
                        myPrint "$info"
                        # Clear CTX_EASYINSTALL_PASSWORD if the password is so that error user can input manually 
                        CTX_EASYINSTALL_PASSWORD=""
                        if [[ "${isSilent}" == "yes" ]]; then
                            exit 4
                        fi
                        continue
                    else
                        info="$(get_str CTXINSTALL_JOIN_DOMAIN_EXIT_INFO_CONFIGURATION $fname)" 
                        myPrint "$info"
                        exit 4
                    fi
                done
            else
                break
            fi
        elif [ "$adret" = "19" ]; then
            info="$(get_str CTXINSTALL_INVALID_USER_OR_PASSWORD)" 
            myPrint "$info"
            # Clear CTX_EASYINSTALL_PASSWORD if the password is so that error user can input manually 
            CTX_EASYINSTALL_PASSWORD=""
            if [[ "${isSilent}" == "yes" ]]; then
                exit 4
            fi
            continue
        elif [ "$adret" = "0" ]; then
            `sudo rm -rf "$centrifyPath"`
            break
        else
            info="$(get_str CTXINSTALL_JOIN_DOMAIN_EXIT_INFO_CONFIGURATION $fname)" 
            myPrint "$info"
            exit 4
        fi
    done
    myLog "Debug: Exit function joinDomainCentrify"
}

#
# Call different command to join domain for RHEL/CentOS
#
function joinDomainRhel()
{   
    myLog "Debug: Enter function joinDomainRhel"
    HOSTNAME=`tr '[a-z]' '[A-Z]' <<<"$hostName"`
    version=${osVersion:0:1}    
    str="join domain via command:  net ads join $REALM -U $domainUser"
    if [[ "${joinDomainWay}" == "winbind" ]]; then  
        joinDomainWinbindOrSssd
        # Start winbind service
        startService "winbind" "start"   
        [[ "$?" -ne "0" ]] && myLog "Error: failed to start winbind service" && configurationStatus="Error"

    elif [[ "${joinDomainWay}" == "sssd" ]]; then       
        joinDomainWinbindOrSssd
        # Start and enable SSSD Daemon 
        startService "sssd" "start"
        [[ "$?" -ne "0" ]] && myLog "Error: failed to start sssd service" && configurationStatus="Error"  
        sudo chkconfig sssd on  >> "$logFile" 2>&1
        [[ "$?" -ne "0" ]] && myLog "Error: failed to enable sssd service" && configurationStatus="Error"  

    elif [[ "${joinDomainWay}" == "centrify" ]]; then
        joinDomainCentrify
    elif [[ "${joinDomainWay}" == "pbis" ]]; then
        joinDomainPbis
    fi    
    info="$(get_str CTXINSTALL_JOIN_DOMAIN_SUCCESSFULLY_CONFIGURATION)"
    myPrint "$info"
    myLog "Debug: Exit function joinDomainRhel"
}

#
# Execute join domain for ubuntu platform
#
function joinDomainUbuntu()
{
    myLog "Debug: Enter function joinDomainUbuntu"
    HOSTNAME=`tr '[a-z]' '[A-Z]' <<<"$hostName"`
    version="${osVersion:0:1}"    
     
    if [[ "${joinDomainWay}" == "winbind" ]]; then
        joinDomainWinbindOrSssd
        # restart winbind service
        systemctl restart winbind >> "$logFile"      
        local configFile="/etc/pam.d/common-session"
        `sed -i 's/^session.*optional.*pam_mkhomedir.so/#&/g' "${configFile}"` 
        echo "session optional            pam_mkhomedir.so" >> "${configFile}"
        # pam-auth-update
    elif [[ "${joinDomainWay}" == "sssd" ]]; then
        joinDomainWinbindOrSssd
        systemctl start sssd >> "$logFile"
        systemctl enable sssd >> "$logFile"
    elif [[ "${joinDomainWay}" == "centrify" ]]; then
        joinDomainCentrify
    elif [[ "${joinDomainWay}" == "pbis" ]]; then
        joinDomainPbis
    fi
   
    info="$(get_str CTXINSTALL_JOIN_DOMAIN_SUCCESSFULLY_CONFIGURATION)"
    myPrint "$info"
    myLog "Debug :Exit function joinDomainUbuntu"
}

#
# Set some environment variables before call ctxsetup.sh script
#
function setCtxsetupEnv()
{
    myLog "Debug: Enter function setCtxsetupEnv"
    # set CTX_XDL_AD_INTEGRATION environment variable
    if [[ "${joinDomainWay}" == "winbind" ]]; then 
        CTX_XDL_AD_INTEGRATION="1"
    elif [[ "${joinDomainWay}" == "centrify" ]]; then 
        CTX_XDL_AD_INTEGRATION="3"
    elif [[ "${joinDomainWay}" == "sssd" ]]; then 
        CTX_XDL_AD_INTEGRATION="4"
    elif [[ "${joinDomainWay}" == "pbis" ]]; then
        CTX_XDL_AD_INTEGRATION="5"	
    else
        myLog "Debug: joinDomainWay is not a valid value.[Error]"
    fi

    # if all ctxsetup.sh environment variables has been set then return
    local setAllCtxSetupEnvironment="yes"
    for val in ${ctxSetupEnvArray[@]}; do
        if [[ -z ${!val} ]]; then
            setAllCtxSetupEnvironment="no"
                echo
                get_str CTXINSTALL_SETUP_PARAMETERS_VERIFY
            break
        fi
    done
    if [[ "${setAllCtxSetupEnvironment}" == "yes" ]]; then  
        myLog "Debug: Exit function setCtxsetupEnv"
        return
    fi

    # The following line is used to separate output
    echo 
    while true ; do    
        get_valve CTX_XDL_DOTNET_RUNTIME_PATH \
                "$(get_str SHELL_SETUP_DOTNET_RUNTIME "/usr/bin")" \
                "/usr/bin" \
                dotnet_rutnime_path_validate
        EASYINSTALL_CTX_XDL_DOTNET_RUNTIME_PATH="$result"

        get_valve CTX_XDL_DESKTOP_ENVIRONMENT \
                "$(get_str SHELL_SETUP_DESKTOP_ENVIRONMENT "$virtual_delivery_agent")" \
                "gnome" \
                desktop_environment_validate
        EASYINSTALL_CTX_XDL_DESKTOP_ENVIRONMENT="$result"

        get_ynd CTX_XDL_SUPPORT_DDC_AS_CNAME \
                "$(get_str SHELL_SETUP_DDC_VIA_CNAME "$virtual_delivery_agent")" \
                "n"
        EASYINSTALL_CTX_XDL_SUPPORT_DDC_AS_CNAME="$result"

        get_valv CTX_XDL_DDC_LIST \
                "$(get_str SHELL_SETUP_PROVIDE_FQDN "$virtual_delivery_agent")" \
                ddc_list_validate
        EASYINSTALL_CTX_XDL_DDC_LIST="$result"

        get_numd_port CTX_XDL_VDA_PORT \
                "$(get_str SHELL_SETUP_DDC_ADDRESS "$virtual_delivery_agent")" \
                "80"
        EASYINSTALL_CTX_XDL_VDA_PORT="$result"

        get_numd_port CTX_XDL_TELEMETRY_SOCKET_PORT \
                "$(get_str SHELL_SETUP_TELEMETRY_SOCKET_ADDRESS "$virtual_delivery_agent")" \
                "7503"
        EASYINSTALL_CTX_XDL_TELEMETRY_SOCKET_PORT="$result"

        get_numd_port CTX_XDL_TELEMETRY_PORT \
                "$(get_str SHELL_SETUP_TELEMETRY_ADDRESS "$virtual_delivery_agent")" \
                "7502"
        EASYINSTALL_CTX_XDL_TELEMETRY_PORT="$result"

        get_ynd CTX_XDL_REGISTER_SERVICE \
                "$(get_str SHELL_SETUP_REG_SERVICES "$linux_virtual_desktop")" \
                "y"
        EASYINSTALL_CTX_XDL_REGISTER_SERVICE="$result"
    
        get_ynd CTX_XDL_ADD_FIREWALL_RULES \
                "$(get_str SHELL_SETUP_CFG_FIREWALL "$linux_virtual_desktop")" \
                "y"
        EASYINSTALL_CTX_XDL_ADD_FIREWALL_RULES="$result"
    
        get_ynd CTX_XDL_HDX_3D_PRO \
                "$(get_str SHELL_SETUP_HDX_3D_PRO "$linux_virtual_desktop" "$virtual_delivery_agent")" \
                "n"
        EASYINSTALL_CTX_XDL_HDX_3D_PRO="$result"
    
        if [ "$EASYINSTALL_CTX_XDL_HDX_3D_PRO" == "y" ]; then
            EASYINSTALL_CTX_XDL_VDI_MODE="y"
        else
            get_ynd CTX_XDL_VDI_MODE \
                    "$(get_str SHELL_SETUP_VDI_MODE "$linux_virtual_desktop")" \
                    "n"
            EASYINSTALL_CTX_XDL_VDI_MODE="$result"
        fi
        
        get_vale CTX_XDL_SITE_NAME \
                "$(get_str SHELL_SETUP_SITE_NAME "$virtual_delivery_agent")"
        EASYINSTALL_CTX_XDL_SITE_NAME="$result"
        if [[ -z "${EASYINSTALL_CTX_XDL_SITE_NAME}" ]]; then
            EASYINSTALL_CTX_XDL_SITE_NAME="<none>"
        fi

        get_vale CTX_XDL_LDAP_LIST \
                "$(get_str SHELL_SETUP_LDAP_LIST "$virtual_delivery_agent")"
        EASYINSTALL_CTX_XDL_LDAP_LIST="$result"
        if [[ -z "${EASYINSTALL_CTX_XDL_LDAP_LIST}" ]]; then    
            EASYINSTALL_CTX_XDL_LDAP_LIST="<none>"
        fi
        
	    get_vale CTX_XDL_SEARCH_BASE \
                "$(get_str SHELL_SETUP_SEARCH_BASE "$virtual_delivery_agent")"
        EASYINSTALL_CTX_XDL_SEARCH_BASE="$result"
        if [[ -z "${EASYINSTALL_CTX_XDL_SEARCH_BASE}" ]]; then
            EASYINSTALL_CTX_XDL_SEARCH_BASE="<none>"
        fi

        get_vale CTX_XDL_FAS_LIST \
                "$(get_str SHELL_SETUP_FAS_LIST "$virtual_delivery_agent")"
        EASYINSTALL_CTX_XDL_FAS_LIST="$result"
        if [[ -z "${EASYINSTALL_CTX_XDL_FAS_LIST}" ]]; then    
            EASYINSTALL_CTX_XDL_FAS_LIST="<none>"
        fi
        
        #get_ynd CTX_XDL_SMART_CARD \
        #        "$(get_str SHELL_SETUP_SMART_CARD "$linux_virtual_desktop")" \
        #        "n"
        #EASYINSTALL_CTX_XDL_SMART_CARD="$result"

        get_ynd CTX_XDL_START_SERVICE \
                "$(get_str SHELL_SETUP_TO_START_SERVICES "$linux_virtual_desktop")" \
                "y"
        EASYINSTALL_CTX_XDL_START_SERVICE="$result"

        get_str CTXINSTALL_CONFIRM_USER_INPUT10_CONFIGURATION

        [[ -z ${CTX_XDL_DOTNET_RUNTIME_PATH} ]] && get_str CTXINSTALL_SETUP_DOTNET_RUNTIME_PATH_VERIFY "${EASYINSTALL_CTX_XDL_DOTNET_RUNTIME_PATH}"
        [[ -z ${CTX_XDL_DESKTOP_ENVIRONMENT} ]] && get_str CTXINSTALL_SETUP_DESKTOP_ENVIRONMENT_VERIFY "${EASYINSTALL_CTX_XDL_DESKTOP_ENVIRONMENT}"
        [[ -z ${CTX_XDL_SUPPORT_DDC_AS_CNAME} ]] && get_str CTXINSTALL_SETUP_DNSCNAME_VERIFY "${EASYINSTALL_CTX_XDL_SUPPORT_DDC_AS_CNAME}"
        [[ -z ${CTX_XDL_DDC_LIST} ]] && get_str CTXINSTALL_SETUP_FQDN_DDC_VERIFY "${EASYINSTALL_CTX_XDL_DDC_LIST}"
        [[ -z ${CTX_XDL_VDA_PORT} ]] && get_str CTXINSTALL_SETUP_TCPIP_PORT_VERIFY "${EASYINSTALL_CTX_XDL_VDA_PORT}"
        [[ -z ${CTX_XDL_TELEMETRY_SOCKET_PORT} ]] && get_str CTXINSTALL_SETUP_TELEMETRY_SOCKET_PORT_VERIFY "${EASYINSTALL_CTX_XDL_TELEMETRY_SOCKET_PORT}"
        [[ -z ${CTX_XDL_TELEMETRY_PORT} ]] && get_str CTXINSTALL_SETUP_TELEMETRY_PORT_VERIFY "${EASYINSTALL_CTX_XDL_TELEMETRY_PORT}"
        [[ -z ${CTX_XDL_REGISTER_SERVICE} ]] && get_str CTXINSTALL_SETUP_REGISTER_SERVICES_VERIFY "${EASYINSTALL_CTX_XDL_REGISTER_SERVICE}"
        [[ -z ${CTX_XDL_ADD_FIREWALL_RULES} ]] && get_str CTXINSTALL_SETUP_OPEN_FIREWALL_VERIFY "${EASYINSTALL_CTX_XDL_ADD_FIREWALL_RULES}"
        [[ -z ${CTX_XDL_HDX_3D_PRO} ]] && get_str CTXINSTALL_SETUP_ENABLE_HDX3D_VERIFY "${EASYINSTALL_CTX_XDL_HDX_3D_PRO}"
        [[ -z ${CTX_XDL_VDI_MODE} ]] && get_str CTXINSTALL_SETUP_ENABLE_VDA_VERIFY "${EASYINSTALL_CTX_XDL_VDI_MODE}"
        [[ -z ${CTX_XDL_SITE_NAME} ]] && get_str CTXINSTALL_SETUP_SPECIFY_DNSSITE_VERIFY "${EASYINSTALL_CTX_XDL_SITE_NAME}"
        [[ -z ${CTX_XDL_LDAP_LIST} ]] && get_str CTXINSTALL_SETUP_FQDNPORT_LDAP_VERIFY "${EASYINSTALL_CTX_XDL_LDAP_LIST}"
        [[ -z ${CTX_XDL_SEARCH_BASE} ]] && get_str CTXINSTALL_SETUP_LDAP_BASE_VERIFY "${EASYINSTALL_CTX_XDL_SEARCH_BASE}"
        [[ -z ${CTX_XDL_FAS_LIST} ]] && get_str CTXINSTALL_SETUP_FQDNPORT_FAS_VERIFY "${EASYINSTALL_CTX_XDL_FAS_LIST}"
        #[[ -z ${CTX_XDL_SMART_CARD} ]] && get_str CTXINSTALL_SETUP_SMART_CARD_VERIFY "${EASYINSTALL_CTX_XDL_SMART_CARD}"
        [[ -z ${CTX_XDL_START_SERVICE} ]] && get_str CTXINSTALL_SETUP_START_SERVICES_VERIFY "${EASYINSTALL_CTX_XDL_START_SERVICE}"

        local str="$(get_str CTXINSTALL_USER_INPUT_CORRECT_CONFIGURATION)"
        getYesOrNo "${str}" "y"
        local ret=$?
        if [[ ${ret} -eq 0 ]]; then
            CTX_XDL_DOTNET_RUNTIME_PATH=${EASYINSTALL_CTX_XDL_DOTNET_RUNTIME_PATH}
            CTX_XDL_DESKTOP_ENVIRONMENT=${EASYINSTALL_CTX_XDL_DESKTOP_ENVIRONMENT}
            CTX_XDL_SUPPORT_DDC_AS_CNAME=${EASYINSTALL_CTX_XDL_SUPPORT_DDC_AS_CNAME}
            CTX_XDL_DDC_LIST=${EASYINSTALL_CTX_XDL_DDC_LIST}
            CTX_XDL_VDA_PORT=${EASYINSTALL_CTX_XDL_VDA_PORT}
            CTX_XDL_TELEMETRY_SOCKET_PORT=${EASYINSTALL_CTX_XDL_TELEMETRY_SOCKET_PORT}
            CTX_XDL_TELEMETRY_PORT=${EASYINSTALL_CTX_XDL_TELEMETRY_PORT}
            CTX_XDL_REGISTER_SERVICE=${EASYINSTALL_CTX_XDL_REGISTER_SERVICE}
            CTX_XDL_ADD_FIREWALL_RULES=${EASYINSTALL_CTX_XDL_ADD_FIREWALL_RULES}
            CTX_XDL_HDX_3D_PRO=${EASYINSTALL_CTX_XDL_HDX_3D_PRO}
            CTX_XDL_VDI_MODE=${EASYINSTALL_CTX_XDL_VDI_MODE}
            CTX_XDL_SITE_NAME=${EASYINSTALL_CTX_XDL_SITE_NAME}
            CTX_XDL_LDAP_LIST=${EASYINSTALL_CTX_XDL_LDAP_LIST}
            CTX_XDL_SEARCH_BASE=${EASYINSTALL_CTX_XDL_SEARCH_BASE}
	        CTX_XDL_FAS_LIST=${EASYINSTALL_CTX_XDL_FAS_LIST}
            #CTX_XDL_SMART_CARD=${EASYINSTALL_CTX_XDL_SMART_CARD}
            CTX_XDL_START_SERVICE=${EASYINSTALL_CTX_XDL_START_SERVICE}
            myLog "Debug: Exit function setCtxsetupEnv"
            return
        else
            continue
        fi
    done
    myLog "Debug: Exit function setCtxsetupEnv"
}

#
# This function is used to prompt for user input
# it is a common function for RHEL/CentOS/Ubuntu
# The following environment variables is used to replace user input 
# CTX_EASYINSTALL_HOSTNAME
# CTX_EASYINSTALL_DNS 
# CTX_EASYINSTALL_NTPS
# CTX_EASYINSTALL_DOMAIN
# CTX_EASYINSTALL_REALM
# CTX_EASYINSTALL_FQDN
# CTX_EASYINSTALL_ADINTEGRATIONWAY
# CTX_EASYINSTALL_USERNAME
#
function getUserInput()
{ 
    myLog "Debug: Enter function getUserInput"
    local setAllEnvironment="yes"
    if [[ "${isSilent}" != "yes" ]]; then
        for val in ${ctxInstallEnvArray[@]}; do
            if [[ -z "${!val}" ]]; then    
                setAllEnvironment="no"
                break
            fi
        done
    fi

    # get DNS ip address and configure DNS
    while true; do
        getDNS
        if [[ -z "${CTX_EASYINSTALL_DNS}" ]]; then    
            # if dns1 is empty ,it means that user didn't input dns
            if [[ -n ${dns1} && "${isSilent}" != "yes" ]]; then
                [[ -n ${dns1} ]] && get_str CTXINSTALL_CONFIRM_USER_DNS1_CONFIGURATION  "${dns1}"
                [[ -n ${dns2} ]] && get_str CTXINSTALL_CONFIRM_USER_DNS1_CONFIGURATION  "${dns2}"
                [[ -n ${dns3} ]] && get_str CTXINSTALL_CONFIRM_USER_DNS1_CONFIGURATION  "${dns3}"
                [[ -n ${dns4} ]] && get_str CTXINSTALL_CONFIRM_USER_DNS1_CONFIGURATION  "${dns4}"
                local str="DNS address"
                if [[ -n "${dns1}" && -z "${dns2}" && -z "${dns3}" && -z "${dns4}" ]]; then
                    info="$(get_str CTXINSTALL_USER_INPUT_CORRECT_CONFIGURATION1 "${str}" "y")"
                else
                    info="$(get_str CTXINSTALL_USER_INPUT_CORRECT_CONFIGURATION "${str}" "y")"
                fi            
                getYesOrNo "${info}" "y"    
                local ret=$?    
                if [[ "${ret}" -eq 0 ]]; then
                    break
                else
                    continue
                fi
            fi
        fi
        break
    done
    confDNS

    # get other user input
    while true; do        
        # get hostname
        getHostName

        # get NTP address 
        getNTPS

        # get Domain 
        getDomain

        # get workgroup
        getWorkgroup

        # get OU
        getOU

        # get Realm
        getRealm

        # get FQDN of AD controller
        getFqdn

        # get ADIntegrationWay
        getADIntegrationWay

        # get UserName
        getUserName    

        if [[ "${setAllEnvironment}" == "no" ]]; then
            get_str CTXINSTALL_CONFIRM_USER_INPUT10_CONFIGURATION
            [[ -z "${CTX_EASYINSTALL_HOSTNAME}" ]] && get_str CTXINSTALL_CONFIRM_USER_HOSTNAME_CONFIGURATION  "${hostName}"
            [[ -z "${CTX_EASYINSTALL_NTPS}" ]] && get_str CTXINSTALL_CONFIRM_USER_NTP_CONFIGURATION ${ntps}
            [[ -z "${CTX_EASYINSTALL_DOMAIN}" ]] && get_str CTXINSTALL_CONFIRM_USER_DOMAIN_CONFIGURATION  ${domain}  
            [[ -z "${CTX_EASYINSTALL_REALM}" ]] && get_str CTXINSTALL_CONFIRM_USER_REALM_CONFIGURATION  ${realm}  
            [[ -z "${CTX_EASYINSTALL_FQDN}" ]] && get_str CTXINSTALL_CONFIRM_USER_FQDN_CONFIGURATION  ${fqdn}  
            [[ -z "${CTX_EASYINSTALL_ADINTEGRATIONWAY}" ]] && get_str CTXINSTALL_CONFIRM_USER_AD_WAY_CONFIGURATION  ${joinDomainWay}  
            [[ -z "${CTX_EASYINSTALL_USERNAME}" ]] && get_str CTXINSTALL_CONFIRM_USER_DOMAIN_USER_CONFIGURATION  ${domainUser}       
            info="$(get_str CTXINSTALL_USER_INPUT_CORRECT_CONFIGURATION)"       
            getYesOrNo "${info}" "y"
            local ret=$?
            if [[ ${ret} -eq 0 ]]; then
                break
            else
                continue
            fi
        elif [[ "${setAllEnvironment}" == "yes" ]]; then
            break
        else
            myLog "setAllEnvironment is ${setAllEnvironment} ,this is a unexpected value"
            break
        fi
    done

    # get ctxsetup.sh script inputs
    if [[ "${isSilent}" != "yes" ]]; then
        setCtxsetupEnv
    fi
    myLog "Debug: Exit function getUserInput"
}

#
# Customize configuration file for RHEL
# 
function configurationRhel()
{
    myLog "Debug: Enter function configurationRhel()"    
    info="$(get_str CTXINSTALL_GET_USER_INPUT_CONFIGURATION 1)" 
    myPrint "$info"     
    getUserInput
    info="$(get_str CTXINSTALL_CONFIG_HOST_NAME_CONFIGURATION 2)" 
    myPrint "$info"     
    confHostNameRhel
    info="$(get_str CTXINSTALL_CONFIG_NTP_CONFIGURATION 3)" 
    myPrint "$info"     
    confNTPSRhel
    info="$(get_str CTXINSTALL_CONFIG_AD_CONFIGURATION 4)" 
    myPrint "$info"     
    confADRhel 
    info="$(get_str CTXINSTALL_JOIN_DOMAIN_CONFIGURATION 5)" 
    myPrint "$info"     
    joinDomainRhel
    myLog "Debug: Exit function configurationRhel()"
}

#
# Customize configuration file for CentOS
# 
function configurationCent()
{
    myLog "Debug: Enter function configurationCent()"
    # CentOS has the same configuration procedures as RHEL
    configurationRhel
    myLog "Debug: Exit function configurationCent()"
}

#
# Customize configuration file for Amazon linux2
# 
function configurationAmazon()
{
    myLog "Debug: Enter function configurationAmazon()"
    # Amazon has the same configuration procedures as RHEL
    configurationRhel
    myLog "Debug: Exit function configurationAmazon()"
}

#
# Configure host name for SUSE
#
function confHostNameSuse()
{
    myLog "Debug: Enter function confHostNameSuse"
    local confFile1="/etc/hostname"
    local contants1="${hostName}.${realm}"
    local confFile2="/etc/hosts"
    local contants2IPV4="127.0.0.2  $hostName"."$realm $hostName"
    local contants3IPV4="127.0.0.1  $hostName"."$realm $hostName localhost"
    local contants2IPV6="::1  $hostName"."$realm $hostName localhost"
    # Backup configuration files
    [[ -f "$confFile1" ]] && `cp "$confFile1" "$backupDir"`
    [[ -f "$confFile2" ]] && `cp "$confFile2" "$backupDir"`
    # update the contents
    # configure hostname
    echo "$contants1">"$confFile1"

    # configure hosts
    sed -i "s/^127.0.0.1/#127.0.0.1/" "${confFile2}"
    sed -i "s/^127.0.0.2/#127.0.0.2/" "${confFile2}"
    sed -i "s/^::1/#::1/" "${confFile2}"
    echo "$contants2IPV4">>"$confFile2"
    echo "$contants3IPV4">>"$confFile2"
    echo "$contants2IPV6">>"$confFile2"
    sysctl -w kernel.hostname="${hostName}.${realm}" >> "$logFile"

    myLog "Debug: $confFile1: $contants1"
    myLog "Debug: $confFile2: $contants2"
    
    confFile="/etc/sysctl.conf"
    # Backup configuration files
    [[ -f "$confFile" ]] && `cp "$confFile" "$backupDir"`
    echo "net.ipv6.conf.all.disable_ipv6 = 1">>$confFile

    confFile="/etc/sysconfig/network/dhcp"
    # Backup configuration files
    [[ -f "$confFile" ]] && `cp "$confFile" "$backupDir"`
    sed -i 's/^DHCLIENT_SET_HOSTNAME.*$/DHCLIENT_SET_HOSTNAME=\"no\"/g' "$confFile"
    sed -i 's/^WRITE_HOSTNAME_TO_HOSTS.*$/WRITE_HOSTNAME_TO_HOSTS=\"yes\"/g' "$confFile"
    
    confFile="/etc/sysconfig/nfs"
    # Backup configuration files
    [[ -f "$confFile" ]] && `cp "$confFile" "$backupDir"`
#    echo "STATD_PORT=''
#STATD_HOSTNAME=''
#LOCKD_TCPPORT=''
#LOCKD_UDPPORT=''>>"$confFile""
#        
    myLog "Debug: Exit function confHostNameSuse"
}

#
# Configure chrony
# common function for SUSE platforms
#
function confChronySuse()
{
    myLog "Debug: Enter function confChronySuse"
    ntpFile="/etc/chrony.conf"
    [[ -f "$ntpFile" ]] && cp -f "$ntpFile" "$backupDir"

    # remove any include configuration
    sed -i 's/^include.*$/#&/g' "$ntpFile"
    # remove any server
    sed -i 's/^server.*$/#&/g' "$ntpFile"
    # remove any pool
    sed -i 's/^pool.*$/#&/g' "$ntpFile"
    # rmove maxdistance settings
    sed -i 's/^maxdistance.*$/#&/g' "$ntpFile"

    [[ -n "$ntps" ]] && echo "server $ntps iburst" >> "$ntpFile"

    echo "maxdistance 16" >> "$ntpFile"

    systemctl enable chronyd >> "$logFile" 2>&1
    systemctl restart chronyd >> "$logFile" 2>&1
    if [[ "$?" -ne "0" ]]; then
        configurationStatus="Error"
    else
        if [[ -n "$ntps" ]]; then
            chronyc -a makestep >> "$logFile" 2>&1
            [[ "$?" -ne "0" ]] && myLog "failed to sync time with NTP server($ntps)[Warning]." && configurationStatus="Warning"
        fi
    fi

    myLog "Debug: Exit function confChronySuse"
}

#
# Configure NTP
# common function for SUSE platforms
#
function confNTPSSuse()
{    
    myLog "Debug: Enter function confNTPSSuse"
    [[ -z "$ntps" ]] && myLog "Debug: ntps is NULL, Exit function confNTPSSuse" && return
    
    ntpFile="/etc/ntp.conf"
    [[ -f "$ntpFile" ]] && cp -f "$ntpFile" "$backupDir"
    sed -i 's/^server.*iburst$/#&/g' "$ntpFile"
    sed -i 's/^pool.*iburst$/#&/g' "$ntpFile"
    [[ -n "$ntps" ]] && echo "server $ntps iburst">>"$ntpFile"

    sed -i '/^restrict -4 default notrap nomodify nopeer noquery$/d' "$ntpFile"
    sed -i '/^restrict -6 default notrap nomodify nopeer noquery$/d' "$ntpFile"
    sed -i '/^restrict 127.0.0.1$/d' "$ntpFile"
    sed -i '/^restrict ::1$/d' "$ntpFile"

    # stop,  sync date, Restart the service    
    /sbin/service ntpd stop  >> "$logFile"  2>&1     
    /usr/sbin/ntpdate "$ntps" >> "$logFile" 2>&1
    [[ "$?" -ne "0" ]] && myLog "failed to sync time with NTP server($ntps)[Warning]."
    /sbin/service ntpd start >> "$logFile" 2>&1       

    # Force time synchronization befor start ntpd
    ntpSysconfigFile="/etc/sysconfig/ntp"
    [[ -f "${ntpSysconfigFile}" ]] && cp -f "${ntpSysconfigFile}" "${backupDir}"
    sed -i -r 's/NTPD_FORCE_SYNC_ON_STARTUP=.*/NTPD_FORCE_SYNC_ON_STARTUP="yes"/' "${ntpSysconfigFile}"

    myLog "Debug: Exit function confNTPSSuse"
}

#
# Customize configuration files for SUSE
# will implement this function soon
# 
function configurationSuse()
{ 
    myLog "Debug: Enter function configurationSuse"
    info="$(get_str CTXINSTALL_GET_USER_INPUT_CONFIGURATION 1)"
    myPrint "$info"     
    getUserInput
    info="$(get_str CTXINSTALL_CONFIG_HOST_NAME_CONFIGURATION 2)" 
    myPrint "$info"     
    confHostNameSuse
    info="$(get_str CTXINSTALL_CONFIG_NTP_CONFIGURATION 3)" 
    myPrint "$info"
    if [[ "$osMajorVersion" -ge "15" ]]; then
        confChronySuse
    else
        confNTPSSuse
    fi
    info="$(get_str CTXINSTALL_CONFIG_AD_CONFIGURATION 4)" 
    myPrint "$info"     
    confADSuse 
    info="$(get_str CTXINSTALL_JOIN_DOMAIN_CONFIGURATION 5)" 
    myPrint "$info"     
    joinDomainSuse
    myLog "Debug: Exit function configurationSuse"
}

#
# Configure host name for Ubuntu
#
function confHostNameUbuntu()
{
    myLog "Debug: Enter function confHostNameUbuntu"
    confFile1="/etc/hostname"
    contants1="$hostName"
    confFile2="/etc/hosts"
    local contants2IPV4="127.0.0.1  $hostName"."$realm $hostName localhost"
    local contants2IPV6="::1  $hostName"."$realm $hostName localhost6"
    local contants3IPV4="127.0.1.1  $hostName"
    # Backup configuration files
    `cp "$confFile1" "$backupDir"`
    `cp /etc/hosts "$backupDir"`
    # update the contents
    # configure hostname
    echo "$contants1">"$confFile1"

    # configure hosts file
    sed -i "s/^127.0.0.1/#127.0.0.1/" "${confFile2}"
    sed -i "s/^127.0.1.1/#127.0.1.1/" "${confFile2}"
    sed -i "s/^::1/#::1/" "${confFile2}"
    sed -i '1i\'"${contants2IPV4}" "${confFile2}"
    sed -i '1a\'"${contants3IPV4}" "${confFile2}"
    echo "${contants2IPV6}" >> "${confFile2}"

    sysctl -w kernel.hostname="$hostName" >> "$logFile"

    myLog "Debug: $confFile1: $contants1"
    myLog "Debug: $confFile2: $contants2"
    myLog "Debug: Exit function confHostNameUbuntu"
}

#
# Customize configuration files for Ubuntu
#
function configurationUbuntu()
{
    myLog "Debug: Enter function configurationUbuntu"
    export DEBIAN_FRONTEND=noninteractive
    info="$(get_str CTXINSTALL_GET_USER_INPUT_CONFIGURATION 1)" 
    myPrint "$info"
    getUserInput
    info="$(get_str CTXINSTALL_CONFIG_HOST_NAME_CONFIGURATION 2)" 
    myPrint "$info"
    confHostNameUbuntu
    info="$(get_str CTXINSTALL_CONFIG_NTP_CONFIGURATION 3)" 
    myPrint "$info"
    confNTPSUbuntu
    info="$(get_str CTXINSTALL_CONFIG_AD_CONFIGURATION 4)" 
    myPrint "$info"
    confADUbuntu
    info="$(get_str CTXINSTALL_JOIN_DOMAIN_CONFIGURATION 5)" 
    myPrint "$info"
    joinDomainUbuntu   
    myLog "Debug: Exit function configurationUbuntu"

}

#
# Customize configuration files for Pardus
#
function configurationPardus()
{
    myLog "Debug: Enter function configurationPardus\n\tcall function 'configurationUbuntu' to complete the configure procedure"
    configurationUbuntu   
    myLog "Debug: Exit function configurationPardus"
}

#
# Customize configuration files for Debian
#
function configurationDebian()
{
    myLog "Debug: Enter function configurationDebian"
    export DEBIAN_FRONTEND=noninteractive
    configurationUbuntu
    myLog "Debug: Exit function configurationDebian"
}

#
# Customize site, such as Hostname, NTS, DNS etc. and join domain
#
function configuration()
{
    myLog "Debug: Enter function configuration"

    if [[ "${isSilent}" == "yes" ]] ; then
        ctxinstallEnvVariableCheck
    fi

    info="$(get_str CTXINSTALL_START_CONFIGURATION)" 
    myPrint "$info"   
    
    if [[ -n "$osPlatform" && "$osPlatform" == "red" ]]; then
        configurationRhel
    elif [[ -n "$osPlatform" && "$osPlatform" == "rocky" ]]; then
        configurationRhel
    elif [[ -n "$osPlatform" && "$osPlatform" == "centos" ]]; then
        configurationCent
    elif [[ -n "$osPlatform" && "$osPlatform" == "amzn" ]]; then
        configurationAmazon
    elif [[ -n "$osPlatform" && "$osPlatform" == "suse" ]]; then
        configurationSuse
    #elif [[ -n "$osPlatform" && "$osPlatform" == "ubuntu" ]]; then
    elif [[ -n "$osPlatform" && ( "$osPlatform" == "ubuntu" || "$osPlatform" == "kylin" ) ]]; then
        configurationUbuntu
    elif [[ -n "$osPlatform" && "$osPlatform" == "pardus" ]]; then
        configurationPardus
    elif [[ -n "$osPlatform" && "$osPlatform" == "debian" ]]; then
        configurationDebian
    else
        info="$(get_str CTXINSTALL_UNSUPPORT_PLATFORM_FAIL $osPlatform)" 
        myPrint "$info"
        exit 4
    fi
    
    if [[ "$configurationStatus" == "Success" ]]; then 
        info="$(get_str CTXINSTALL_END_CONFIGURATION )" 
    else
        info="$(get_str CTXINSTALL_END_WITH_WARNING_CONFIGURATION "${configurationStatus}" )"        
    fi
    myPrint "$info"

    echo
    myLog "Debug: Exit function configuration"
}

#
# Call ctxsetup.sh to do the further configuration
#
function callCtxsetup()
{
    myLog "Debug: Enter function callCtxsetup"    

    if [[ "${isSilent}" == "yes" ]] ; then
        ctxsetupEnvVariableCheck
    fi

    # After verfication passed, call /opt/Citrix/VDA/sbin/ctxsetup.sh to configure Linux VDA
    local info="$(get_str CTXINSTALL_CALL_CTXSETUP_INFO_VERIFICATION $verfstep  '/opt/Citrix/VDA/sbin/ctxsetup.sh')"
    myPrint "$info"
    verfstep=`expr $verfstep + 1` 
    source /opt/Citrix/VDA/sbin/ctxsetup.sh
    
    # Configure FAS
    if [ ! "$CTX_XDL_FAS_LIST" == "<none>" ]; then
	#callCtxfascfg
	echo ""
    fi
    
    myLog "Debug: Exit function callCtxsetup"
}

#
# Call ctxfascfg.sh to auto configure LVDA federated authentication
#
function callCtxfascfg()
{
    myLog "Debug: Enter function callCtxfascfg"    
    # After ctxsetup is finished, call /opt/Citrix/VDA/sbin/ctxfascfg.sh to configure Linux VDA Federated authentiation
    verfstep=`expr $verfstep + 1` 
    source /opt/Citrix/VDA/sbin/ctxfascfg.sh
    myLog "Debug: Exit function callCtxfascfg"
}

#
# Verify the configuration for RHEL
#
function verficationRhel()
{
    myLog "Debug: Enter function verficationRhel()"
    # verify the domain membership for centrify
    info="$(get_str CTXINSTALL_CHECK_DOMAIN_MEMBERSHIP_VERIFICATION "${verfstep}")"
    myPrint "$info"
    verfstep=`expr $verfstep + 1`    
    
    if [[ "${joinDomainWay}" == "centrify" ]]; then
        sudo adinfo -d
        if [[ "$?" -ne 0 ]]; then
            info="$(get_str CTXINSTALL_JOIN_DOMAIN_FAILURE_VERIFICATION "${hostName}")"
            myPrint "$info"
            exit 5
            else
            info="$(get_str CTXINSTALL_JOIN_DOMAIN_SUCCESSFULLY_VERIFICATION "${hostName}")"
            myPrint "$info"
        fi
    elif [[ "${joinDomainWay}" == "pbis" ]]; then
        result="$(sudo /opt/pbis/bin/domainjoin-cli query 2>&1)"
        res=$(echo $result | grep "Domain")
        if [[ "$res" != "" ]]; then
            info="$(get_str CTXINSTALL_JOIN_DOMAIN_SUCCESSFULLY_VERIFICATION  "${hostName}")"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_JOIN_DOMAIN_FAILURE_VERIFICATION  "${hostName}")"
            myPrint "$info"
	    exit 5
        fi	
    elif [[ -n "${joinDomainWay}" ]]; then
        # verify the domain membership for Winbind or SSSD
        # verify the domain membership for sssd on RHEL8
        if [[ "${joinDomainWay}" == "sssd" && "$version" == "8" ]]; then
            if [[ "$realm" == "" ]]; then
                myLog "Skip domain membership verification."
            else
                result="$(sudo realm list 2>&1)"
                res=$(echo $result |grep $realm)
                if [[ "$res" != "" ]]; then
                    info="$(get_str CTXINSTALL_JOIN_DOMAIN_SUCCESSFULLY_VERIFICATION  "${hostName}")"
                    myPrint "$info"
                else
                    info="$(get_str CTXINSTALL_JOIN_DOMAIN_FAILURE_VERIFICATION  "${hostName}")"
                    myPrint "$info"
                    exit 5
                fi
            fi
        else
            result="$(sudo net ads testjoin 2>&1)"
            res=$(echo $result | grep "Join is OK")
            if [[ "$res" != "" ]]; then
                info="$(get_str CTXINSTALL_JOIN_DOMAIN_SUCCESSFULLY_VERIFICATION  "${hostName}")"
                myPrint "$info"
            else
                info="$(get_str CTXINSTALL_JOIN_DOMAIN_FAILURE_VERIFICATION  "${hostName}")"
                myPrint "$info"
                exit 5
            fi
        fi
    fi

    # retain this sentence 
    #str="$HOSTNAME"'\$@'"$REALM"
    info="$(get_str CTXINSTALL_CHECK_ESSENTIAL_PROCESS_VERIFICATION "${verfstep}")"
    myPrint "$info"
    verfstep=`expr $verfstep + 1` 
    
    # Check if critical system processes are running
    [[ "$osPlatform" == "red" || "$osPlatform" == "centos" || "$osPlatform" == "amzn" || "$osPlatform" == "rocky" ]] && checkList=("messagebus" "oddjobd") 
    [[ "$osPlatform" == "ubuntu" || "$osPlatform" == "pardus" || "$osPlatform" == "debian" ]] && checkList=("oddjobd") 
    checkNum=${#checkList[@]}
    for((i=0;i<checkNum;i++)); do
        info="$(get_str CTXINSTALL_CHECK_PROCESS_STATUS_VERIFICATION "${checkList[$i]}")"
        myPrint "$info"
        #/usr/sbin/service  ${checkList[$i]} status >> "$logFile"   
        startService "${checkList[$i]}" "status"
    
        if [[  "$?" -eq "0" ]]; then
            info="$(get_str CTXINSTALL_PROCESS_IS_RUNNING_VERIFICATION "${checkList[$i]}")"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_PROCESS_IS_NOT_RUNNING_AND_TRY_VERIFICATION "${checkList[$i]}")"
            myPrint "$info"
            #/usr/sbin/service ${checkList[$i]} start >> "$logFile"
            startService "${checkList[$i]}"  "start"
       
            info="$(get_str CTXINSTALL_START_PROCESS_FAILURE_VERIFICATION ${checkList[$i]})"
            [[  "$?" -ne "0" ]] && myPrint "$info" && verficationStatus="Warning"
        fi
    done
    
    callCtxsetup
    
    info="$(get_str CTXINSTALL_CHECK_LVDA_PROCESS_VERIFICATION "${verfstep}")"
        myPrint "$info"
    verfstep=`expr $verfstep + 1`
    # Check if processes ctxhdx & ctxvda are running
    checkList=("ctxhdx" "ctxvda")
    checkNum=${#checkList[@]}
    for((i=0;i<checkNum;i++)); do
        info="$(get_str CTXINSTALL_CHECK_PROCESS_STATUS_VERIFICATION "${checkList[$i]}")"
        myPrint "$info"
        str="$(ps -ef |grep  "${checkList[$i]}" |grep -v grep 2>&1)"
        if [[ "$?" -eq "0" &&  -n "$str" ]]; then        
            info="$(get_str CTXINSTALL_PROCESS_IS_RUNNING_VERIFICATION "${checkList[$i]}")"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_PROCESS_IS_NOT_RUNNING_VERIFICATION "${checkList[$i]}")"            
            myPrint "$info"
            verficationStatus="Error"
        fi
    done

    myLog "Debug: Exit function verficationRhel()"
}

#
# Verify the configuration for CentOS
#
function verficationCent()
{
    myLog "Debug: Enter function verficationCent()"
    # Take the same logic as RHEL
    verficationRhel
    myLog "Debug: Exit function verficationCent()"
}

#
# Verify the configuration for Amazon linux2
#
function verficationAmazon()
{
    myLog "Debug: Enter function verficationAmazon()"
    # Take the same logic as RHEL
    verficationRhel
    myLog "Debug: Exit function verficationAmazon()"
}

#
# Verify the configuration for SUSE
#
function verficationSuse()
{
    myLog "Debug: Enter function verficationSuse()"
    # verify the domain membership for centrify
    info="$(get_str CTXINSTALL_CHECK_DOMAIN_MEMBERSHIP_VERIFICATION "${verfstep}")"
        myPrint "$info"
    verfstep=`expr $verfstep + 1`
    if [[ "${joinDomainWay}" == "centrify" ]]; then
        sudo adinfo -d
        if [[ "$?" -ne 0 ]]; then
         info="$(get_str CTXINSTALL_JOIN_DOMAIN_FAILURE_VERIFICATION "${hostName}")"
         myPrint "$info"
         exit 5
        else
         info="$(get_str CTXINSTALL_JOIN_DOMAIN_SUCCESSFULLY_VERIFICATION "${hostName}")"
         myPrint "$info"
        fi   
    elif [[ "${joinDomainWay}" == "pbis" ]]; then
        result="$(sudo /opt/pbis/bin/domainjoin-cli query 2>&1)"
        res=$(echo $result | grep "Domain")
        if [[ "$res" != "" ]]; then
            info="$(get_str CTXINSTALL_JOIN_DOMAIN_SUCCESSFULLY_VERIFICATION  "${hostName}")"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_JOIN_DOMAIN_FAILURE_VERIFICATION  "${hostName}")"
            myPrint "$info"
	    exit 5
        fi	
    else
    # verify the domain membership for Winbind or Sssd
        result="$(sudo net ads testjoin 2>&1)"
        res=$(echo $result | grep "Join is OK")
        if [[ "$res" != "" ]]; then
           info="$(get_str CTXINSTALL_JOIN_DOMAIN_SUCCESSFULLY_VERIFICATION  "${hostName}")"
           myPrint "$info"
        else
           info="$(get_str CTXINSTALL_JOIN_DOMAIN_FAILURE_VERIFICATION  "${hostName}")"
           myPrint "$info"
           exit 5
        fi
    fi
  
    str="$HOSTNAME"'\$@'"$REALM"
       
    callCtxsetup
    
    # Check if processes ctxhdx & ctxvda are running
    info="$(get_str CTXINSTALL_CHECK_LVDA_PROCESS_VERIFICATION "${verfstep}")"
        myPrint "$info"
    verfstep=`expr $verfstep + 1`
    checkList=("ctxhdx" "ctxvda")
    checkNum=${#checkList[@]}
    for((i=0;i<checkNum;i++)); do
        info="$(get_str CTXINSTALL_CHECK_PROCESS_STATUS_VERIFICATION "${checkList[$i]}")"
        myPrint "$info"
        str="$(ps -ef |grep  ${checkList[$i]} |grep -v grep 2>&1)"
        if [[ "$?" -eq "0" &&  -n "$str" ]]; then        
            info="$(get_str CTXINSTALL_PROCESS_IS_RUNNING_VERIFICATION "${checkList[$i]}")"
            myPrint "$info"
        else
            info="$(get_str CTXINSTALL_PROCESS_IS_NOT_RUNNING_VERIFICATION "${checkList[$i]}")"
            myPrint "$info"
            verficationStatus="Error"
        fi
    done

    myLog "Debug: Exit function verficationSuse()"
}

#
# Verify the configuration for Ubuntu
#
function verficationUbuntu()
{
    myLog "Debug: Enter function verficationUbuntu()"
    # Take the same logic as RHEL
    verficationRhel
    myLog "Debug: Exit function verficationUbuntu()"
}

#
# Verify the configuration for Pardus
#
function verficationPardus()
{
    myLog "Debug: Enter function verficationPardus()"
    # Take the same logic as RHEL
    verficationRhel
    myLog "Debug: Exit function verficationPardus()"
}

#
# Verify the configuration for Debian
#
function verficationDebian()
{
    myLog "Debug: Enter function verficationDebian()"
    # Take the same logic as RHEL
    verficationRhel
    myLog "Debug: Exit function verficationDebian()"
}

#        
# Verify the change we made in phases 2/3
# 
function verfication()
{
    myLog "Debug: Enter function verification()"

    version="${osVersion:0:1}"
    if [[ "${isSilent}" == "yes" ]] ; then
        if [[ "${CTX_XDL_AD_INTEGRATION}" == "1" ]]; then 
            joinDomainWay="winbind"
        elif [[ "${CTX_XDL_AD_INTEGRATION}" == "3" ]]; then 
            joinDomainWay="centrify"
        elif [[ "${CTX_XDL_AD_INTEGRATION}" == "4" ]]; then 
            joinDomainWay="sssd"
        elif [[ "${CTX_XDL_AD_INTEGRATION}" == "5" ]]; then
            joinDomainWay="pbis"	
        fi
    fi

    startInfo="$(get_str CTXINSTALL_START_VERIFICATION)"   
    myPrint "$startInfo"
    verfstep=1
    if [[ -n "$osPlatform" && "$osPlatform" == "red" ]]; then
        verficationRhel
    elif [[ -n "$osPlatform" && "$osPlatform" == "rocky" ]]; then
        verficationRhel
    elif [[ -n "$osPlatform" && "$osPlatform" == "centos" ]]; then
        verficationCent
    elif [[ -n "$osPlatform" && "$osPlatform" == "amzn" ]]; then
        verficationAmazon
    elif [[ -n "$osPlatform" && "$osPlatform" == "suse" ]]; then
        verficationSuse
   #Kylin
   # elif [[ -n "$osPlatform" && "$osPlatform" == "ubuntu" ]]; then
    elif [[ -n "$osPlatform" && ( "$osPlatform" == "ubuntu" || "$osPlatform" == "kylin" ) ]]; then
        verficationUbuntu
    elif [[ -n "$osPlatform" && "$osPlatform" == "pardus" ]]; then
        verficationPardus
    elif [[ -n "$osPlatform" && "$osPlatform" == "debian" ]]; then
        verficationDebian
    else       
        info="$(get_str CTXINSTALL_UNSUPPORT_PLATFORM_FAIL $osPlatform)"
        myPrint "$info"
        exit 5
    fi
   
    if [[ "$verficationStatus" == "Success" ]]; then         
        info="$(get_str CTXINSTALL_END_VERIFICATION)"
    else
        info="$(get_str CTXINSTALL_END_WITH_WARNING_VERIFICATION "${verficationStatus}" )"        
    fi
    myPrint "$info"
    myLog "Debug: Exit function verification()"
}

#
# Check if address is IPv4
#
function checkIPAddr4()
{
    myLog "Debug: Enter function checkIPAddr4"
    if [[ `echo $1 | awk -F . '{print NF}'` -ne 4 ]]; then
        myLog "Debug: Exit function checkIPAddr4 with 1"
        return 1
    fi
    ipaddr=$1
    a=`echo $ipaddr|awk -F . '{print $1}'`
    b=`echo $ipaddr|awk -F . '{print $2}'` 
    c=`echo $ipaddr|awk -F . '{print $3}'` 
    d=`echo $ipaddr|awk -F . '{print $4}'`
    for num in $a $b $c $d
    do
        if [[ $num -gt 255 || $num -lt 0 ]]; then
            myLog "Debug: Exit function checkIPAddr4 with 1"
            return 1
        fi
    done
    myLog "Debug: Exit function checkIPAddr4 with 0"
    return 0
}

#
# Configure use IPv4 or IPv6 for registration
#
function useIPv6()
{
    myLog "Debug: Enter function useIPv6"
    myLog "Debug: Check env is 1.Pure IPv4 2.Pure IPv6 3.Hybrid"
    local address=$dns1
   
    if [[ -n $address ]]; then
        result=`expr index $address '.'`
        if [[ "$result" -ne "0" ]]; then
            useIPv6="no"
        else
            useIPv6="yes"
        fi
    elif [[ ! -f /etc/resolv.conf ]]; then
        myLog "Debug: no /etc/resolv.conf file, please configure DNS first"
        info="$(get_str CTXINSTALL_EXECUTED_WITH_ERROR "${fname}" "Error" "${logFile}" )"
        myPrint "$info"
        exit 1        
    else
        OLD_IFS="$IFS"
        IFS=$'\x0A'
        # read content line by line, resolve ip address and judge its type
        for line in `cat /etc/resolv.conf`
        do
            # get content before the first '#', if there is 'nameserver', get the string after it
            res=${line%%#*}
            ret=$(echo $res | grep "nameserver")
            ip=${ret##*nameserver}
            if [[ "$ret" != "" && "$ip" != "" ]]; then
                checkIPAddr4 $ip
                resultV4=$?
                if [[ "$resultV4" -eq "0" ]]; then
                    useIPv6="no"
                    break
                else
                    resultV6=`echo $ip | grep : | grep '[a-f\|A-F\|0-9]'`
                    if [[ $resultV6 ]]; then
                        useIPv6="yes"
                    else
                        continue
                    fi
                fi
            else
                continue
            fi
        done
        IFS=$OLD_IFS
    fi

    if [ "$useIPv6" == "yes" ]
    then
        myLog "Debug: use IPv6 for registration"
        /opt/Citrix/VDA/bin/ctxreg create -k "HKLM\Software\Policies\Citrix\VirtualDesktopAgent" -t "REG_DWORD" -v "OnlyUseIPv6ControllerRegistration" -d "0x00000001" --force
    fi
    myLog "Debug: Exit function useIPv6"
}
  
#  
# Commit the installation,  remove all the backup files
# after that, no backout can be allowed.
#
function commit()
{
    myLog "Debug: Enter funciont commit"
    info1="$(get_str CTXINSTALL_START_COMMIT)"
    info2="$(get_str CTXINSTALL_INFO_COMMIT)"
    info3="$(get_str CTXINSTALL_END_COMMIT)"
    myLog "Debug: Enter function commit()"
    myPrint "$info1"
    if [[ -d $backupDir ]]; then
       `$RM -f -r $backupDir`
    fi
    myPrint "$info2"
    myPrint "$info3"
    myLog "Debug: Exit funciont commit"
}

#  
# Restore the change in configuration files 
#
function backout()
{
    myLog "Debug: Enter function backout"
    startInfo="$(get_str CTXINSTALL_START_BACKOUT)"
    endInfo="$(get_str CTXINSTALL_END_BACKOUT)"
    myPrint "$startInfo"
    if [[ ! -d "$backupDir" ]]; then
        info="$(get_str CTXINSTALL_DIR_NOT_EXIST_BACKOUT "${backupDir}")"
        myPrint "$info"
        myLog "Debug: Exit function backout()"
        return
    fi
    for file in ${backupDir}/*; do
        fileName=`basename $file`
        targetDir=""
        case $fileName in
           hostname)
             targetDir="/etc/" 
             ;;
           network) 
             targetDir="/etc/sysconfig/"
             ;;
           hosts)
             targetDir="/etc/"
             ;;
           chrony.conf)
             if [[ "$osPlatform" == "ubuntu" ]]; then 
                 targetDir="/etc/chrony/"                
             else
                 targetDir="/etc/"
             fi
             ;;
           ntp.conf)
             targetDir="/etc/"
             ;;
           krb5.conf)
             targetDir="/etc/"
             ;;
           pam_winbind.conf)
             targetDir="/etc/security/"
             ;;
           smb.conf)
             targetDir="/etc/samba/"
             ;;
           sssd.conf)
             targetDir="/etc/sssd/"
             ;;
           nsswitch.conf)
             targetDir="/etc/"
             ;;             
           ?)
             info="$(get_str CTXINSTALL_FILE_CANNOT_RESTORE_BACKOUT "${fileName}")"
             myPrint "$info"
             ;;
        esac       
        
        info1="$(get_str CTXINSTALL_GARBAGE_FILE_BACKOUT "${fileName}")"
        info2="$(get_str CTXINSTALL_FAIL_RESTORE_FILE_BACKOUT "${fileName}")"
        info3="$(get_str CTXINSTALL_RESTORE_FILE_SUCCESSFULL_BACKOUT "${fileName}")"
        [[ -z "$targetDir" ]] && myPrint "$info1"
        `cp  -f "${backupDir}""/""$fileName" "$targetDir"` 
        if [[ "$?" -ne "0" ]]; then 
           myPrint "$info2"
        else 
           myPrint "$info3"
        fi
    done
    myPrint "$endInfo"
    echo
    myLog "Debug: Exit function backout()"
}

#
# Clear all the backup and temperary files and directores
# Dump end time slot to the log file
function clearFile()
{
      myLog "Debug: Enter function clearFile"
    str="`date "+%Y-%m-%d %H:%M:%S"`"    
    echo "############################ End $scriptName($str) ############################">>$logFile
}

#
# Ask user to 
#  1. configure the "Machine Catalogs" and "Delivery Groups" in Citrix Studio 
#     2. reboot the server to solve potential problems           
# 
function finishingConfig()
{
      myLog "Debug: Enter function rebootServer"
    # output recommention info
    get_str CTXINSTALL_FINISHING_CONFIG 
      myLog "Debug: Exit function rebootServer"
}

################## main process block #####################
main()
{
    # Check if the user is an root,only root has the permission to run this script
    checkUser

    # Parse parameter
    parameterParse "$@"
    
    # Create log file
    createLogFile

    # output some info on this tool 
    get_str CTXINSTALL_BEGIN_WARNING "${fname}"  "${logFile}"

    # Get current system information
    getSysInfo

    # Phase 1:  check if the environment meets the pre-condition to configure the Linux VDA
    [[ "$isPreCheck" == "yes" ]]&&preCheck

    # Phase 2:  Install the packages which Linux VDA dependents upon
    [[ "$isInstallation" == "yes" ]]&&installation
    
    # Phase 3:  Customize site, such as Hostname, NTS, DNS etc. and join domain
    [[ "$isConfiguration" == "yes" ]]&&configuration
  
    # Phase 4:  Verify the change we made in phases 2/3
    [[ "$isVerfication" == "yes" ]]&&verfication
    
    # Phase 5:  Commit the installation
    [[ "$isCommit" == "yes" ]]&&commit
    
    # Check if only use IPv6 or not
    useIPv6
    
    # Restore the change in configuration files
    [[ "$isBackout" == "yes" ]]&&backout          
    
    # Ask user to reboot the server
    [[ "$isFinishing" == "yes" ]]&&finishingConfig 

    if [[ "$preCheckStatus" == "Error" ||  \
          "$installationStatus" == "Error" || \
          "$configurationStatus" == "Error" || \
          "$verficationStatus" == "Error" ]]; then        
        info="$(get_str CTXINSTALL_EXECUTED_WITH_ERROR "${fname}" "Error" "${logFile}" )"
    elif [[ "$preCheckStatus" == "Warning" ||  \
          "$installationStatus" == "Warning" || \
          "$configurationStatus" == "Warning" || \
          "$verficationStatus" == "Warning" ]]; then        
        info="$(get_str CTXINSTALL_EXECUTED_WITH_ERROR "${fname}" "Warning" "${logFile}" )"
    else
        info="$(get_str CTXINSTALL_EXECUTED_SUCCESSFULLY "${fname}")"
    fi
    myPrint "$info"  
    
    # Clear all the temperary files
    clearFile

    if [[ "$preCheckStatus" == "Error" ]]; then
        exit 2
    fi
    if [[ "$installationStatus" == "Error" ]]; then
        exit 3
    fi
    if [[ "$configurationStatus" == "Error" ]]; then
        exit 4
    fi
    if [[ "$verficationStatus" == "Error" ]]; then
        exit 5
    fi
    exit 0
}
main "$@"

