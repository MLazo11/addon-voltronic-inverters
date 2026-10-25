#!/bin/bash
# bms-poll.sh: periodic READ-ONLY QBMS poll (BMS message as received by the inverter) -> MQTT sensors for Home Assistant and InfluxDB.
# Uses the same port lock as mqtt-push.sh and mqtt-subscriber.sh. It never sends set commands.
CFG=/etc/inverter/mqtt.json
SRV=$(jq -r .server $CFG)
PRT=$(jq -r .port $CFG)
TOP=$(jq -r .topic $CFG)
NAM=$(jq -r .devicename $CFG)
SER=$(jq -r .serial $CFG)
USR=$(jq -r .username $CFG)
PWD_=$(jq -r .password $CFG)
MF=$(jq -r .manufacturer $CFG)
MD=$(jq -r .model $CFG)
VR=$(jq -r .ver $CFG)
BASE="$TOP/sensor/${NAM}_${SER}"
PAUSE=2
pub() { mosquitto_pub -h "$SRV" -p "$PRT" -u "$USR" -P "$PWD_" -i "bmspoll_${SER}" -t "$1" -m "$2" $3; }
reg() { U=""; [ -n "$2" ] && U=",\"unit_of_measurement\":\"$2\""; pub "$BASE/$1/config" "{\"name\":\"$4\",\"uniq_id\":\"${SER}_$1\",\"device\":{\"ids\":\"$SER\",\"mf\":\"$MF\",\"mdl\":\"$MD\",\"name\":\"$NAM\",\"sw\":\"$VR\"},\"state_topic\":\"$BASE/$1\",\"state_class\":\"measurement\",\"icon\":\"mdi:$3\"$U}" -r; }
regt() { pub "$BASE/$1/config" "{\"name\":\"$2\",\"uniq_id\":\"${SER}_$1\",\"device\":{\"ids\":\"$SER\",\"mf\":\"$MF\",\"mdl\":\"$MD\",\"name\":\"$NAM\",\"sw\":\"$VR\"},\"state_topic\":\"$BASE/$1\",\"icon\":\"mdi:battery-heart-variant\"}" -r; }
reg_all() { reg BMS_connected "" battery-check "BMS connected"; reg BMS_soc "%" battery "BMS soc"; reg BMS_force_charge "" battery-charging "BMS force charge"; reg BMS_stop_discharge "" battery-off "BMS stop discharge"; reg BMS_stop_charge "" battery-off-outline "BMS stop charge"; reg BMS_charge_voltage "V" current-dc "BMS charge voltage"; reg BMS_float_voltage "V" current-dc "BMS float voltage"; reg BMS_cutoff_voltage "V" current-dc "BMS cutoff voltage"; reg BMS_max_charge_current "A" current-dc "BMS max charge current"; reg BMS_max_discharge_current "" current-dc "BMS max discharge current raw"; regt BMS_raw "BMS raw message"; }
d1() { v=$((10#$1)); echo "$((v/10)).$((v%10))"; }
reg_all
N=0
BAD=0
while :; do
  OUT=$(flock -w 15 /tmp/inverter_poller.lock timeout 10 /opt/inverter-cli/bin/inverter_poller -r QBMS 2>&1)
  R=$(echo "$OUT" | grep -m1 'Reply:' | sed 's/.*Reply: *//' | tr -d '\r')
  set -- $R
  if [ $# -eq 10 ] && ! echo "$R" | grep -q '[^0-9 ]'; then
    pub "$BASE/BMS_connected" "$((10#$1))"
    pub "$BASE/BMS_soc" "$((10#$2))"
    pub "$BASE/BMS_force_charge" "$((10#$3))"
    pub "$BASE/BMS_stop_discharge" "$((10#$4))"
    pub "$BASE/BMS_stop_charge" "$((10#$5))"
    pub "$BASE/BMS_charge_voltage" "$(d1 $6)"
    pub "$BASE/BMS_float_voltage" "$(d1 $7)"
    pub "$BASE/BMS_cutoff_voltage" "$(d1 $8)"
    pub "$BASE/BMS_max_charge_current" "$((10#$9))"
    pub "$BASE/BMS_max_discharge_current" "$((10#${10}))"
    pub "$BASE/BMS_raw" "$R"
    BAD=0
  else
    BAD=$((BAD+1))
    [ $((BAD % 50)) -eq 1 ] && echo "[BMS] invalid QBMS reply ($BAD in a row): $R"
  fi
  N=$((N+1))
  [ $((N % 200)) -eq 0 ] && reg_all
  sleep $PAUSE
done
