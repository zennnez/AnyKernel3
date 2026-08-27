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
do.check_boot_version=0
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
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

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

# GKI check
kernel_version=$(cat /proc/version | awk -F '-' '{print $1}' | awk '{print $3}')
case $kernel_version in
    5.10*) ksu_supported=true ;;
    5.15*) ksu_supported=true ;;
    6.1*) ksu_supported=true ;;
    6.6*) ksu_supported=true ;;
    6.12*) ksu_supported=true ;;
    *) ksu_supported=false ;;
esac

ui_print " " "  -> Knockout Kernels Supported: $ksu_supported"
$ksu_supported || abort "  -> Non-GKI device, abort."

# boot install
split_boot

if [ -f "$SPLITIMG/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi

ui_print " "
ui_print " "