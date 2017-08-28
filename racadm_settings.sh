#!/bin/bash

R="\e[31m"
Y="\e[33m"
G="\e[32m"
N="\e[0m"
U="\e[4m"
B="\e[34m"

pend_count=0
DATE="$(date +%m%Y%d%H%M%S)"
rerun_log_file="$(pwd)/Re-Run-FailediDRACList.$DATE"
TIME_LIMIT=180

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
}

power_wait_reboot () {
    echo -e ${REBOOT[@]} | grep -i YES
    if [ $? = 0 ];then
            echo -e "\n${Y}Rebooting $1 ..${N}\n"
            sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@$1 racadm serveraction powercycle
            power_wait $1
    else
        echo -e "\n${G}$1 : Reboot NOT required..${N}\n"
    fi
    yes - | head -45 | tr "\n" " "
    echo -e "\n"
}

rac_ping_check () {
echo -e "\n${Y}Check if $1 is reachable..${N}\n"
ping -c2 $1 -W 2
if [ $? != 0 ];then
echo -e "${R}$1 : is not reachable..\n${N}"
exit 22
fi
}

rac_queue_check () {
echo -e "\n${Y}Checking for any pending jobs for $1 ..\n${N}"
sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@$1 racadm jobqueue view | grep ^Message | egrep -i "New|Scheduled"
if [ $? = 0 ];then
echo -e "\n${R}$1 : Please complete all the pending jobs, and re-run this script..\n${N}"
exit 55
fi
}

racadm_pending () {
    target=$1
    value=$2
    jobqueuetarget=$3
    result=$(sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get $target)
    check_pen=$(echo $result | grep -o Pending)
    job_pen=$(sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm jobqueue view | grep -A 4 $target | egrep -i -o "New|Scheduled")
    echo $result
    sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get $target | grep -v Pending | grep "$value"
    if [ $? = 0 ];then
	REBOOT["$pend_count"]=NO
	    echo -e "${ip_list[i]}" >> $rerun_log_file
    else
	REBOOT["$pend_count"]=YES
	if [ "$check_pen" = Pending ] && [ -z "$job_pen" ];then
	    jobqueue ${ip_list[i]} "$jobqueuetarget"
            echo -e "\n${Y}A Change is already in Pending state for $target, System will be Rebooted to apply the Change $target with job $jobqueuetarget ..\n${N}"
	else
            echo -e "\n\tChanging $target to $value : \n"
            sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set $target $value
            jobqueue ${ip_list[i]} "$jobqueuetarget"
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


power_wait () {
echo
echo "Hit Control-C to exit before $TIME_LIMIT seconds,but Racadm Jobs will still run .."
echo
SECONDS=0
while [ "$SECONDS" -le "$TIME_LIMIT" ]
do
if [ -s "/tmp/$1-created-jobs.$DATE" ];then
job_id=$(tail -1 /tmp/$1-created-jobs.$DATE)
job_status=$(sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@$1 racadm jobqueue view -i $job_id | grep ^Message)

if [[ "$job_status" =~ ^.*completed ]];then
echo -e "\n${G}Last Job $job_id Successfully Completed..Waiting for the System to be fully UP..\n${N}"
sleep 20 && break
fi

echo -e "\n${Y}Waiting for the Pending Jobs to be Completed..\n${N}"
echo -e "${Y}Current Job status : $job_status\n${N}"
sleep 30
else
echo -e "\n${R}Job file /tmp/$1-created-jobs.$DATE NOT found/empty ..\n${N}"
break
fi

if [ "$SECONDS" -gt "$TIME_LIMIT" ];then
echo -e "\n${R}Timed Out for System UP ..\n${N}"
fi

done

}


INPUT=$1
[ ! -f $INPUT ] && { echo -e "\n$INPUT file not found\n"; exit 99; }
[ $# != 1 ] && echo -e "\nUSAGE : $0 [INPUT file]\n" && exit

read -p "Please Enter the IDRAC Username :" login

read -sp "Please Enter the IDRAC Password :" pass

jobqueue () {
    echo -e "\n"
    sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@$1 racadm jobqueue create $2 | tee /tmp/jobqueue.$$
    JOB=$(grep "Commit JID" /tmp/jobqueue.$$ | awk -F "=" '{print $2}' | tr -d " ")
    echo $JOB | tee -a /tmp/${1}-created-jobs.$DATE
    [ -n "$JOB" ] && sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@$1 racadm jobqueue view -i $JOB || sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@$1 racadm jobqueue view | egrep -i "Job|scheduled|message|status"
#    rm -rf /tmp/jobqueue.$$
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

#Create log file for a Re-Run iDRAC list
echo -e "\n${B}==================================================="
echo -e "\n${B}Failed iDRAC IP addresses are being writtent to log file ${U}"$rerun_log_file".$N$B Please Rerun the script on those IP addresses."
echo -e "\n${B}You only see the above log file in the PWD in a Failed Scenario. If everything goes well, then the above log file won't get generated."
echo -e "\n${B}===================================================${N}\n"

for ((i=0;i<${#ip_list[@]};++i))
do
    eval mkdir -p $(pwd)/idrac_logs
    DATE="$(date +%m%Y%d%H%M%S)"
    log_file="$(pwd)/idrac_logs/${dns_idracNAME[i]}.$DATE"
    echo -e "\n\nLog is being written to $log_file..."
    exec &> >(tee -a "$log_file")
      
    echo -e "\n\n${G}WORKING ON ${ip_list[i]}/${dns_idracNAME[i]} now ..${N}\n"

    #Reset the Reboot array
    REBOOT=()
    
    rac_ping_check "${ip_list[i]}"

    rac_queue_check "${ip_list[i]}"

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
	echo -e "\nBIOS System Profile :"
	racadm_pending "BIOS.SysProfileSettings.SysProfile" "PerfOptimized" "BIOS.Setup.1-1"

    #Check LifecycleControllerState
	echo -e "\nLifeCycle Controller State :"
	racadm_check_enable LifecycleController.LCAttributes.LifecycleControllerState "1"
    
    #Check for BIOS mode set to bios
    echo -e "\nCheck for BIOS boot mode :"
    racadm_pending "bios.biosbootsettings.BootMode" "Bios" "BIOS.Setup.1-1"
    
    #Change NIC1 boot to NONE
    echo -e "\nnic.nicconfig.1.LegacyBootProto :"
    racadm_pending "nic.nicconfig.1.LegacyBootProto" "NONE" "NIC.Integrated.1-1-1"
    
    #Change NIC3 boot to PXE
    echo -e "\nnic.nicconfig.3.LegacyBootProto :"
    racadm_pending "nic.nicconfig.3.LegacyBootProto" "PXE" "NIC.Integrated.1-3-1"
    
    power_wait_reboot ${ip_list[i]}
   
    #Again Reset the array
    REBOOT=()
    pend_count=0


    #Change BIOS sequence order
    echo -e "\nCheck for BIOS Sequence :"
    #racadm_pending "bios.biosbootsettings.BootSeq" "HardDisk.List.1-1,NIC.Integrated.1-3-1" "BIOS.Setup.1-1"
    sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get bios.biosbootsettings.BootSeq|grep "HardDisk.List.1-1,NIC.Integrated.1-3-1"
    if [ $? = 0 ];then
	REBOOT[pend_count]=NO
    else
	sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm get nic.nicconfig.3.LegacyBootProto | grep "PXE"
	if [ $? = 0 ];then
	    REBOOT[pend_count]=YES
	    echo -e "\n" && sshpass -p$pass ssh -o StrictHostKeyChecking=no $login@${ip_list[i]} racadm set bios.biosbootsettings.BootSeq HardDisk.List.1-1,NIC.Integrated.1-3-1
	    jobqueue ${ip_list[i]} BIOS.Setup.1-1
	    (( pend_count += 1 ))
	else
	    echo -e "\nA Change is either pending for NIC.Integrated.1-3-1 (or) Check the correct configuration has been passed in the previous step. Please Reboot to apply the Change..And then Rerun this step again"
            echo -e "${ip_list[i]}" >> $rerun_log_file
	fi


    fi

	
    echo -e "\n\n*********END BIOS CONFIGURATION*********\n"
    echo -e "reboot is : ${REBOOT[@]}"
    power_wait_reboot ${ip_list[i]}
done
echo "Out side for loop..."

#Cleanup logfiles older than 5 days.
find idrac_logs/ -type f -mtime +5 -exec rm -f '{}' \;
