#!/bin/sh

dev="$(echo "$3" | sed 's/:/ /g')"
echo "$2" | sudo tee "/sys/bus/pci/devices/$2/driver/unbind"
if [ "$1" = "unbind" ]; then
  echo "$dev" | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id
else
  echo "$dev" | sudo tee /sys/bus/pci/drivers/vfio-pci/remove_id
fi
echo "$2" | sudo tee "/sys/bus/pci/drivers_probe"
dev="$(echo "$3" | sed 's/ /:/g')"
lspci -nnk -d "$dev"
