#!/bin/sh
AOSP="/data/android/aosp"
MKZIP='7z -mx9 -mmt=1 a "$OUTFILE" .'
if [ $1 = "" ]; then
    echo "##### You should point where the zImage file is in arg 1 #####"
    exit
fi

zImage=$1
# Generate update.zip for flashing
echo "Generating update.zip for flashing"
rm -fr update.zip
cp $zImage build/update/zImage
OUTFILE="$PWD/update.zip"
pushd build/update
eval "$MKZIP" >/dev/null 2>&1
popd

echo "Signing the update.zip file for flashing"
java -jar "$AOSP"/out/host/linux-x86/framework/signapk.jar \
	"$AOSP"/build/target/product/security/testkey.x509.pem \
	"$AOSP"/build/target/product/security/testkey.pk8 \
	"$OUTFILE" "$OUTFILE"-signed
mv "$OUTFILE"-signed "$OUTFILE"
