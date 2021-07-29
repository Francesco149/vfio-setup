#!/bin/sh

dir="$(dirname "$(readlink "$0")")"
cd "$dir" || exit

vmname="win10"
socketf="${vmname}socket"

headless() {
  if [ -t 0 ] && [ -t 1  ]; then
    return 1
  fi
}

msg() {
  headless && notify-send "[$(basename "$0")] $*"
  echo ":: $*"
}

if ! command -v socat >/dev/null 2>&1; then
  msg "!! Please install socat"
  exit 1
fi

if echo "info status" | sudo socat - "unix-connect:$socketf" >/dev/null 2>&1; then
  if headless; then
    msg "VM already running, run me in a terminal for the monitor"
  else
    msg "VM already running, starting monitor"
    sudo socat -,echo=0,icanon=0 "unix-connect:$socketf"
  fi
  exit
fi


use_shield=yes
ram=$(( 2048 * 8 ))

undofile="${vmname}-undo.run"

vfio_undo() {
  if [ -f "$undofile" ]; then
    if sudo vfio-isolate -v restore "$undofile"; then
      msg "undid $undofile"
      sudo rm "$undofile"
    else
      msg "something's wrong with undoing $undofile"
      exit
    fi
  fi
}

shield() {
  guestcpus="C6-11,18-23"
  vfio_undo
  sudo vfio-isolate \
    -v -u "$undofile" \
    drop-caches \
    compact-memory \
    cpuset-create --cpus C0-5,12-17 /host.slice \
    cpuset-create --cpus "$guestcpus" -nlb /machine.slice \
    move-tasks / /host.slice \
    irq-affinity mask "$guestcpus"
}

unshield() {
  vfio_undo
}

utils/vfio.sh unbind '0000:2d:00.3' '1022 149c' # pass through usb3 controller
sudo sysctl vm.nr_hugepages=16                  # allocate 16GB of hugepages

msg "Starting VM $vmname from $(pwd)"
if [ -z "$use_shield" ]; then
  cmd="qemu-system-x86_64"
  cores=12
else
  cores=6
  shield
  cmd="sudo cgexec -g cpuset:machine.slice qemu-system-x86_64"
fi
$cmd \
  -no-user-config -nodefaults \
  -enable-kvm \
  -machine mem-merge=off,type=q35,kvm-shadow-mem=256000000,accel=kvm,graphics=off,usb=off,vmport=off,smm=on,dump-guest-core=off,kernel_irqchip=on \
  -watchdog-action none \
  -global kvm-pit.lost_tick_policy=delay -no-hpet \
  -rtc base=localtime,driftfix=slew \
  -cpu max,check,l3-cache=on,-hypervisor,kvm=off,+kvm_pv_unhalt,+kvm_pv_eoi,migratable=no,kvmclock=on,kvm-nopiodelay=on,kvm-asyncpf=on,kvm-steal-time=on,kvmclock-stable-bit=on,x2apic=on,acpi=off,monitor=off,svm=off,+topoext,+invtsc,hv-spinlocks=0x1fff,hv_reset,hv_runtime,hv_vapic,hv_time,hv_relaxed,hv_vpindex,hv_synic,hv_stimer,hv_vendor_id=1234567890ab \
  -smp $(( cores * 2 )),sockets=1,dies=1,cores=$(( cores )),threads=2 \
  -serial none -parallel none \
  -m $ram -mem-path /hugepages -mem-prealloc -overcommit mem-lock=on,cpu-pm=on \
  -drive "file=virtio-win-0.1.185.iso,index=1,media=cdrom" \
  -drive "if=virtio,format=raw,file=${vmname}.img,cache=none,format=raw,aio=native" \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/ovmf/x64/OVMF_CODE.fd \
  -netdev tap,id=network0,ifname=tap0,script=no,downscript=no,vhost=on \
  -device virtio-net,netdev=network0,mac=52:54:00:af:96:e9 \
  -spice port=5900,disable-ticketing \
  -device virtio-serial-pci \
  -chardev spicevmc,id=vdagent,name=vdagent \
  -device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
  -device usb-ehci,id=ehci \
  -device qemu-xhci -device usb-kbd \
  -monitor unix:$socketf,server,nowait \
  -name "$vmname",debug-threads=on \
  -device pcie-root-port,chassis=1,id=pci.1,bus=pcie.0 \
  -device pcie-root-port,chassis=2,id=pci.2,bus=pcie.0,multifunction=on \
  -device pcie-root-port,chassis=3,id=pci.3,bus=pcie.0,multifunction=on \
  -device vfio-pci,host=0000:04:00.0,id=hostdev0,bus=pci.1 \
  -device vfio-pci,host=0000:04:00.1,id=hostdev1,bus=pci.2 \
  -device vfio-pci,host=0000:2d:00.3,id=usbcontroller,bus=pci.3 \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-pci,rng=rng0,disable-legacy=on,disable-modern=off \
  -vga none -nographic \
  -boot c \
  2>&1 | tee -a "${vmname}.log" || msg "VM $vmname terminated unexpectedly"

utils/vfio.sh bind '0000:2d:00.3' '1022 149c' # return usb3 controller to linux
sudo sysctl vm.nr_hugepages=0                 # free up ram
[ -z "$use_shield" ] || unshield

exit
