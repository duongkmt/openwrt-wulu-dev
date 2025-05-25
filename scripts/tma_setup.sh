#!/bin/bash

awk 1 ./boards/wlnw-1/tma_diffconfig >> .config
echo Make defconfig...
make defconfig
