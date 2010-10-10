#!/bin/sh
AOSP="/data/android/aosp"
MKZIP='7z -mx9 -mmt=1 a "$OUTFILE" .'
if [ $1 = "" ]; then
    echo "##### You should point where the zImage file is in arg 1 #####"
    exit
fi

zImage=$1
echo "Generating update.zip for flashing..."
rm -fr update.zip
cp $zImage build/update/zImage
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
