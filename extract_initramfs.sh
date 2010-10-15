#!/bin/sh
zImage=$1
#========================================================
# find start of gziped kernel object in the zImage file:
#========================================================
pos=`grep -P -a -b -m 1 --only-matching $'\x1F\x8B\x08' $zImage | cut -f 1 -d :`
echo "-I- Extracting kernel image from $zImage (start = $pos)"

#========================================================================
# the cpio archive might be compressed too, so two gunzips could be needed:
#========================================================================
dd if=$zImage bs=1 skip=$pos | gunzip > /tmp/kernel.img
pos=`grep -P -a -b -m 1 --only-matching $'\x1F\x8B\x08' /tmp/kernel.img | cut -f 1 -d :`
#===========================================================================
# find start and end of the "cpio" initramfs image inside the kernel object:
# ASCII cpio header starts with '070701'
# The end of the cpio archive is marked with an empty file named TRAILER!!!
#===========================================================================
if [ ! $pos = "" ]; then
    echo "-I- Extracting compressed cpio image from kernel image (start = $pos)"
    dd if=/tmp/kernel.img bs=1 skip=$pos | gunzip > /tmp/cpio.img
    start=`grep -a -b -m 1 --only-matching '070701' /tmp/cpio.img | head -1 | cut -f 1 -d :`
    end=`grep -a -b --only-matching 'TRAILER!!!' /tmp/cpio.img | tail -1 | cut -f 1 -d :`
    inputfile=/tmp/cpio.img
else
    echo "-I- Already uncompressed cpio.img, not decompressing"
    start=`grep -a -b -m 1 --only-matching '070701' /tmp/kernel.img | head -1 | cut -f 1 -d :`
    end=`grep -a -b --only-matching 'TRAILER!!!' /tmp/kernel.img | tail -1 | cut -f 1 -d :`
    inputfile=/tmp/kernel.img
fi

end=$((end + 10))
count=$((end - start))
if (($count < 0)); then
    echo "-E- Couldn't match start/end of the initramfs image."
    exit
fi
echo "-I- Extracting initramfs image from $inputfile (start = $start, end = $end)"
dd if=$inputfile bs=1 skip=$start count=$count > initramfs.cpio
