#!/bin/bash

R="\e[31m"
Y="\e[33m"
G="\e[32m"
N="\e[0m"
U="\e[4m"

pend_count=0

racadm_check () {
target=$1
value=$2
result=$(sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get $target)
echo $result
if [[ ! $result =~ $value ]];then
echo -e "\n\tChanging $target to $value : \n"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set $target $value
else
echo -e "\n\t$target already matched with $value ..\n"
fi
#exit
}

racadm_pending () {
target=$1
value=$2
result=$(sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get $target)
check_pen=$(echo $result | grep -o Pending)
echo $result
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get $target | grep -v Pending | grep "$value"
if [ $? = 0 ];then
REBOOT["$pend_count"]=NO
else
REBOOT["$pend_count"]=YES
if [ "$check_pen" != Pending ];then
echo -e "\n\tChanging $target to $value : \n"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set $target $value
jobqueue ${ip_list[i]} BIOS.Setup.1-1
else
echo -e "\nA Change is already in Pending state for $target, Please Reboot to apply the Change.."
fi
fi
(( pend_count += 1 ))
}

racadm_check_enable () {
target=$1
value=$2
result=$(sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get $target)
echo $result
if [[ !($result =~ "Disabled") && $value -eq "0" ]];then
echo -e "\n\tChanging $target to $value (Disabled) : \n"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set $target $value
elif [[ !($result =~ "Enabled") && $value -eq "1" ]];then
echo -e "\n\tChanging $target to $value (Enabled) : \n"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set $target $value
else
echo -e "\n\tNo Change needed: $target already matched with $value..\n"
fi
}

INPUT=$1
[ ! -f $INPUT ] && { echo -e "\n$INPUT file not found\n"; exit 99; }
[ $# != 1 ] && echo -e "\nUSAGE : $0 [INPUT file]\n" && exit

read -p "Please Enter the IDRAC Username :" login

read -sp "Please Enter the IDRAC Password :" pass

jobqueue () {
echo -e "\n"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@$1 racadm jobqueue create $2 | tee /tmp/jobqueue.$$
JOB=$(grep "Job ID" /tmp/jobqueue.$$ | awk -F "=" '{print $2}' | awk -F "]" '{print $1}')
echo $JOB
[ -n "$JOB" ] && sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@$1 racadm jobqueue view -i $JOB || sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@$1 racadm jobqueue view | egrep -i "Job|scheduled|message|status"
rm -rf /tmp/jobqueue.$$
}

OLDIFS=$IFS
IFS=","
while read RAC_IPADDR BMC_NAME BMC_NETMASK BMC_GATEWAY BMC_pDNS BMC_sDNS BMC_DOMAIN
  do

    [[ "$RAC_IPADDR" =~ ^#.*$ ]] && continue

    ip_list=("${ip_list[@]}" $RAC_IPADDR)
    dns_idracNAME=("${dns_idracNAME[@]}" $BMC_NAME)
    netmask_list=("${netmask_list[@]}" $BMC_NETMASK)
    gateway_list=("${gateway_list[@]}" $BMC_GATEWAY)
    pdns_list=("${pdns_list[@]}" $BMC_pDNS)
    sdns_list=("${sdns_list[@]}" $BMC_sDNS)
    domain_list=("${domain_list[@]}" $BMC_DOMAIN)
    
  done < $INPUT

IFS=$OLDIFS


for ((i=0;i<${#ip_list[@]};++i))
do

eval mkdir -p $(pwd)/idrac_logs
DATE="$(date +%m%Y%d%H%M%S)"
log_file="$(pwd)/idrac_logs/${dns_idracNAME[i]}.$DATE"
echo -e "Log is being written to $log_file"
exec &> >(tee -a "$log_file")
  
echo -e "\n\n${G}WORKING ON ${ip_list[i]}/${dns_idracNAME[i]} now ..${N}\n"

#echo -e "\n*******************************************\n"
echo -e "\n********START iDRAC NETWORK SETTINGS********\n"
#echo -e "\n*******************************************\n"
#Set iDRAC DNS Name
racadm_check iDRAC.NIC.DNSRacName "${dns_idracNAME[i]}"

#Set iDRAC domain name
racadm_check iDRAC.NIC.DNSDomainName "${domain_list[i]}"

#set iDRAC IP
racadm_check iDRAC.IPv4.Address "${ip_list[i]}" 

#set NETMASK for iDRAC IP
racadm_check iDRAC.IPv4.Netmask "${netmask_list[i]}"

#set GATEWAY for iDRAC IP
racadm_check iDRAC.IPv4.Gateway "${gateway_list[i]}" 

#set iDRAC IP DHCP to Disabled
racadm_check_enable iDRAC.IPv4.DHCPEnable "0"

#set iDRAC IP DNS from DHCP to Disabled
racadm_check_enable iDRAC.IPv4.DNSFromDHCP "0"

# setup the primary DNS
racadm_check iDRAC.IPv4.DNS1 "${pdns_list[i]}"

# setup the secondary DNS
racadm_check iDRAC.IPv4.DNS2 "${sdns_list[i]}"

#Enable IPMI
racadm_check_enable iDRAC.IPMILan.Enable "1"

#echo -e "\n*******************************************\n"
echo -e "\n*********END iDRAC NETWORK SETTINGS*********\n"
#echo -e "\n*******************************************\n"

echo -e "\n\n*********START BIOS CONFIGURATION*********\n"

#BIOS performance Mode
#sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get BIOS.SysProfileSettings.SysProfile | grep -v Pending | grep "PerfOptimized"
#if [ $? = 0 ];then
#REBOOT[0]=NO
#else
#REBOOT[0]=YES
#sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set BIOS.SysProfileSettings.SysProfile PerfOptimized
#jobqueue ${ip_list[i]} BIOS.Setup.1-1
#fi

racadm_pending BIOS.SysProfileSettings.SysProfile PerfOptimized

echo -e "\nLifeCycle Controller State :"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get LifecycleController.LCAttributes.LifecycleControllerState | grep Enabled
if [ $? != 0 ];then
echo -e "\n${G}Enabling LifeCycle Controller..${N}\n"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set LifecycleController.LCAttributes.LifecycleControllerState 1
fi
echo -e "\nCheck for BIOS boot mode :"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get bios.biosbootsettings.BootMode | grep -v Pending | grep "Bios"
if [ $? = 0 ];then
REBOOT[1]=NO
else
REBOOT[1]=YES
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set bios.biosbootsettings.BootMode Bios
jobqueue ${ip_list[i]} BIOS.Setup.1-1
fi

echo -e "\nnic.nicconfig.1.LegacyBootProto :"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get nic.nicconfig.1.LegacyBootProto | grep -v Pending | grep "NONE"
if [ $? = 0 ];then
REBOOT[2]=NO
else
REBOOT[2]=YES
echo -e "\n" && sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set nic.nicconfig.1.LegacyBootProto NONE
jobqueue ${ip_list[i]} NIC.Integrated.1-1-1
fi

echo -e "\nnic.nicconfig.3.LegacyBootProto :"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get nic.nicconfig.3.LegacyBootProto | grep -v Pending | grep "PXE"
if [ $? = 0 ];then
REBOOT[3]=NO
else
REBOOT[3]=YES
echo -e "\n" && sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set nic.nicconfig.3.LegacyBootProto PXE
jobqueue ${ip_list[i]} NIC.Integrated.1-3-1
fi

echo -e "\nCheck for BIOS Sequence :"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get bios.biosbootsettings.BootSeq|grep "HardDisk.List.1-1,NIC.Integrated.1-3-1"
if [ $? = 0 ];then
REBOOT[4]=NO
else
REBOOT[4]=YES
echo -e "\n" && sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set bios.biosbootsettings.BootSeq HardDisk.List.1-1,NIC.Integrated.1-3-1
jobqueue ${ip_list[i]} BIOS.Setup.1-1
fi

echo -e "\n\n*********END BIOS CONFIGURATION*********\n"

echo -e ${REBOOT[@]} | grep -i YES
if [ $? = 0 ];then
read -p "$i : Needs Reboot for the BIOS changes..Do you want to REBOOT..? (YES/no)" prompt
if [ $prompt = YES ];then
echo -e "\n${Y}Rebooting ${ip_list[i]}..${N}\n"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm serveraction powercycle
else
echo  -e "\n${Y}$i : User Chosen not to Reboot..${N}\n"
fi
else
echo -e "\n${G}$i : Reboot NOT required..${N}\n"
fi
yes - | head -45 | tr "\n" " "
echo -e "\n"

done

#Cleanup logfiles older than 5 days.
find idrac_logs/ -type f -mtime +5 -exec rm -f '{}' \;
