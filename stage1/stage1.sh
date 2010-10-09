#!/hush
unlzma -dc compressed-ramdisk.cpio.lzma | cpio -i
exec /init
