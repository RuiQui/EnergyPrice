# 🔌 EnergyPrice

> 将实时电价接入 Home Assistant，支持阶梯电价、峰谷电价、一户多人口等复杂计价规则。

---

## 🚀 功能介绍

- 📡 **MQTT 实时读取**  
  从 Tasmota 设备通过 MQTT 获取总用电量数据。

- 💰 **电价计算与上报**  
  根据实时用电量、时间段、季节、人口户型等动态计算当前电价，并通过 MQTT 实时推送至 Home Assistant。

- 🧮 **支持多种电价模型组合**  
  - 阶梯电价（三档）
  - 峰谷分时电价
  - 一户多人口阈值调整

- ☀️❄️ **自动判断夏季 / 非夏季**  
  自动根据月份（5~10 月为夏季）切换电价计算逻辑。

- 🗓️ **月初数据归档至数据库**  
  每月第一次启动时，将当前用电量作为月初数据写入 MySQL 数据库。

---

## 📦 使用方法

1. 创建数据库：
   ```
   CREATE TABLE tasmota_power (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME,
    energy_total FLOAT
    );
   ```
2. 克隆脚本到本地目录：

   ```bash
   git clone https://github.com/RuiQui/EnergyPrice.git
   cd EnergyPrice
   ```

3. 创建配置文件 `.mqtt.conf`：用于存储 MQTT 连接信息。

   ```bash
   MQTT_HOST="localhost"
   MQTT_PORT="1883"
   MQTT_USER="your_username"
   MQTT_PASS="your_password"
   MQTT_TOPIC="tele/DEVS_XXXX/SENSOR"
   ```

4. 创建配置文件 `.my.cnf`：用于 MySQL 自动登录。

   ```ini
   [client]
   user=your_mysql_user
   password=your_mysql_password
   host=127.0.0.1
   port=3306
   ```

5. 启动脚本：

   ```bash
   ./energyprice.sh
   ```

6. 在 Home Assistant 中订阅 `home/energy/price` 主题，接收实时电价推送。
   ```
   实体名称：实时电价
   实体类型：传感器
   状态类别：测量值
   度量单位：CNY/kWh
   状态主题：home/energy/price
   值模板：{{ value_json.price }}

   实体名称：实时电价 电价状态
   状态主题：home/energy/price
   值模板：{{ value_json.status }}

   上面没有提到的选项均为空
   ```

---

## 🖼️ 效果图

<img width="1027" height="692" alt="image" src="https://github.com/user-attachments/assets/7c190260-b9dd-4360-861b-382c4b0141aa" />
<img width="1277" height="848" alt="image" src="https://github.com/user-attachments/assets/5db61ef0-b053-43e3-b8cc-e5081356010f" />


---

## 📄 开源许可建议


* **GPLv3**


---

## 🙌 欢迎参与

如有建议、问题或功能需求，欢迎提交 [Issue](https://github.com/RuiQui/EnergyPrice/issues) 或 PR！

