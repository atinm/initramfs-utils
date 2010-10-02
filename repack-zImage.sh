#!/bin/sh
##############################################################################
# usage : ./repack.sh [kernel] [initramfs.cpio]                                                                                      #
# example : ./repack.sh  /data/android/initramfs-utils/zImage  /data/android/captivate-initramfs/ramdisk.cpio     #
# based on editor.sh from dkcldark @ xda
##############################################################################
# you should point where your cross-compiler is                                                                                 #
COMPILER="${HOME}/arm-none-eabi-4.3.4/bin/arm-none-eabi-"
##############################################################################

zImage=$1
new_ramdisk=$2
determiner=0
Image_here="./out/Image"

echo "##### My name is $0 #####"
echo "##### The kernel is $1 #####"
echo "##### The ramdisk is $2 #####"
if [ $1 = "" ]; then
	echo "##### You should point where the zImage file is #####"
	exit
elif [ $2 = "" ]; then
	echo "##### You should point where your new initramfs is #####"
	exit
fi

#=======================================================
# find start of gziped kernel object in the zImage file:
#=======================================================

pos=`grep -P -a -b --only-matching '\x1F\x8B\x08' $zImage | cut -f 1 -d :`
echo "##### 01.  Extracting kernel  from $zImage (start = $pos)"
mkdir out
dd if=$zImage bs=1 skip=$pos | gunzip > $Image_here

pos=`grep -P -a -b -m 1 --only-matching $'\x1F\x8B\x08' $Image_here | cut -f 1 -d :`
if [ ! $pos = "" ]; then
    echo "##### ERROR: Cannot handle a compressed cpio image in the kernel image"
    exit
fi

#===========================================================================
# find start and end of the "cpio" initramfs  inside the kernel object:
# ASCII cpio header starts with '070701'
# The end of the cpio archive is marked with an empty file named TRAILER!!!
#===========================================================================
start=`grep -a -b --only-matching '070701' $Image_here | head -1 | cut -f 1 -d :`
end=`grep -a -b --only-matching 'TRAILER!!!' $Image_here | head -1 | cut -f 1 -d :`
end=$((end + 10))
count=$((end - start))

if [ $count -lt $determiner ]; then
  echo "##### ERROR : Couldn't match start/end of the initramfs ."
  exit
fi

# Check the Image's size
filesize=`ls -l $Image_here | awk '{print $5}'`
echo "##### 02. The size of the Image is $filesize"

# Split the Image #1 ->  head.img
echo "##### 03. Making a head.img ( from 0 ~ $start )"
dd if=$Image_here bs=1 count=$start of=out/head.img

# Split the Image #2 ->  tail.img
echo "##### 04. Making a tail.img ( from $end ~ $filesize )"
dd if=$Image_here bs=1 skip=$end of=out/tail.img

# Check the new ramdisk's size
ramdsize=`ls -l $new_ramdisk | awk '{print $5}'`
echo "##### 05. The size of the new ramdisk is = $ramdsize"

echo "##### 06. Checking if ramdsize is bigger than the stock one"
if [ $ramdsize -gt $count ]; then
	cp $new_ramdisk out/ramdisk.backup
	cat out/ramdisk.backup | gzip -f -9 > out/ramdisk.cpio
	echo "##### Your initramfs needs to be gzipped!! ###"
else
	cp $new_ramdisk out/ramdisk.cpio
fi

# FrankenStein is being made #1
echo "##### 07. Merging head + ramdisk"
cat out/head.img out/ramdisk.cpio > out/franken.img

echo "##### 08. Checking the size of [head+ramdisk]"
franksize=`ls -l out/franken.img | awk '{print $5}'`

# FrankenStein is being made #2
echo "##### 09. Merging [head+ramdisk] + padding + tail"
if [ $franksize -lt $end ]; then
	tempnum=$((end - franksize))
	dd if=resources/blankfile bs=1 count=$tempnum of=out/padding
	cat out/padding out/tail.img > out/newtail.img
	cat out/franken.img out/newtail.img > out/new_Image
else
	echo "##### ERROR : Your initramfs is still BIGGER than the stock initramfs #####"
	exit
fi


#============================================
# rebuild zImage
#============================================
echo "##### Now we are rebuilding the zImage #####"

cp ../../out/new_Image $KSRC/arch/arm/boot/Image

#1. Image -> piggy.gz
echo "##### 10. Image ---> piggy.gz"
gzip -f -9 < $KSRC/arch/arm/boot/compressed/../Image > $KSRC/arch/arm/boot/compressed/piggy.gz

#2. piggy.gz -> piggy.o
echo "##### 11. piggy.gz ---> piggy.o"
$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.piggy.o.d  -nostdinc -isystem toolchain_resources/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -D__ASSEMBLY__ -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8  -msoft-float -gdwarf-2  -Wa,-march=all   -c -o arch/arm/boot/compressed/piggy.o arch/arm/boot/compressed/piggy.S

#3. head.o
echo "##### 12. Compiling head"
$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.head.o.d  -nostdinc -isystem toolchain_resources/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -D__ASSEMBLY__ -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8  -msoft-float -gdwarf-2  -Wa,-march=all   -c -o arch/arm/boot/compressed/head.o arch/arm/boot/compressed/head.S

#4. misc.o
echo "##### 13. Compiling misc"
$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.misc.o.d  -nostdinc -isystem toolchain_resources/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -Wall -Wundef -Wstrict-prototypes -Wno-trigraphs -fno-strict-aliasing -fno-common -Werror-implicit-function-declaration -Os -marm -fno-omit-frame-pointer -mapcs -mno-sched-prolog -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8 -msoft-float -Uarm -fno-stack-protector -I/modules/include -fno-omit-frame-pointer -fno-optimize-sibling-calls -g -Wdeclaration-after-statement -Wno-pointer-sign -fwrapv -fpic -fno-builtin -Dstatic=  -D"KBUILD_STR(s)=\#s" -D"KBUILD_BASENAME=KBUILD_STR(misc)"  -D"KBUILD_MODNAME=KBUILD_STR(misc)"  -c -o arch/arm/boot/compressed/misc.o arch/arm/boot/compressed/misc.c

#5. head.o + misc.o + piggy.o --> vmlinux
echo "##### 14. head.o + misc.o + piggy.o ---> vmlinux"
$COMPILER-ld -EL    --defsym zreladdr=0x30008000 --defsym params_phys=0x30000100 -p --no-undefined -X toolchain_resources/libgcc.a -T arch/arm/boot/compressed/vmlinux.lds arch/arm/boot/compressed/head.o arch/arm/boot/compressed/piggy.o arch/arm/boot/compressed/misc.o -o arch/arm/boot/compressed/vmlinux 

#6. vmlinux -> zImage
echo "##### 15. vmlinux ---> zImage"
$COMPILER-objcopy -O binary -R .note -R .note.gnu.build-id -R .comment -S  arch/arm/boot/compressed/vmlinux arch/arm/boot/zImage

# finishing
echo "##### 16. Getting finished!!"
mv arch/arm/boot/zImage ../../new_zImage
rm arch/arm/boot/compressed/vmlinux arch/arm/boot/compressed/piggy.o arch/arm/boot/compressed/misc.o arch/arm/boot/compressed/head.o arch/arm/boot/compressed/piggy.gz arch/arm/boot/Image
rm -r ../../out
