#!/bin/bash

# —— 配置文件路径 ——
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" #定位到脚本的目录
MYSQL_CONF="$SCRIPT_DIR/.my.cnf"  #数据库密钥文件
MQTT_CONF="$SCRIPT_DIR/.mqtt.conf" #MQTT密钥文件

# —— 加载 MQTT 配置 ——
source "$MQTT_CONF"
MQTT_PRICE_TOPIC="home/energy/price" #电价上传数据

# —— MySQL 配置 ——
MYSQL_DB="energyprice"  #数据库名
MYSQL_TABLE="tasmota_power"  #表名

# —— 电价配置与逻辑参数 ——  
one_more_enabled=false  #一户多人口启用
tou_enabled=true  # 峰谷电价启用

price_base=0.60886875    # 基础阶梯电价（第一档）
price_mid=0.65886875     # 阶梯电价第二档
price_high=0.90886875    # 阶梯电价第三档
price_peak=1.02896875    # 峰段电价（分时基价部分）
price_valley=0.23676875  # 谷段电价（分时基价部分）
price_flat=$price_base   # 平段电价

# 阶梯阈值
limit1_non=200   #非夏季第二档阈值
limit2_non=400   #非夏季第三档阈值
limit1_sum=260   #夏季第二档阈值
limit2_sum=600   #夏季第三档阈值
[ "$one_more_enabled" = true ] && limit1_non=$((limit1_non+100)) && limit1_sum=$((limit1_sum+100)) && limit2_non=$((limit1_non+100)) && limit2_sum=$((limit1_sum+100))  #一户多人口每阶段电量上调100度

# —— 夏季状态获取函数 ——
get_summer_status(){
  month=$(date +%-m) #获取当前月份
  if (( month >= 5 && month <= 10 )); then
    season="summer"
  else
    season="non_summer"
  fi
}

# —— 分时电价计算函数 ——
get_tou_status(){
  hm=$(date +%H%M); hm=$((10#$hm)) #四位数时间，强制十进制计算
  if (( hm < 800 )); then
    echo "$price_valley" "低谷"
  elif (( (hm>=1000 && hm<1200) || (hm>=1400 && hm<1900) )); then
    echo "$price_peak" "高峰"
  else
    echo "$price_flat" "平段"
  fi
}

# —— 电价状态获取函数 ——
get_ladder_status(){
  used=$1
  if [ "$season" = "summer" ]; then
    if (( $(echo "$used <= $limit1_sum" | bc -l) )); then
      echo "$price_base" "夏季,第一档"
    elif (( $(echo "$used <= $limit2_sum" | bc -l) )); then
      echo "$price_mid" "夏季,第二档"
    else
      echo "$price_high" "夏季,第三档"
    fi
  else
    if (( $(echo "$used <= $limit1_non" | bc -l) )); then
      echo "$price_base" "非夏季,第一档"
    elif (( $(echo "$used <= $limit2_non" | bc -l) )); then
      echo "$price_mid" "非夏季,第二档"
    else
      echo "$price_high" "非夏季,第三档"
    fi
  fi
}

# —— 阶梯增量计算函数 ——  
get_ladder_delta(){
  used=$1
  if [ "$season" = "summer" ]; then
    if (( $(echo "$used <= $limit1_sum" | bc -l) )); then
      #第一档无增量
      delta=0
    elif (( $(echo "$used <= $limit2_sum" | bc -l) )); then
      #第二档减第一档
      delta=$(awk "BEGIN{printf \"%g\", $price_mid - $price_base}") 
    else
      # 第三档减第一档
      delta=$(awk "BEGIN{printf \"%g\", $price_high - $price_base}")
    fi
  else
    if (( $(echo "$used <= $limit1_non" | bc -l) )); then
      delta=0
    elif (( $(echo "$used <= $limit2_non" | bc -l) )); then
      delta=$(awk "BEGIN{printf \"%g\", $price_mid - $price_base}")
    else
      delta=$(awk "BEGIN{printf \"%g\", $price_high - $price_base}")
    fi
  fi
  echo "$delta"
}

# —— 更新综合电价与状态函数 ——  
get_price_and_status(){
  used=$1
  if [ "$tou_enabled" = "true" ]; then
    read price_tou status_tou <<< "$(get_tou_status)" #获取峰谷电价和状态
    read ladder_price status_ladd <<< "$(get_ladder_status "$used")" #获取季节挡位状态
    delta=$(get_ladder_delta "$used") #获取峰谷电价增量
    if (( $(echo "$delta == 0" | bc -l) )); then
      price="$price_tou" #无增量，直接为峰谷电价
      status="$status_tou,$status_ladd"
    else
      price=$(awk "BEGIN{printf \"%.8f\", $price_tou + $delta}") #超过第一档，峰谷电价加增量
      status="$status_tou,$status_ladd,+${delta}"
    fi
  else
    read price status <<< "$(get_ladder_status "$used")"  #未开启峰谷电价，获取阶梯电价
  fi
  echo "$price" "$status"
}

# —— 月初初始化逻辑 ——  
refresh_current_ym(){
  current_year=$(date +%Y); current_month=$(date +%m) #获取当前年月
}
start_energy=""
check_and_init_month(){
  refresh_current_ym
  row=$(mysql --defaults-extra-file="$MYSQL_CONF" -N -e "
    SELECT energy_total FROM $MYSQL_DB.$MYSQL_TABLE
    WHERE YEAR(timestamp)=$current_year AND MONTH(timestamp)=$current_month
    ORDER BY timestamp ASC LIMIT 1;
  ")
  if [ -n "$row" ]; then
    start_energy=$row
    echo "✅ 使用已有 ${current_year}年${current_month}月 月初电量：${start_energy} kWh"
  else
    # —— 新增初始电价上报 ——  
    used=0 #假设月初用电量为0
    read price status <<< "$(get_price_and_status "$used")" #获取电价和状态
    last_price="$price"
    last_status="$status"
    json="{\"price\":${price},\"status\":\"${status}\",\"used\":${used}}"
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
      -t "$MQTT_PRICE_TOPIC" -m "$json" #直接上报电价
    echo "[$(date '+%F %T')] 初始上报 用电: ${used} kWh, 电价: ¥${price}/kWh, 状态: ${status}"
    payload=$(mosquitto_sub -C 1 -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$MQTT_TOPIC")
    total=$(echo "$payload" | jq '.ENERGY.Total')
    if [ -n "$total" ] && [ "$total" != "null" ]; then
      first="${current_year}-${current_month}-01 00:00:00"
      mysql --defaults-extra-file="$MYSQL_CONF" "$MYSQL_DB" <<EOF
INSERT INTO $MYSQL_TABLE (timestamp, energy_total) VALUES ('$first', $total);
EOF
      start_energy=$total
      echo "🆕 插入 ${current_year}年${current_month}月 月初电量：${start_energy} kWh"
    else
      echo "⚠️ 无法获取初始电量，退出"; exit 1
    fi
  fi
}

#开始运行
#检查和定义月
check_and_init_month

last_price=""
last_status=""
last_report_ts=$(date +%s) #当前时间戳

#从TASMOTA读取总用电量
mosquitto_sub -v -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
  -t "$MQTT_TOPIC" -t "$MQTT_TOPIC_STATUS_10" |
while read -r topic payload; do #循环
  old_year=$current_year
  old_month=$current_month
  refresh_current_ym #获取当前年月
  get_summer_status #检查夏季状态
  if [ "$current_year" != "$old_year" ] || [ "$current_month" != "$old_month" ]; then
    echo "➡️ 月份变化：${old_year}-${old_month} → ${current_year}-${current_month}"
    check_and_init_month #初始化年月，写入当前电量
  fi

  if [[ "$topic" == "$MQTT_TOPIC_STATUS_10" ]]; then
  total=$(echo "$payload" | jq -r '.StatusSNS.ENERGY.Total')
else
  total=$(echo "$payload" | jq -r '.ENERGY.Total')
fi

  [ -z "$total" ] || [ "$total" = "null" ] && continue
  used=$(echo "$total - $start_energy" | bc -l)

  read price status <<< "$(get_price_and_status "$used")"

  now_ts=$(date +%s)
  elapsed=$(( now_ts - last_report_ts ))

  if [ "$price" != "$last_price" ] || [ "$status" != "$last_status" ] || [ "$elapsed" -ge 3600 ] || [[ "$topic" == "$MQTT_TOPIC_STATUS_10" ]]; then
    json="{\"price\":${price},\"status\":\"${status}\",\"used\":\"${used}\"}"
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
      -t "$MQTT_PRICE_TOPIC" -m "$json"
    echo "[$(date '+%F %T')] 用电: ${used} kWh, 电价: ¥${price}/kWh, 状态: $status"
    last_price=$price
    last_status=$status
    last_report_ts=$now_ts
  fi
done
