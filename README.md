# EnergyPrice
将实时电价接入Home-Assistant

目前实现的功能：
1、通过MQTT读取Tasmota上报的总用电量信息
2、通过MQTT上报当前电价
3、实现一户多人口以及峰谷电价叠加阶梯电价功能
4、判断夏季、非夏季用电
5、月初用电量写入MySql数据库
