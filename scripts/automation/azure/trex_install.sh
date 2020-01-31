#!/bin/sh

# This script to be run in Centos 7.5 machine in azure to install Trex.

declare -r TREX_DIR="/opt/trex"
declare -r TREX_TAR_FILE="/opt/trex/latest"
declare -r TREX_AZURE_DIR=$TREX_DIR"/azure"
declare -r INSTALL_LOG=$TREX_AZURE_DIR"/install.log"
declare -r CFG_TEMPLATE_URL="https://raw.githubusercontent.com/vakalapa/trex-core/5d999d492635f9888e9c4829a32aca7e2ddc6d81/scripts/automation/config/trex_cfg_azure.cfg"
declare -r CFG_LOCATION="/etc/trex_cfg.yaml"

ITERATION="unknown"

if [[ ! -e $TREX_AZURE_DIR ]]; then
    mkdir -p $TREX_AZURE_DIR
    ITERATION="firstboot"
    if [[ ! -f "$FILE" ]]; then
        echo "Script first run. Created $TREX_AZURE_DIR" > $INSTALL_LOG
    else
        echo "Created $TREX_AZURE_DIR" >> $INSTALL_LOG
    fi
else
    ITERATION="secondary"
    if [[ ! -f "$FILE" ]]; then
        echo "Script first run. $TREX_AZURE_DIR already exists" > $INSTALL_LOG
    else
        echo "$TREX_AZURE_DIR already exists" >> $INSTALL_LOG
    fi
fi

echo "Boot iteration is $ITERATION" >> $INSTALL_LOG


# Check for number of Mellanox devices. If less than 2 then exit out of script.
devnum=$(lspci | grep Mell | wc -l)
if [ $devnum -gt 1 ]; then
    echo "This VM has $devnum Mellanox interfaces" >> $INSTALL_LOG
else
    echo "This VM has only $devnum Mellanox interfaces. Recommended number is 2. Exiting out" >> $INSTALL_LOG
    exit 1
fi


if [[ $ITERATION = "firstboot" ]] || [[ $ITERATION = "unknown" ]] ; then
    sudo yum -y groupinstall "Infiniband Support" -y
    sudo dracut --add-drivers "mlx4_en mlx4_ib mlx5_ib" -f
    sudo yum install -y gcc kernel-devel-`uname -r` numactl-devel.x86_64 librdmacm-devel libmnl-devel
fi


hugepages_output=$(cat /proc/meminfo | grep HugePages_Total)
if [[ $hugepages_output == *"4096"* ]]; then
    echo "Proc meminfo contains 4096 free huge pages."  >> $INSTALL_LOG
else
    #Adding hugepages to grub cmdline
    sudo sed 's/net.ifnames=0/net.ifnames=0 hugepages=4096/g' /etc/default/grub
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    echo "Updated grub file with hugepages. VM needs Reboot."  >> $INSTALL_LOG
    NEEDS_REBOOT="true"
fi

if [[ ! -e /mnt/huge ]]; then
    #add fstab partition
    sudo sed -i '$a nodev /mnt/huge hugetlbfs defaults 0 0' /etc/fstab
    echo "/mnt/huge is missing. Added entry. VM needs reboot" >> $INSTALL_LOG
    NEEDS_REBOOT="true"
else
     echo "/mnt/huge exists." >> $INSTALL_LOG 
fi

pwd >> $INSTALL_LOG
wget --no-cache https://trex-tgn.cisco.com/trex/release/latest
tar -xzvf latest -C $TREX_DIR
echo "Pulled TRex tarz and expanded it." >> $INSTALL_LOG

if [[ ! -f $CFG_LOCATION ]]; then
    sudo curl -o /etc/trex_cfg.cfg $CFG_TEMPLATE_URL
    echo "Pulled TREX_CFG file from URL." >> $INSTALL_LOG
fi

echo "End of Trex config. Please edit $CFG_LOCATION file to update local and remote IPs" >> $INSTALL_LOG

if [ ! -z $NEEDS_REBOOT ]; then
    echo "Rebooting now" >> $INSTALL_LOG
    sudo reboot now
fi