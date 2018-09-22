#!/bin/bash

RFS=$1

# Housekeeping...
rm -f /tmp/ramdisk.img
rm -f /tmp/ramdisk.img.gz
mkdir -pv /mnt/initrd 
# Ramdisk Constants
RDSIZE=4000
BLKSIZE=1024
 
# Create an empty ramdisk image
dd if=/dev/zero of=/tmp/ramdisk.img bs=$BLKSIZE count=$RDSIZE

 
# Make it an ext2 mountable file system
/sbin/mke2fs -F -m 0 -b $BLKSIZE /tmp/ramdisk.img $RDSIZE

# Mount it so that we can populate
mount  -t ext2 -o loop /tmp/ramdisk.img /mnt/initrd
 
# Populate the filesystem (subdirectories)
mkdir /mnt/initrd/bin
mkdir /mnt/initrd/sys
mkdir /mnt/initrd/dev
mkdir /mnt/initrd/proc
 
# Grab busybox and create the symbolic links
pushd /mnt/initrd/bin
cp $RFS/bin/busybox .
ln -s busybox ash
ln -s busybox mount
ln -s busybox echo
ln -s busybox ls
ln -s busybox cat
ln -s busybox ps
ln -s busybox dmesg
ln -s busybox sysctl
popd
 
# Grab the necessary dev files
# prefer to use mknod -m 0600 console c 5 1
[ -e /dev/ram0 ] || mknod -m 660 /dev/ram0 b 1 1
cp -a /dev/console /mnt/initrd/dev
cp -a /dev/ram0 /mnt/initrd/dev
cp -a /dev/null /mnt/initrd/dev
cp -a /dev/tty1 /mnt/initrd/dev
cp -a /dev/tty2 /mnt/initrd/dev
 
# Equate sbin with bin
pushd /mnt/initrd
ln -s bin sbin
popd
 
# Create the init file
cat >> /mnt/initrd/linuxrc << EOF
#!/bin/ash
echo
echo "Simple initrd is active"
echo
mount -t proc /proc /proc
mount -t sysfs none /sys
/bin/ash --login
EOF
 
chmod +x /mnt/initrd/linuxrc
 
# Finish up...
umount /mnt/initrd
rmdir /mnt/initrd
gzip -9 /tmp/ramdisk.img



