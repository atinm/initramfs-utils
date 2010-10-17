#!/bin/sh
##############################################################################
# usage : ./repack.sh [kernel] [initramfs_direcotry] [kernel source dir] "title of build"
# example : ./repack.sh  /data/android/initramfs-utils/zImage /data/android/captivate-initramfs \
#                  /data/android/linux-2.6.32 "title of build"
# based on editor.sh from dkcldark @ xda
##############################################################################
set -x
# you should point where your cross-compiler is
COMPILER_PATH="${HOME}/arm-none-eabi-4.3.4/bin"
COMPILER="$COMPILER_PATH/arm-none-eabi"
# you should point this where your AOSP root is
AOSP="/data/android/aosp"
##############################################################################

zImage=$1
new_ramdisk_dir=$2
KSRC=$3
TITLE=$4
determiner=0
Image_here="./out/Image"
MKZIP='7z -mx9 -mmt=1 a "$OUTFILE" .'
TARGET_DEVICE_NAME=SGH-I897
DATE=`date`

write_script() {
    test -n "$TARGET_DEVICE_NAME" && \
	echo "assert(getprop(\"ro.product.device\") == \"$TARGET_DEVICE_NAME\" || getprop(\"ro.build.product\") == \"$TARGET_DEVICE_NAME\");"
    declare -f pre_hook >/dev/null 2>&1 && \
	pre_hook
    title="ui_print(\"** $TITLE \");"
    echo $title
    echo 'ui_print("** atinm @ xda-developers");'
    date="ui_print(\"** Build date: $DATE \");"
    echo $date
    echo 'ui_print("-");'
    echo 'ui_print("-");'
    echo 'ui_print("Unpacking files...");'
    declare -f unpack_hook >/dev/null 2>&1 && \
	unpack_hook
    echo 'package_extract_dir("tmp", "/tmp");'
    declare -f apply_hook >/dev/null 2>&1 && \
	apply_hook
    echo 'ui_print("-");'
    echo 'ui_print("-");'
    echo 'ui_print("Flashing kernel...");'
    echo 'write_raw_image("/tmp/zImage", "/dev/block/bml7");'
    declare -f post_hook >/dev/null 2>&1 && \
	post_hook
    echo 'ui_print("** Done!");'
    return 0
}

prepare_update() {
    rm -r build/update/tmp
    mkdir -p build/update/tmp
    cp -a out/zImage build/update/tmp
    write_script >build/update/META-INF/com/google/android/updater-script
    declare -f prepare_hook >/dev/null 2>&1 && \
	prepare_hook
    return 0
}

if [ -z $1 ]; then
    echo "##### You should point where the zImage file is in arg 1 #####"
    exit
elif [ -z $2 ]; then
    echo "##### You should point where your new initramfs is in arg 2 #####"
    exit
elif [ -z $3 ]; then
    echo "##### You should point where your kernel source is in arg 3 #####"
    exit
elif [ -z "$4" ]; then
    echo "##### You should specify the title for this update in arg 4 #####"
    exit
fi
echo "##### My name is $0 #####"
echo "##### The kernel is $1 #####"
echo "##### The ramdisk is $2 #####"
echo "##### The kernel source is $3 #####"
echo "##### The title for this update is $4 #####"

#=======================================================
# find start of gziped kernel object in the zImage file:
#=======================================================
rm -rf out
mkdir out

pos=`grep -P -a -b -m 1 --only-matching '\x1F\x8B\x08' $zImage | cut -f 1 -d :`
echo "##### 01.  Extracting boot header from $zImage (start=0, count=$pos)"
dd if=$zImage bs=1 count=$pos of=out/boot.img

echo "##### 03.  Extracting kernel  from $zImage (start = $pos)"
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
start=`grep -a -b -m 1 --only-matching '070701' $Image_here | head -1 | cut -f 1 -d :`
end=`grep -a -b -m 1 --only-matching 'TRAILER!!!' $Image_here | head -1 | cut -f 1 -d :`
end=$((end + 10))
count=$((end - start))

if [ $count -lt $determiner ]; then
    echo "##### ERROR : Couldn't match start/end of the initramfs ."
    exit
fi

# Check the Image's size
filesize=`ls -l $Image_here | awk '{print $5}'`
echo "##### 03. The size of the Image is $filesize"

# Split the Image #1 ->  head.img
echo "##### 04. Making a head.img ( from 0 ~ $start )"
dd if=$Image_here bs=1 count=$start of=out/head.img

# Split the Image #2 ->  tail.img
echo "##### 05. Making a tail.img ( from $end ~ $filesize )"
dd if=$Image_here bs=1 skip=$end of=out/tail.img

# Create the cpio archive
OUT=`pwd`/out
pushd $new_ramdisk_dir
find ./ | grep -v ".gitignore" | cpio -o -H newc > $OUT/new_ramdisk.cpio
popd

# Check the new ramdispk's size
ramdsize=`ls -l out/new_ramdisk.cpio | awk '{print $5}'`
echo "##### 06. The size of the new ramdisk is = $ramdsize"

echo "##### 07. Checking if ramdsize is bigger than the stock one"
if [ $ramdsize -gt $count ]; then
    echo "##### Your initramfs needs to be gzipped!! ###"
    cp out/new_ramdisk.cpio out/ramdisk.backup
    cat out/ramdisk.backup | gzip -f -9 > out/ramdisk.cpio
else
    cp out/new_ramdisk.cpio out/ramdisk.cpio
fi

# FrankenStein is being made #1
echo "##### 08. Merging head + ramdisk"
cat out/head.img out/ramdisk.cpio > out/franken.img

echo "##### 09. Checking the size of [head+ramdisk]"
franksize=`ls -l out/franken.img | awk '{print $5}'`

# FrankenStein is being made #2
echo "##### 10. Merging [head+ramdisk] + padding + tail"
if [ $franksize -le $end ]; then
    tempnum=$((end - franksize))
    dd if=resources/blankfile bs=1 count=$tempnum of=out/padding
    cat out/padding out/tail.img > out/newtail.img
    cat out/franken.img out/newtail.img > out/new_Image
else
    echo "##### ERROR : Your initramfs is still BIGGER than the stock initramfs $franksize > $end #####"
    exit
fi

#============================================
# rebuild zImage
#============================================
echo "##### Now we are rebuilding the zImage #####"

cp out/new_Image $KSRC/arch/arm/boot/Image
pushd $KSRC

#1. Image -> piggy.gz
echo "##### 11. Image ---> piggy.gz"
gzip -f -9 < arch/arm/boot/compressed/../Image > arch/arm/boot/compressed/piggy.gz

#2. piggy.gz -> piggy.o
echo "##### 12. piggy.gz ---> piggy.o"
$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.piggy.o.d  -nostdinc -isystem $COMPILER_PATH/../lib/gcc/arm-none-eabi/4.3.4/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -D__ASSEMBLY__ -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8  -msoft-float -gdwarf-2  -Wa,-march=all   -c -o arch/arm/boot/compressed/piggy.o arch/arm/boot/compressed/piggy.S

#3. head.o
echo "##### 13. Compiling head"
$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.head.o.d  -nostdinc -isystem $COMPILER_PATH/../lib/gcc/arm-none-eabi/4.3.4/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -D__ASSEMBLY__ -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8  -msoft-float -gdwarf-2  -Wa,-march=all   -c -o arch/arm/boot/compressed/head.o arch/arm/boot/compressed/head.S

#4. misc.o
echo "##### 14. Compiling misc"
$COMPILER-gcc -Wp,-MD,arch/arm/boot/compressed/.misc.o.d  -nostdinc -isystem $COMPILER_PATH/../lib/gcc/arm-none-eabi/4.3.4/include -Dlinux -Iinclude  -Iarch/arm/include -include include/linux/autoconf.h -D__KERNEL__ -mlittle-endian -Iarch/arm/mach-s5pc110/include -Iarch/arm/plat-s5pc11x/include -Iarch/arm/plat-s3c/include -Wall -Wundef -Wstrict-prototypes -Wno-trigraphs -fno-strict-aliasing -fno-common -Werror-implicit-function-declaration -Os -marm -fno-omit-frame-pointer -mapcs -mno-sched-prolog -mabi=aapcs-linux -mno-thumb-interwork -D__LINUX_ARM_ARCH__=7 -mcpu=cortex-a8 -msoft-float -Uarm -fno-stack-protector -I/modules/include -fno-omit-frame-pointer -fno-optimize-sibling-calls -g -Wdeclaration-after-statement -Wno-pointer-sign -fwrapv -fpic -fno-builtin -Dstatic=  -D"KBUILD_STR(s)=\#s" -D"KBUILD_BASENAME=KBUILD_STR(misc)"  -D"KBUILD_MODNAME=KBUILD_STR(misc)"  -c -o arch/arm/boot/compressed/misc.o arch/arm/boot/compressed/misc.c

#5. head.o + misc.o + piggy.o --> vmlinux
echo "##### 15. head.o + misc.o + piggy.o ---> vmlinux"
$COMPILER-ld -EL    --defsym zreladdr=0x30008000 --defsym params_phys=0x30000100 -p --no-undefined -X $COMPILER_PATH/../lib/gcc/arm-none-eabi/4.3.4/libgcc.a -T arch/arm/boot/compressed/vmlinux.lds arch/arm/boot/compressed/head.o arch/arm/boot/compressed/piggy.o arch/arm/boot/compressed/misc.o -o arch/arm/boot/compressed/vmlinux 

#6. vmlinux -> zImage
echo "##### 16. vmlinux ---> zImage"
$COMPILER-objcopy -O binary -R .note -R .note.gnu.build-id -R .comment -S  arch/arm/boot/compressed/vmlinux arch/arm/boot/zImage

popd
mv $KSRC/arch/arm/boot/zImage out/zImage

echo "##### 17. Creating zImage-inject.tar for Odin"
tar c -C out zImage > zImage-inject.tar

# Generate update.zip for flashing
echo "18. Generating update.zip for flashing"
rm -fr update.zip*
prepare_update
OUTFILE="$PWD/update.zip"
pushd build/update

FILES=
SYMLINKS=

for file in $(find .)
do

    if [ -d $file ]
    then
	continue
    fi

    META_INF=$(echo $file | grep META-INF)
    if [ ! -z $META_INF ]
    then
	continue;
    fi

    if [ -h $file ]
    then
	SYMLINKS=$SYMLINKS' '$file
    elif [ -f $file ]
    then
	FILES=$FILES' '$file
    fi
done

echo "Zipping $OUTFILE..."
zip -ry $OUTFILE-unsigned . -x $SYMLINKS '*\[*' '*\[\[*'
echo "Signing $OUTFILE for flashing"
java -jar $AOSP/out/host/linux-x86/framework/signapk.jar -w $AOSP/build/target/product/security/testkey.x509.pem $AOSP/build/target/product/security/testkey.pk8 $OUTFILE-unsigned $OUTFILE
popd

echo "##### 20. Done!"

