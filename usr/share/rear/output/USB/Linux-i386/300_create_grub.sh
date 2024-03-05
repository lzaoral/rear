
# Only run when GRUB2 is specified to be used as USB bootloader:
test "$USB_BOOTLOADER" = "grub" || return 0

# We assume REAL_USB_DEVICE and RAW_USB_DEVICE are both set by prep/USB/Linux-i386/350_check_usb_disk.sh
[ "$RAW_USB_DEVICE" -a "$REAL_USB_DEVICE" ] || BugError "RAW_USB_DEVICE and REAL_USB_DEVICE are not both set"

LogPrint "Using GRUB2 as USB bootloader for legacy BIOS boot on $RAW_USB_DEVICE (USB_BOOTLOADER='$USB_BOOTLOADER')"

# Choose the right GRUB2 install binary and set the right GRUB2 boot directory
# cf. https://github.com/rear/rear/issues/849 and https://github.com/rear/rear/pull/850
# and error out if there is neither grub-install nor grub2-install:
local grub_install_binary="false"
has_binary grub-install && grub_install_binary="grub-install"
has_binary grub2-install && grub_install_binary="grub2-install"
is_false $grub_install_binary && Error "Cannot install GRUB2 as USB bootloader (neither grub-install nor grub2-install found)"
# Choose the right GRUB2 config depending on what there is on the original system
# (if things are unexpected on the original system using GRUB2 as USB bootloader likely fails)
# so better error out here if there is neither /boot/grub/grub.cfg nor /boot/grub2/grub.cfg
# cf. "Try hard to care about possible errors" in https://github.com/rear/rear/wiki/Coding-Style
local grub_cfg="false"
test -s /boot/grub/grub.cfg && grub_cfg="grub/grub.cfg"
test -s /boot/grub2/grub.cfg && grub_cfg="grub2/grub.cfg"
is_false $grub_cfg && Error "Cannot install GRUB2 as USB bootloader (neither /boot/grub/grub.cfg nor /boot/grub2/grub.cfg found)"

# Verify the GRUB version because only GRUB2 is supported.
# Because substr() for awk did not work as expected for this case here
# 'cut' is used (awk '{print $NF}' prints the last column which is the version).
# Only the first character of the version should be enough (at least for now).
# Example output (on openSUSE Leap 15.2)
# # grub2-install --version
# grub2-install (GRUB2) 2.04
# # grub2-install --version | awk '{print $NF}' | cut -c1
# 2
local grub_version
grub_version=$( $grub_install_binary --version | awk '{print $NF}' | cut -c1 )
test "$grub_version" = "2" || Error "Cannot install GRUB as USB bootloader (only GRUB2 is supported, '$grub_install_binary --version' shows '$grub_version')"

# Install and configure GRUB2 as USB bootloader for legacy BIOS boot:
local usb_boot_dir="$BUILD_DIR/outputfs/boot"
if [ ! -d "$usb_boot_dir" ] ; then
    mkdir -p $v "$usb_boot_dir" || Error "Failed to create USB boot dir '$usb_boot_dir'"
fi
DebugPrint "Installing GRUB2 as USB bootloader on $RAW_USB_DEVICE"
# Set default USB_GRUB2_INSTALL_OPTIONS only if there are no USB_GRUB2_INSTALL_OPTIONS set:
test "$USB_GRUB2_INSTALL_OPTIONS" || USB_GRUB2_INSTALL_OPTIONS=""
# grub-install defaults to '--target=x86_64-efi' when the system is booted with EFI.
# So it would fail to install a legacy BIOS (or 32bit) GRUB2 without setting the --target parameter.
# ("man grub2-install" tells "TARGET platform [default=i386-pc]" but this is more like a fallback.)
# So setting explicitly a legacy BIOS target is needed when the system is booted with EFI,
# see https://github.com/rear/rear/issues/2883
if is_true $USING_UEFI_BOOTLOADER ; then
    # TODO: only call grub-install if legacy boot install is explicitly requested
    # TODO: use a switch case based on the target (uname -m) and possibly other info?
    # Enforce legacy BIOS installation since EFI was handled in 100_create_efiboot.sh
    # see https://github.com/rear/rear/issues/2883
    # Set a GRUB2 target only if there is no '--target=' in USB_GRUB2_INSTALL_OPTIONS
    # (according to "man grub2-install" of grub2-2.06 on openSUSE Leap 15.4
    #  '--target=TARGET' is the only possible syntax to specify a GRUB2 target)
    # because a GRUB2 target could be already specified like '--target=i386-qemu'
    # cf. https://github.com/rear/rear/pull/2905#discussion_r1062457353
    [[ "$USB_GRUB2_INSTALL_OPTIONS" == *"--target="* ]] || USB_GRUB2_INSTALL_OPTIONS+=" --target=i386-pc"
fi
test "$USB_GRUB2_INSTALL_OPTIONS" && DebugPrint "Using USB_GRUB2_INSTALL_OPTIONS '$USB_GRUB2_INSTALL_OPTIONS'"
$grub_install_binary $USB_GRUB2_INSTALL_OPTIONS --boot-directory=$usb_boot_dir --recheck $RAW_USB_DEVICE || Error "Failed to install GRUB2 on $RAW_USB_DEVICE"
# grub[2]-install creates the $BUILD_DIR/outputfs/boot/grub[2] sub-directory that is needed
# to create the GRUB2 config $BUILD_DIR/outputfs/boot/grub[2].cfg in the next step:
DebugPrint "Creating GRUB2 config for legacy BIOS boot as USB bootloader"
# In default.conf there is USB_BOOT_PART_SIZE="0" i.e. no (optional) boot partition
# and USB_DEVICE_BOOT_LABEL="REARBOOT" which conflicts with "no boot partition"
# so we need to use the ReaR data partition label as fallback
# when 'lsblk' shows nothing with a USB_DEVICE_BOOT_LABEL.
# Very old Linux distributions that do not contain lsblk (e.g. SLES10)
# are not supported by ReaR and the code below will error out there.
# "lsblk -no LABEL /dev/..." works e.g. on SLES11 SP3 (which is also not supported)
# so the code should work on all Linux distributions that are supported by ReaR.
# USB_DEVICE_BOOT_LABEL must not be empty (otherwise grep "" falsely succeeds):
contains_visible_char "$USB_DEVICE_BOOT_LABEL" || USB_DEVICE_BOOT_LABEL="REARBOOT"
if lsblk -no LABEL $RAW_USB_DEVICE | grep "$USB_DEVICE_BOOT_LABEL" ; then
    DebugPrint "Found USB_DEVICE_BOOT_LABEL '$USB_DEVICE_BOOT_LABEL' on $RAW_USB_DEVICE"
else
    LogPrintError "Could not find USB_DEVICE_BOOT_LABEL '$USB_DEVICE_BOOT_LABEL' on $RAW_USB_DEVICE"
    # USB_DEVICE_FILESYSTEM_LABEL must not be empty (otherwise grep "" falsely succeeds):
    contains_visible_char "$USB_DEVICE_FILESYSTEM_LABEL" || USB_DEVICE_FILESYSTEM_LABEL="REAR-000"
    if lsblk -no LABEL $RAW_USB_DEVICE | grep "$USB_DEVICE_FILESYSTEM_LABEL" ; then
        LogPrintError "Using USB_DEVICE_FILESYSTEM_LABEL '$USB_DEVICE_FILESYSTEM_LABEL' as USB_DEVICE_BOOT_LABEL"
        USB_DEVICE_BOOT_LABEL="$USB_DEVICE_FILESYSTEM_LABEL"
    else
        Error "Found neither USB_DEVICE_BOOT_LABEL '$USB_DEVICE_BOOT_LABEL' nor USB_DEVICE_FILESYSTEM_LABEL '$USB_DEVICE_FILESYSTEM_LABEL' on $RAW_USB_DEVICE"
    fi
fi
# We need to set the GRUB environment variable 'root' to the partition device with filesystem label USB_DEVICE_BOOT_LABEL
# because GRUB's default 'root' (or GRUB's 'root' identifcation heuristics) would point to the ramdisk but neither kernel
# nor initrd are located on the ramdisk but on the partition device with filesystem label USB_DEVICE_BOOT_LABEL.
# GRUB2_SET_ROOT_COMMAND and/or GRUB2_SEARCH_ROOT_COMMAND is needed by the create_grub2_cfg() function.
# Set GRUB2_SEARCH_ROOT_COMMAND if not specified by the user:
contains_visible_char "$GRUB2_SEARCH_ROOT_COMMAND" || GRUB2_SEARCH_ROOT_COMMAND="search --no-floppy --set=root --label $USB_DEVICE_BOOT_LABEL"
create_grub2_cfg /$USB_PREFIX/kernel /$USB_PREFIX/$REAR_INITRD_FILENAME > $usb_boot_dir/$grub_cfg
