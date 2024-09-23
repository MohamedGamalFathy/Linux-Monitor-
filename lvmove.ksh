#!/usr/bin/ksh
## Lvmove script
## Belal Koura SSNC
## Units in bytes
## VERSION 5
#==============================================================================================================
# Pre-checks
if [[ -z "$1" || $EUID -ne 0 ]]; then
   echo "[INFO] Usage $0 <lv_name|pattern>"
   exit 1
fi

#==============================================================================================================
# VARs
if [[ "$1" =~ ^/dev/([^/]+)/([^/]+)$ ]]; then
 lv_name=${1##*/}
else
 lv_name=$(lvs --noheadings -o lv_name|awk -v lv="$1" '!seen[$1]++ && $1 ~ lv{print $1}')
fi

lv_vg=$(lvs --noheadings|awk -v lv="$lv_name" '!seen[$1]++ && $1==lv{print $2}')
lv_size=$(lvs --noheadings --nosuffix --units B|grep $lv_name|awk 'NR==1{print $4}') ## Size in Bytes
max_free=$(vgs --noheadings -o vg_free --units B --sort vg_free --nosuffix|awk 'END{print $1}') ## Size in Bytes
max_vg=$(vgs --noheadings -o vg_name --sort vg_free|awk 'END{print $1}')
dev_size=$(df /dev|awk 'NR==2{print $5}'|sed 's/%//')
completion_file="/usr/share/bash-completion/completions/lvmove"
install_file="/sbin/lvmove"

#==============================================================================================================
if [[ ! -f "$completion_file" && ! -f "$install_file" ]]; then
echo "[INFO] Creating Bash completion file for lvmove"

cat << EOF > $completion_file
# bash completion for lvm                                  -*- shell-script -*-
_lvmove()
{

    local cur_word="\${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=(\$(compgen -W "\$(lvscan 2>/dev/null|sed -n -e "s|^.*'\(.*\)'.*$|\1|p")" -- "\$cur_word"))
} &&
complete -F _lvmove lvmove
EOF

chmod 644 "$completion_file"
cp "$0" "$install_file" &&\
chmod +x "$install_file" &&\
echo "[INFO] $0 installed as lvmove, please rerun it as lvmove <lv_name|pattern>"
exit 30
fi

#==============================================================================================================
## Max_VG Not the same VG and Max_free not zero
## make sure devtmpfs is not full
if [[ "$dev_size" -lt 100 ]]; then
   if (( `echo "$lv_size > $max_free || $max_free == 0" | bc -l` )) || [ "$lv_vg" == "$max_vg" ] ; then

   echo "[ERROR] Volume group $max_vg has insufficient free space ${max_free}B: ${lv_size}B required."
   exit 2

   fi

else
  echo "[ERROR] /dev has no free space"
  exit 100

fi
#==============================================================================================================
## copying data from old VG to new VG
mountpoint -q  /${lv_name#lv} &&\
umount -f /dev/${lv_vg}/${lv_name} 2> /dev/null

lvcreate -L ${lv_size}B --name $lv_name $max_vg &&\
echo "[INFO] Please wait while copying $lv_name data to $max_vg ..." &&\
dd if=/dev/${lv_vg}/${lv_name} of=/dev/${max_vg}/${lv_name}  bs=1024K conv=noerror,sync status=progress &&\
lvremove /dev/${lv_vg}/${lv_name}

#==============================================================================================================
if lvs /dev/${max_vg}/${lv_name} >/dev/null 2>&1 ; then
   if grep -q "$lv_name" /etc/fstab; then
   cpdate /etc/fstab
   sed -i "s/$lv_vg/$max_vg/g" /etc/fstab
   systemctl daemon-reload &&\
   echo "[INFO] fstab file updated. "
   mount /dev/${max_vg}/${lv_name} 2> /dev/null
   fi
fi
