#!/bin/bash

# Change this to the current date and time
CURRENT_TIME="2026-08-05 22:20:00"

sudo timedatectl set-time "$CURRENT_TIME"

# Save system time to hardware RTC
sudo hwclock --systohc

echo "System time:"
date

echo "RTC time:"
sudo hwclock
