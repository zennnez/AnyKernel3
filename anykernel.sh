### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Knockout Kernel by zen | Telegram: t.me/zennnez
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
do.check_boot_version=1
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
keycheck.timeout=10
'; } # end properties


### AnyKernel install
## boot shell variables
block=boot;
is_slot_device=auto;
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

# GKI check
kernel_version=$(cat /proc/version | awk -F '-' '{print $1}' | awk '{print $3}')
case $kernel_version in
    6.1*) ksu_supported=true ;;
    6.6*) ksu_supported=true ;;
    *) ksu_supported=false ;;
esac

ui_print " " "  -> Device Supported: $ksu_supported"
$ksu_supported || abort "  -> Non-GKI device, abort."

# Display Kernel Features from features.json
feat_file=""
if [ -f "$AKHOME/features.json" ]; then
    feat_file="$AKHOME/features.json"
elif [ -f "features.json" ]; then
    feat_file="features.json"
fi

if [ -n "$feat_file" ]; then
    ui_print " "
    ui_print "  ======================================================"
    ui_print "              Knockout Kernel Features & Config         "
    ui_print "  ======================================================"
    model=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$feat_file" 2>/dev/null | head -n1 | sed -e 's/.*"model"[[:space:]]*:[[:space:]]*"//' -e 's/"//g')
    soc=$(grep -o '"soc"[[:space:]]*:[[:space:]]*"[^"]*"' "$feat_file" 2>/dev/null | head -n1 | sed -e 's/.*"soc"[[:space:]]*:[[:space:]]*"//' -e 's/"//g')
    os_ver=$(grep -o '"os_version"[[:space:]]*:[[:space:]]*"[^"]*"' "$feat_file" 2>/dev/null | head -n1 | sed -e 's/.*"os_version"[[:space:]]*:[[:space:]]*"//' -e 's/"//g')
    kver=$(grep -o '"kernel_version"[[:space:]]*:[[:space:]]*"[^"]*"' "$feat_file" 2>/dev/null | head -n1 | sed -e 's/.*"kernel_version"[[:space:]]*:[[:space:]]*"//' -e 's/"//g')
    root_sol=$(grep -o '"root_solution"[[:space:]]*:[[:space:]]*"[^"]*"' "$feat_file" 2>/dev/null | head -n1 | sed -e 's/.*"root_solution"[[:space:]]*:[[:space:]]*"//' -e 's/"//g')

    if [ -n "$model" ] && [ -n "$soc" ]; then
        ui_print "  -> Device Model  : $model ($soc)"
    elif [ -n "$model" ]; then
        ui_print "  -> Device Model  : $model"
    fi
    if [ -n "$os_ver" ] && [ -n "$kver" ]; then
        ui_print "  -> Android / OS  : $os_ver (Kernel $kver)"
    elif [ -n "$os_ver" ]; then
        ui_print "  -> Android / OS  : $os_ver"
    fi
    [ -n "$root_sol" ] && ui_print "  -> Root Solution : $root_sol"
    ui_print "  ------------------------------------------------------"
    ui_print "  -> Active Kernel Features:"

    awk '
        /"name"[[:space:]]*:/ {
            gsub(/.*"name"[[:space:]]*:[[:space:]]*"/, "");
            gsub(/".*/, "");
            name = $0;
        }
        /"desc"[[:space:]]*:/ {
            gsub(/.*"desc"[[:space:]]*:[[:space:]]*"/, "");
            gsub(/".*/, "");
            desc = $0;
            if (name != "") {
                print "     • " name;
                print "       - " desc;
                name = "";
                desc = "";
            }
        }
    ' "$feat_file" | while IFS= read -r fline; do
        ui_print "$fline"
    done
    ui_print "  ======================================================"
    ui_print " "
fi

# boot install
split_boot

# Remove any false-positive kernel_dtb split by magiskboot on GKI kernel images
rm -f "$SPLITIMG/kernel_dtb"

# Dual Boot Detection & Patching for erhai (OnePlus Pad 2 Pro / Pad 3)
is_dualboot=0

# 1. Check if current boot slot kernel already contains Mu UEFI firmware header (_FVH)
if [ -f "$SPLITIMG/kernel" ]; then
    if grep -a -q "_FVH" "$SPLITIMG/kernel" 2>/dev/null || grep -q "_FVH" "$SPLITIMG/kernel" 2>/dev/null; then
        is_dualboot=1
    fi
fi

# 2. Check if ESP partition exists and contains the dual-boot EFI loaders
if [ "$is_dualboot" = "0" ]; then
    for byname in /dev/block/bootdevice/by-name /dev/block/by-name /dev/block/platform/soc/*/by-name; do
        if [ -d "$byname" ] && [ -e "$byname/esp" ]; then
            espmnt="/tmp/ak3_esp_chk"
            mkdir -p "$espmnt"
            if mount -t vfat -o ro "$byname/esp" "$espmnt" 2>/dev/null; then
                if [ -f "$espmnt/EFI/BOOT/bootaa64.efi" ] && [ -f "$espmnt/EFI/android/AndroidBootPkg.efi" ]; then
                    is_dualboot=1
                fi
                umount "$espmnt" 2>/dev/null
            fi
            rmdir "$espmnt" 2>/dev/null
            [ "$is_dualboot" = "1" ] && break
        fi
    done
fi

# 3. Check for dedicated linux rootfs partition alongside esp
if [ "$is_dualboot" = "0" ]; then
    for byname in /dev/block/bootdevice/by-name /dev/block/by-name /dev/block/platform/soc/*/by-name; do
        if [ -d "$byname" ] && [ -e "$byname/linux" ] && [ -e "$byname/esp" ]; then
            is_dualboot=1
            break
        fi
    done
fi

if [ "$is_dualboot" = "1" ]; then
    ui_print " "
    ui_print "  ======================================================"
    ui_print "                  Dual Boot detected!                   "
    ui_print "  ======================================================"
    ui_print "  -> Active Slot   : boot${SLOT:-}"
    ui_print "  -> Patching kernel with UEFI dual-boot payload..."

    patcher="$BIN/DualBootKernelPatcher"
    uefi_fd="$BIN/ERHAI_UEFI.fd"
    cfg="$BIN/DualBoot.Sm8750.cfg"
    shellcode="$BIN/ShellCode.Erhai.bin"

    [ -x "$patcher" ] || patcher="$AKHOME/tools/DualBootKernelPatcher"
    [ -f "$uefi_fd" ] || uefi_fd="$AKHOME/tools/ERHAI_UEFI.fd"
    [ -f "$cfg" ] || cfg="$AKHOME/tools/DualBoot.Sm8750.cfg"
    [ -f "$shellcode" ] || shellcode="$AKHOME/tools/ShellCode.Erhai.bin"

    chmod 755 "$patcher" 2>/dev/null

    target_img=""
    if [ -f "$AKHOME/Image" ]; then
        target_img="$AKHOME/Image"
    elif [ -f "$SPLITIMG/kernel" ]; then
        target_img="$SPLITIMG/kernel"
    fi

    # CRITICAL: Strip bogus kernel_dtb so it is never appended to the kernel
    rm -f "$SPLITIMG/kernel_dtb"

    if [ -x "$patcher" ] && [ -f "$uefi_fd" ] && [ -f "$cfg" ] && [ -f "$shellcode" ] && [ -n "$target_img" ]; then
        patched_kernel="$AKHOME/Image-patched"
        rm -f "$patched_kernel"

        if "$patcher" "$target_img" "$uefi_fd" "$patched_kernel" "$cfg" "$shellcode" >/dev/null 2>&1 && [ -s "$patched_kernel" ]; then
            mv -f "$patched_kernel" "$AKHOME/Image"
            cp -f "$AKHOME/Image" "$SPLITIMG/kernel"
            rm -f "$SPLITIMG/kernel_dtb"
            ui_print "  -> Dual-boot kernel patched successfully!"
        else
            ui_print "  ! Warning: DualBootKernelPatcher failed, falling back to regular flash..."
        fi
    else
        ui_print "  ! Warning: Dual-boot payload files missing in tools/, falling back to regular flash..."
    fi
    ui_print "  ======================================================"
    ui_print " "
else
    ui_print " "
    ui_print "  -> Dual Boot not detected. Proceeding with regular flash..."
    rm -f "$SPLITIMG/kernel_dtb"
fi

if [ -f "$SPLITIMG/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi

# On-device vendor_boot ramdisk patching for vendor modules
if [ -d "$AKHOME/modules/display" ] && ls "$AKHOME/modules/display/"*.ko >/dev/null 2>&1; then
    ui_print " "
    ui_print "  ======================================================"
    ui_print "          Patching vendor_boot Ramdisk on Device        "
    ui_print "  ======================================================"
    for vb_dev in "/dev/block/bootdevice/by-name/vendor_boot$SLOT" "/dev/block/by-name/vendor_boot$SLOT" "/dev/block/bootdevice/by-name/vendor_boot" "/dev/block/by-name/vendor_boot"; do
        if [ -e "$vb_dev" ]; then
            ui_print "  -> Found vendor_boot partition: $vb_dev"
            reset_ak
            block="$vb_dev"
            split_boot
            if [ -d "$SPLITIMG/vendor_ramdisk" ] || [ -f "$SPLITIMG/ramdisk.cpio" ]; then
                unpack_ramdisk
                if [ -d "$AKHOME/modules/display" ]; then
                    for ko in "$AKHOME/modules/display/"*.ko; do
                        [ -f "$ko" ] || continue
                        koname=$(basename "$ko")
                        found_target=$(find "$VENDORRD" -name "$koname" 2>/dev/null | head -n1)
                        if [ -n "$found_target" ] && [ -f "$found_target" ]; then
                            ui_print "     • Replacing: $koname in vendor_boot ramdisk"
                            cp -f "$ko" "$found_target"
                        else
                            ui_print "     • Injecting: $koname into vendor_boot ramdisk"
                            mkdir -p "$VENDORRD/ramdisk/lib/modules"
                            cp -f "$ko" "$VENDORRD/ramdisk/lib/modules/"
                        fi
                    done
                fi
                write_boot
                ui_print "  -> vendor_boot successfully patched and flashed!"
            fi
            break
        fi
    done
    ui_print "  ======================================================"
    ui_print " "
fi

# =====================================================================
# Flash EROFS / Dynamic Partition vendor_*.img (vendor_dlkm.img, vendor.img, etc.)
# =====================================================================
flash_erofs_vendor() {
    local img="$1"
    [ -f "$img" ] || return 0
    local partname
    partname=$(basename "$img" .img)
    # vendor_boot is handled separately via ramdisk unpack/repack
    [ "$partname" = "vendor_boot" ] && return 0

    ui_print " "
    ui_print "  ======================================================"
    ui_print "         Flashing EROFS Partition: $partname            "
    ui_print "  ======================================================"
    local imgsz_mb
    imgsz_mb=$(wc -c < "$img" | awk '{print int($1/1024/1024)}')
    ui_print "  -> Image: $(basename "$img") (${imgsz_mb}MB)"

    # 1. Locate block device (handle mapper, by-name, bootdevice)
    local imgblock=""
    for path in /dev/block/mapper /dev/block/bootdevice/by-name /dev/block/by-name; do
        for file in "$partname$SLOT" "$partname"; do
            if [ -e "$path/$file" ]; then
                imgblock="$path/$file"
                break 2
            fi
        done
    done

    # If logical partition not yet mapped in /dev/block/mapper, map it via lptools
    if [ -z "$imgblock" ] && [ -f "$AKHOME/tools/lptools_static" ]; then
        chmod 755 "$AKHOME/tools/lptools_static" 2>/dev/null
        "$AKHOME/tools/lptools_static" map "$partname$SLOT" 2>/dev/null || "$AKHOME/tools/lptools_static" map "$partname" 2>/dev/null
        for file in "$partname$SLOT" "$partname"; do
            if [ -e "/dev/block/mapper/$file" ]; then
                imgblock="/dev/block/mapper/$file"
                break
            fi
        done
    fi

    if [ -z "$imgblock" ]; then
        ui_print "  ! Target block device for $partname could not be found!"
        ui_print "  ======================================================"
        return 1
    fi

    ui_print "  -> Found partition block: $imgblock"

    # 2. Unmount if currently mounted anywhere
    for mnt in "/$partname" "/mnt/$partname" "/system/$partname" "/postinstall/$partname"; do
        if grep -q " $mnt " /proc/mounts 2>/dev/null; then
            ui_print "  -> Unmounting $mnt before flashing..."
            umount "$mnt" 2>/dev/null
        fi
    done

    # 3. AVB / dm-verity hashtree patching via httools
    if [ -f "$AKHOME/tools/httools_static" ]; then
        chmod 755 "$AKHOME/tools/httools_static" 2>/dev/null
        local avb
        avb=$("$AKHOME/tools/httools_static" avb "$partname" 2>/dev/null)
        if [ -n "$avb" ]; then
            local flags
            flags=$("$AKHOME/tools/httools_static" disable-flags 2>/dev/null)
            if [ "$flags" = "enabled" ]; then
                ui_print "  -> dm-verity active; updating $avb hashtree for $partname..."
                local avbblock=""
                for avbpath in /dev/block/mapper /dev/block/bootdevice/by-name /dev/block/by-name; do
                    for file in "$avb$SLOT" "$avb"; do
                        if [ -e "$avbpath/$file" ]; then
                            avbblock="$avbpath/$file"
                            break 2
                        fi
                    done
                done
                if [ -n "$avbblock" ]; then
                    "$AKHOME/tools/httools_static" patch "$partname" "$img" "$avbblock" 2>/dev/null
                fi
            fi
        fi
    fi

    # 4. Safe raw block flashing (preserves dynamic partition table in super)
    blockdev --setrw "$imgblock" 2>/dev/null
    ui_print "  -> Writing EROFS image to $imgblock..."
    if ! cat "$img" > "$imgblock" 2>/dev/null; then
        dd if="$img" of="$imgblock" bs=4096 2>/dev/null
    fi
    blockdev --setro "$imgblock" 2>/dev/null
    ui_print "  -> $partname flashed successfully!"
    ui_print "  ======================================================"
    ui_print " "
    touch "$AKHOME/${partname}_erofs_flashed"
}

# 1. Flash any bundled EROFS vendor_*.img (vendor_dlkm.img, vendor.img, etc.)
for vimg in "$AKHOME"/vendor_*.img; do
    [ -f "$vimg" ] || continue
    flash_erofs_vendor "$vimg"
done

# 2. On-device fallback replacement for display modules if no vendor_dlkm.img was bundled
if [ ! -f "$AKHOME/vendor_dlkm_erofs_flashed" ] && [ -d "$AKHOME/modules/display" ]; then
    ui_print " "
    ui_print "  ======================================================"
    ui_print "         Patching vendor_dlkm Modules on Device         "
    ui_print "  ======================================================"
    vdlkm_mnt=""
    mounted_by_us=0

    # Check if vendor_dlkm is already mounted in recovery
    for mnt in /vendor_dlkm /mnt/vendor_dlkm /system/vendor_dlkm /postinstall/vendor_dlkm; do
        if [ -d "$mnt" ] && grep -q " $mnt " /proc/mounts 2>/dev/null; then
            vdlkm_mnt="$mnt"
            ui_print "  -> Detected mounted partition: $vdlkm_mnt"
            mount -o rw,remount "$vdlkm_mnt" 2>/dev/null
            break
        fi
    done

    # If not mounted, find block device and try mounting
    if [ -z "$vdlkm_mnt" ]; then
        vdlkm_dev=""
        for dev in "/dev/block/mapper/vendor_dlkm$SLOT" "/dev/block/mapper/vendor_dlkm" \
                   "/dev/block/bootdevice/by-name/vendor_dlkm$SLOT" "/dev/block/bootdevice/by-name/vendor_dlkm" \
                   "/dev/block/by-name/vendor_dlkm$SLOT" "/dev/block/by-name/vendor_dlkm"; do
            if [ -e "$dev" ]; then
                vdlkm_dev="$dev"
                break
            fi
        done

        if [ -z "$vdlkm_dev" ] && [ -f "$AKHOME/tools/lptools_static" ]; then
            chmod 755 "$AKHOME/tools/lptools_static" 2>/dev/null
            "$AKHOME/tools/lptools_static" map "vendor_dlkm$SLOT" 2>/dev/null || "$AKHOME/tools/lptools_static" map "vendor_dlkm" 2>/dev/null
            for dev in "/dev/block/mapper/vendor_dlkm$SLOT" "/dev/block/mapper/vendor_dlkm"; do
                if [ -e "$dev" ]; then
                    vdlkm_dev="$dev"
                    break
                fi
            done
        fi

        if [ -n "$vdlkm_dev" ]; then
            ui_print "  -> Found vendor_dlkm block device: $vdlkm_dev"
            blockdev --setrw "$vdlkm_dev" 2>/dev/null
            custom_mnt="/tmp/vendor_dlkm_mnt"
            mkdir -p "$custom_mnt"
            if mount -o rw "$vdlkm_dev" "$custom_mnt" 2>/dev/null || mount "$vdlkm_dev" "$custom_mnt" 2>/dev/null; then
                vdlkm_mnt="$custom_mnt"
                mounted_by_us=1
                ui_print "  -> Successfully mounted $vdlkm_dev at $vdlkm_mnt"
            fi
        fi
    fi

    # Replace display modules
    if [ -n "$vdlkm_mnt" ]; then
        for ko in "$AKHOME/modules/display/"*.ko; do
            [ -f "$ko" ] || continue
            koname=$(basename "$ko")
            found_target=$(find "$vdlkm_mnt" -name "$koname" 2>/dev/null | head -n1)
            if [ -z "$found_target" ]; then
                if [ -d "$vdlkm_mnt/lib/modules" ]; then
                    found_target="$vdlkm_mnt/lib/modules/$koname"
                fi
            fi

            if [ -n "$found_target" ]; then
                ui_print "     • Replacing: $koname in $found_target"
                mount -o rw,remount "$vdlkm_mnt" 2>/dev/null
                cp -f "$ko" "$found_target" 2>/dev/null
                if [ $? -eq 0 ]; then
                    chmod 644 "$found_target" 2>/dev/null
                    chown 0:0 "$found_target" 2>/dev/null
                    chcon "u:object_r:vendor_file:s0" "$found_target" 2>/dev/null || \
                    chcon "u:object_r:vendor_dlkm_file:s0" "$found_target" 2>/dev/null
                    ui_print "       -> Module replaced successfully!"
                else
                    ui_print "       -> Write failed: vendor_dlkm is read-only EROFS (bundle vendor_dlkm.img to flash)"
                fi
            else
                ui_print "     • Target $koname not found in $vdlkm_mnt"
            fi
        done

        if [ "$mounted_by_us" = "1" ]; then
            sync
            umount "$vdlkm_mnt" 2>/dev/null
            rmdir "$vdlkm_mnt" 2>/dev/null
        fi
    else
        ui_print "  -> Could not mount vendor_dlkm partition in recovery"
    fi

    # Also check /vendor if mounted
    if grep -q " /vendor " /proc/mounts 2>/dev/null; then
        for ko in "$AKHOME/modules/display/"*.ko; do
            [ -f "$ko" ] || continue
            koname=$(basename "$ko")
            found_vendor=$(find /vendor -name "$koname" 2>/dev/null | head -n1)
            if [ -n "$found_vendor" ]; then
                mount -o rw,remount /vendor 2>/dev/null
                if cp -f "$ko" "$found_vendor" 2>/dev/null; then
                    chmod 644 "$found_vendor" 2>/dev/null
                    ui_print "     • Also replaced $koname in /vendor ($found_vendor)"
                fi
            fi
        done
    fi
    ui_print "  ======================================================"
    ui_print " "
fi

# Flash extra physical partition images if bundled in the package
flash_generic init_boot
flash_generic dtbo

ui_print " "
ui_print " "

# Flash all bundled Magisk / KernelSU / APatch module zips
ui_print " "
ui_print "  Installing bundled modules..."
ui_print "  ======================================================"

mount /data 2>/dev/null

for modzip in "$AKHOME"/*.zip; do
    [ -f "$modzip" ] || continue
    zipname=$(basename "$modzip")

    # Skip AnyKernel3 zip itself if present in working dir
    case "$zipname" in
        KO_*|*anykernel*|*AnyKernel*) continue ;;
    esac

    # Verify if zip is a Magisk/KSU module (contains module.prop)
    if ! unzip -l "$modzip" 2>/dev/null | grep -q "module.prop"; then
        continue
    fi

    ui_print "  • Installing module: $zipname"

    installed=0
    # 1. Native CLI installer if root manager binary is present
    if [ -x /data/adb/ksu/bin/ksud ]; then
        if /data/adb/ksu/bin/ksud module install "$modzip" >/dev/null 2>&1; then
            installed=1
        fi
    elif [ -x /data/adb/ap/bin/apd ]; then
        if /data/adb/ap/bin/apd module install "$modzip" >/dev/null 2>&1; then
            installed=1
        fi
    elif [ -x /data/adb/magisk/magisk ]; then
        if /data/adb/magisk/magisk --install-module "$modzip" >/dev/null 2>&1; then
            installed=1
        fi
    fi

    # 2. Universal update-binary execution via manager util_functions.sh
    if [ "$installed" -eq 0 ]; then
        tmp_mod="/tmp/mod_inst_$$"
        rm -rf "$tmp_mod"
        mkdir -p "$tmp_mod"
        if unzip -q -o "$modzip" -d "$tmp_mod" 2>/dev/null; then
            if [ -f "$tmp_mod/META-INF/com/google/android/update-binary" ]; then
                (
                    cd "$tmp_mod"
                    sh "$tmp_mod/META-INF/com/google/android/update-binary" 3 1 "$modzip"
                ) >/dev/null 2>&1 && installed=1
            fi
        fi
        rm -rf "$tmp_mod"
    fi

    # 3. Direct extraction fallback into /data/adb/modules
    if [ "$installed" -eq 0 ] && [ -d /data/adb/modules ]; then
        mod_id=$(unzip -p "$modzip" module.prop 2>/dev/null | grep -E '^id=' | head -n1 | cut -d= -f2 | tr -d ' \r\n')
        if [ -n "$mod_id" ]; then
            target_dir="/data/adb/modules/$mod_id"
            mkdir -p "$target_dir"
            unzip -q -o "$modzip" -d "$target_dir" 2>/dev/null
            rm -f "$target_dir/disable" "$target_dir/remove"
            touch "$target_dir/update"
            chmod 755 "$target_dir"/*.sh 2>/dev/null || true
            installed=1
        fi
    fi

    if [ "$installed" -eq 1 ]; then
        ui_print "    -> Successfully installed $zipname"
    else
        ui_print "    -> Skipped $zipname (no active root manager / unencrypted data)"
    fi
done

ui_print "  ======================================================"
