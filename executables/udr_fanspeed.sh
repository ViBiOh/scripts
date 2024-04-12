#!/bin/sh

fanSetting=$(cat /sys/class/hwmon/hwmon0/pwm1)
currentTemp=$(sensors -u | grep temp1_input | cut -c 16-)
currentTemp=$(echo ${currentTemp%.*})

thresholdTemp=60
minimumFanSpeed=36

# If current temperature is below our threshold reduce the fan speed
if [ "$currentTemp" -le $thresholdTemp ]; then
  if [ "$fanSetting" -gt $minimumFanSpeed ]; then
    newFanspeed=$((fanSetting - 10))

    echo "Temperature under threshold of $thresholdTemp, decreasing fan speed"

    if [ "$newFanspeed" -lt $minimumFanSpeed ]; then
      newFanspeed=$minimumFanSpeed
    fi

    chmod 644 "/sys/class/hwmon/hwmon0/pwm1"
    echo $newFanspeed >/sys/class/hwmon/hwmon0/pwm1
    chmod 444 "/sys/class/hwmon/hwmon0/pwm1"
  fi
else
  newFanspeed=$((fanSetting + 10))

  echo "Temperature over threshold of $thresholdTemp, increasing fan speed"

  if [ "$newFanspeed" -gt 255 ]; then
    newFanspeed=255
  fi

  chmod 644 "/sys/class/hwmon/hwmon0/pwm1"
  echo $newFanspeed >/sys/class/hwmon/hwmon0/pwm1
  chmod 444 "/sys/class/hwmon/hwmon0/pwm1"
fi

exit 0
