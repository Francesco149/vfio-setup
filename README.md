my vfio gpu passthrough setup on a 5900x.

I don't recommend using it as is. read the `win10.sh` script for reference

this setup has been tested with latency sensitive audio stuff with no issue. I livestream from
the vm no problem

assumes you have a win10.img disk image and
`virtio-win-0.1.185.iso` which you can get from https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso .

the script also assumes that your sudo doesn't ask for password

you also need to have [vfio-isolate](https://github.com/darkguy2008/vfio-isolate) installed.
I also have [vendor-reset](https://github.com/gnif/vendor-reset) to fix the reset bug on my
rx570.

libcgroup is also needed for cpu isolation (which is enabled by default in the script)

you also need to set up a br0 bridge device, example with nmcli using interface enp42s0

    nmcli con add type bridge con-name br0 ifname br0 autoconnect yes
    nmcli con add type bridge-slave ifname enp42s0 master br0

    # use nmcli to set static ip on br0 if needed, as if it was your main connection

    nmcli con down "Wired connection 1"
    nmcli con up br0
    nmcli connection add type tun ifname tap0 con-name mytap mode tap owner `id -u`
    nmcli connection mod mytap connection.slave-type bridge connection.master br0

I use barrier to share mouse between linux and windows

to start the vm, you need to cd to the path where the script and the disk image are located and
start `./win10.sh`
