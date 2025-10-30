# CUIOT MQTT 项目核心流程图

## 1. 项目整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                          主线程 cuiotCloud()                      │
│  ┌──────────────┐  ┌─────────────┐  ┌────────────────────────┐ │
│  │ 初始化模块    │  │ 配置解析    │  │   子线程监控循环        │ │
│  │              │  │             │  │                        │ │
│  │ mqtt_cloud_  │  │ mqtt_parse_ │  │ while(1) {            │ │
│  │ init()       │→ │ project()   │→ │   sub_thread_monitor()│ │
│  │              │  │             │  │   soft_watchdog_feed()│ │
│  │ dmpcu_init() │  │             │  │ }                     │ │
│  └──────────────┘  └─────────────┘  └────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 创建子线程
                              ↓
┌──────────────────────────────────────────────────────────────────────┐
│                            子线程体系                                  │
├──────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  线程1: mqtt_new_handle()         - MQTT 主连接线程            │ │
│  │  ├─ 状态机：INIT → CONNECT → LOGIN → DATA → DEVINFO          │ │
│  │  ├─ 负责：建立连接、订阅主题、维持心跳                          │ │
│  │  └─ 异常：RECONNECT / RECONNECT_WAIT                          │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  线程2: mqtt_new_handle_getInfo() - MQTT 信息查询线程         │ │
│  │  ├─ 专用于设备信息查询                                         │ │
│  │  └─ 独立连接，避免影响主连接                                   │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  线程3: report_message_strategy_handle() - 数据上报策略线程   │ │
│  │  ├─ 注册数据库回调：data_cb()                                  │ │
│  │  ├─ 接收数据 → 加入队列                                        │ │
│  │  └─ 定时触发上报                                               │ │
│  └────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 2. 系统启动流程（从 main 到运行）

```
程序启动
   │
   ↓
cuiotCloud() 主线程函数
   │
   ├─→ sal_thread_start()                 # 线程初始化
   │
   ├─→ mqtt_cloud_init()                  # 初始化全局变量
   │    └─ pthread_mutex_init()           # 数据锁初始化
   │
   ├─→ dmpcu_init()                       # DMPCU 特定初始化
   │    ├─ 读取 PROJECT_CONFIG_FILE 路径
   │    ├─ 构造 Token 文件路径：
   │    │   DMPCU_DEVICE_TOKEN = "xxx/mqtt_cuiot_deviceToken.para"
   │    │   DMPCU_DEVICE_KEY = "xxx/mqtt_cuiot_subdeviceToken.para"
   │    └─ cuiot_service_init()           # 初始化服务列表
   │
   ├─→ mqtt_parse_project()               # 解析配置文件
   │    ├─ json_parse_file_with_comments(PROJECT_CONFIG_FILE)
   │    ├─ 提取 "server" 对象
   │    └─ for each server:
   │         ├─ parse_server_configuration()
   │         │   ├─ 解析 IP/Port/ClientID/Username/Password
   │         │   ├─ parse_param_configuration()  # 解析参数
   │         │   ├─ dmpcu_parse_data()           # 解析 DMPCU 配置
   │         │   │   ├─ 解析 deviceInfo (网关配置)
   │         │   │   └─ 解析 subdeviceInfo (子设备配置)
   │         │   └─ 创建子线程：
   │         │       ├─ pthread_create(mqtt_new_handle_getInfo)
   │         │       ├─ pthread_create(mqtt_new_handle)
   │         │       └─ pthread_create(report_message_strategy_handle)
   │         └─ 返回主循环
   │
   └─→ 主监控循环
        while(1) {
           msleep(100);
           sub_thread_monitor(mqtt_server_group);  # 检查子线程健康
           soft_watchdog_feed(get_threadid());     # 喂主线程看门狗
        }
```

---

## 3. MQTT 连接线程状态机详细流程

```
mqtt_new_handle() 线程启动
   │
   ├─→ mosquitto_lib_init()                        # 初始化 Mosquitto 库
   ├─→ mosq = mosquitto_new(client_id, true, NULL)
   ├─→ 设置回调函数：
   │    ├─ mosquitto_message_callback_set()        → receive_message_handle
   │    ├─ mosquitto_connect_callback_set()        → mqtt_cloud_connect_handle
   │    ├─ mosquitto_disconnect_callback_set()     → mqtt_cloud_disconnect_handle
   │    ├─ mosquitto_subscribe_callback_set()      → mqtt_cloud_subscribe_handle
   │    └─ mosquitto_publish_callback_set()        → mqtt_cloud_publish_handle
   │
   └─→ 进入状态机主循环：

┌────────────────────────────────────────────────────────────────────┐
│  状态：MQTT_INIT                                                    │
├────────────────────────────────────────────────────────────────────┤
│  执行：mqtt_broker_init()                                          │
│        ├─ 检查网络状态                                             │
│        └─ 准备连接参数                                             │
│  配置 TLS (如启用):                                                │
│        ├─ mosquitto_tls_opts_set()                                │
│        ├─ mosquitto_tls_set()                                     │
│        └─ mosquitto_tls_insecure_set()                            │
│  设置认证：mosquitto_username_pw_set(usrname, passwd)              │
│  转换：change_run_status(MQTT_CONNECT)                            │
└────────────────────────────────────────────────────────────────────┘
              │
              ↓
┌────────────────────────────────────────────────────────────────────┐
│  状态：MQTT_CONNECT                                                 │
├────────────────────────────────────────────────────────────────────┤
│  执行：mosquitto_connect(mosq, address, port, heartbeat)           │
│  结果：                                                             │
│    ├─ 成功 (ret == 0):                                            │
│    │   ├─ isreconnect = 0                                         │
│    │   ├─ login_time = get_uptime()                               │
│    │   └─ 转到 MQTT_LOGIN                                         │
│    └─ 失败 (ret != 0):                                            │
│        └─ 转到 MQTT_RECONNECT_WAIT                                │
└────────────────────────────────────────────────────────────────────┘
              │ 成功
              ↓
┌────────────────────────────────────────────────────────────────────┐
│  状态：MQTT_LOGIN                                                   │
├────────────────────────────────────────────────────────────────────┤
│  等待：连接回调触发 mqtt_cloud_connect_handle()                    │
│  超时：20 秒未收到回调 → 转到 MQTT_CONNECT (重连)                  │
│  喂狗：每 30 秒更新 wdt_tick                                        │
└────────────────────────────────────────────────────────────────────┘
              │ 回调触发
              ↓
┌────────────────────────────────────────────────────────────────────┐
│  回调：mqtt_cloud_connect_handle()                                 │
├────────────────────────────────────────────────────────────────────┤
│  1. 检查 result 参数 (0=成功)                                      │
│  2. report_message.conn_flag = NETWORK_STATE_SUCC                  │
│  3. 记录重连停止时间：reconn_time.time_stop                        │
│  4. mqtt_subscribe(mosq, mqtt_server)                             │
│      └─ 调用 dmpcu_topic_subscribe()                              │
│           ├─ 订阅网关主题：                                        │
│           │   $sys/{PK}/{DK}/ext/register_reply                   │
│           │   $sys/{PK}/{DK}/property/post_reply                  │
│           │   $sys/{PK}/{DK}/property/set                         │
│           │   $sys/{PK}/{DK}/service/invoke                       │
│           │   ... (共 15+ 个主题)                                  │
│           └─ 订阅子设备主题 (循环 subdeviceNum)                    │
│  5. change_run_status(MQTT_DATA)                                  │
│  6. 写连接标志文件：CONNECTED_FLAG                                 │
│  7. 保存设备凭证到文件 (首次连接):                                 │
│      deviceKey|token → DMPCU_DEVICE_TOKEN                         │
└────────────────────────────────────────────────────────────────────┘
              │
              ↓
┌────────────────────────────────────────────────────────────────────┐
│  状态：MQTT_DATA                                                    │
├────────────────────────────────────────────────────────────────────┤
│  执行：直接转到 MQTT_DEVINFO                                        │
└────────────────────────────────────────────────────────────────────┘
              │
              ↓
┌────────────────────────────────────────────────────────────────────┐
│  状态：MQTT_DEVINFO  (核心业务状态)                                │
├────────────────────────────────────────────────────────────────────┤
│  循环执行：                                                         │
│    1. report_devicestatus_message()      # 设备状态上报            │
│    2. if (alarm_flag == 1):                                        │
│         report_alarm_message()           # 告警上报                │
│    3. if (定时器到期):                                             │
│         report_interval_message()        # 定时数据上报            │
│         report_deviceinfo_message()      # 设备信息上报            │
│    4. 每 30 秒喂狗：wdt_tick = COMM_get_uptime()                   │
│                                                                    │
│  并发执行：                                                         │
│    mosquitto_loop(mosq, 1000, 1)        # 处理网络 I/O             │
│      ├─ 接收消息 → receive_message_handle()                       │
│      ├─ 发送心跳                                                   │
│      └─ 处理 ACK                                                   │
└────────────────────────────────────────────────────────────────────┘
              │ 如果 loop 返回错误
              ↓
┌────────────────────────────────────────────────────────────────────┐
│  状态：MQTT_RECONNECT_WAIT                                          │
├────────────────────────────────────────────────────────────────────┤
│  执行：等待 reconnect_interval 秒                                   │
│  期间：每 30 秒喂狗                                                 │
│  处理：调用 dmpcu_subdevice_reconnect_init()  # 重置子设备状态     │
│  转换：超时后 → MQTT_INIT (重新初始化)                             │
└────────────────────────────────────────────────────────────────────┘
              │
              ↓
┌────────────────────────────────────────────────────────────────────┐
│  状态：MQTT_RECONNECT                                               │
├────────────────────────────────────────────────────────────────────┤
│  执行：mosquitto_reconnect(mosq)                                    │
│  策略：每 RECONNECT_EXPIREDTIME 秒尝试一次                          │
│  结果：                                                             │
│    ├─ 成功 → 回到 MQTT_LOGIN 状态                                 │
│    └─ 失败 → 继续等待下次重连                                      │
└────────────────────────────────────────────────────────────────────┘
```

---

## 4. 设备认证流程（三种模式）

### 4.1 一机一密认证 (authType=0)

```
设备启动
   │
   ↓
读取配置文件
   ├─ productKey (产品标识)
   ├─ deviceName (设备名称)
   ├─ deviceSecret (设备密钥，预先分配)
   └─ authType = 0
   │
   ↓
dmpcu_device_init()
   │
   └─ 判断 authType == 0
       │
       ↓
   dmpcu_device_online_request()
       ├─ 构造登录消息：
       │   {
       │     "productKey": "xxx",
       │     "deviceName": "xxx",
       │     "sign": SHA256(productKey+deviceName+deviceSecret+timestamp),
       │     "timestamp": 1234567890,
       │     "signMethod": "sha256"
       │   }
       ├─ 发布到主题：$sys/{PK}/{DK}/ext/login
       └─ 等待响应：$sys/{PK}/{DK}/ext/login_reply
           │
           ↓
       云平台校验
           ├─ 验证签名
           └─ 返回：{"code": 200, "token": "xxx"}
           │
           ↓
       保存 token 到文件
       设置 onlineState = 100 (在线)
```

### 4.2 一型一密预注册 (authType=1)

```
设备启动
   │
   ↓
读取配置文件
   ├─ productKey (产品标识)
   ├─ productSecret (产品密钥，同一型号共享)
   ├─ deviceName (设备名称)
   └─ authType = 1
   │
   ↓
dmpcu_device_init()
   │
   └─ 判断 authType == 1
       │
       ├─ if (onlineState == 1):   # 首次启动，需要注册
       │   │
       │   ↓
       │   dmpcu_device_online_regist()
       │       ├─ 构造注册消息：
       │       │   {
       │       │     "productKey": "xxx",
       │       │     "deviceName": "xxx",
       │       │     "sign": SHA256(productKey+deviceName+productSecret+timestamp)
       │       │   }
       │       ├─ 发布到：$sys/{PK}/{DK}/ext/register
       │       └─ 等待响应：$sys/{PK}/{DK}/ext/register_reply
       │           │
       │           ↓
       │       云平台返回：
       │           {"code": 200, "deviceSecret": "yyy", "token": "zzz"}
       │           │
       │           ↓
       │       保存 deviceSecret 和 token 到文件
       │       设置 onlineState = 3
       │
       └─ if (onlineState == 3):   # 已注册，直接登录
           │
           ↓
           dmpcu_device_online_request()  # 同一机一密流程
```

### 4.3 一型一密免预注册 (authType=2)

```
设备启动
   │
   ↓
读取配置文件
   ├─ productKey
   ├─ productSecret
   ├─ deviceKey (如未配置，自动获取 IMEI)
   └─ authType = 2
   │
   ↓
获取 deviceKey (如为空)
   ├─ 读取 /tmp/device.info 中的 IMEI
   └─ deviceKey = IMEI
   │
   ↓
dmpcu_device_init()
   │
   └─ 判断 authType == 2
       │
       ├─ if (onlineState == 1):   # 首次启动，自动注册
       │   │
       │   ↓
       │   dmpcu_device_online_autoregist()
       │       ├─ 构造注册消息：
       │       │   {
       │       │     "productKey": "xxx",
       │       │     "deviceKey": "IMEI123456",
       │       │     "sign": SM3(productKey+deviceKey+productSecret+timestamp)
       │       │   }
       │       ├─ 发布到：$sys/{PK}/{DK}/ext/autoRegister
       │       └─ 等待响应：$sys/{PK}/{DK}/ext/autoRegister_reply
       │           │
       │           ↓
       │       云平台自动创建设备：
       │           {"code": 200, "token": "zzz"}
       │           │
       │           ↓
       │       保存 deviceKey|token 到文件
       │       设置 onlineState = 3
       │
       └─ if (onlineState == 3):   # 已注册，二次上线
           │
           ↓
           dmpcu_device_online_request()
               ├─ authType = -2  (特殊标记)
               └─ 使用 token 直接登录
```

---

## 5. 数据上报完整流程

```
┌─────────────────────────────────────────────────────────────────┐
│  数据源：数据库 / 本地采集                                        │
└─────────────────────────────────────────────────────────────────┘
              │
              │ 数据产生
              ↓
┌─────────────────────────────────────────────────────────────────┐
│  数据库回调：data_cb()                                            │
│  ├─ 获取 data_format_st 数据                                     │
│  ├─ database_data_ref()  (引用计数+1)                            │
│  ├─ 判断数据类型：                                                │
│  │   ├─ 告警数据 → publish_type_alarm()                          │
│  │   │              └─ 加入 alarm_list 链表                      │
│  │   └─ 普通数据 → publish_message_prepare()                     │
│  │                  └─ 加入 report_list 链表                     │
│  └─ database_data_unref()  (引用计数-1)                          │
└─────────────────────────────────────────────────────────────────┘
              │
              │ 数据在链表中缓存
              ↓
┌─────────────────────────────────────────────────────────────────┐
│  MQTT_DEVINFO 状态定时触发                                        │
│  ├─ report_alarm_message()  (如有告警)                           │
│  │   ├─ 从 alarm_list 取数据                                     │
│  │   ├─ 组装 JSON：                                              │
│  │   │   {                                                       │
│  │   │     "id": "123",                                          │
│  │   │     "params": {                                           │
│  │   │       "alarmType": "temperature",                         │
│  │   │       "alarmLevel": 2,                                    │
│  │   │       "alarmValue": 85.5,                                 │
│  │   │       "timestamp": 1234567890                             │
│  │   │     }                                                     │
│  │   │   }                                                       │
│  │   ├─ 调用 mqtt_message_publish()                              │
│  │   └─ 发布到：$sys/{PK}/{DK}/event/post                        │
│  │                                                               │
│  └─ report_interval_message()  (定时上报)                        │
│      ├─ 从 report_list 取数据 (批量 upload_nums 条)              │
│      ├─ 组装批量 JSON：                                           │
│      │   {                                                       │
│      │     "id": "456",                                          │
│      │     "params": {                                           │
│      │       "properties": {                                     │
│      │         "temperature": 25.5,                              │
│      │         "humidity": 60.0,                                 │
│      │         "voltage": 220.0                                  │
│      │       }                                                   │
│      │     }                                                     │
│      │   }                                                       │
│      ├─ 调用 mqtt_message_publish()                              │
│      └─ 发布到：$sys/{PK}/{DK}/property/batch_post               │
└─────────────────────────────────────────────────────────────────┘
              │
              ↓
┌─────────────────────────────────────────────────────────────────┐
│  mqtt_message_publish()                                          │
│  ├─ 参数检查：mosq, buf, len, topic, qos                         │
│  ├─ 调用：mosquitto_publish(mosq, &mid, topic, len, buf, qos)   │
│  ├─ 记录日志：topic, mid, qos, buf, result                       │
│  └─ 返回结果                                                      │
└─────────────────────────────────────────────────────────────────┘
              │
              ↓
┌─────────────────────────────────────────────────────────────────┐
│  mosquitto_loop() 处理发送                                        │
│  ├─ 将消息加入发送队列                                            │
│  ├─ 通过 TCP Socket 发送 MQTT PUBLISH 报文                       │
│  └─ 根据 QoS 等待 ACK：                                           │
│      ├─ QoS 0：不等待                                            │
│      ├─ QoS 1：等待 PUBACK                                       │
│      └─ QoS 2：等待 PUBREC → PUBREL → PUBCOMP                    │
└─────────────────────────────────────────────────────────────────┘
              │
              ↓
┌─────────────────────────────────────────────────────────────────┐
│  云平台接收并响应                                                 │
│  ├─ 解析 JSON                                                    │
│  ├─ 存储到数据库                                                  │
│  └─ 发送响应：$sys/{PK}/{DK}/property/batch_post_reply            │
│      {                                                           │
│        "id": "456",                                              │
│        "code": "000000",                                         │
│        "message": "success"                                      │
│      }                                                           │
└─────────────────────────────────────────────────────────────────┘
              │
              ↓
┌─────────────────────────────────────────────────────────────────┐
│  设备接收响应：receive_message_handle()                           │
│  ├─ mosquitto_loop() 收到消息触发回调                             │
│  ├─ 调用 receive_cloudmsg_parse()                                │
│  ├─ 根据 topic 解析：                                             │
│  │   └─ property/batch_post_reply → 解析 code 字段               │
│  └─ 处理结果：                                                    │
│      ├─ 成功 (code=000000)：从链表删除已上报数据                 │
│      └─ 失败：记录日志，重试或丢弃                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. 属性下发与服务调用流程

```
云平台下发指令
   │
   ↓
┌─────────────────────────────────────────────────────────────────┐
│  场景 1：属性设置                                                 │
│  Topic: $sys/{PK}/{DK}/property/set                              │
│  Payload:                                                        │
│    {                                                             │
│      "id": "789",                                                │
│      "params": {                                                 │
│        "ReportInterval": 60,                                     │
│        "LEDStatus": 1                                            │
│      }                                                           │
│    }                                                             │
└─────────────────────────────────────────────────────────────────┘
   │
   ↓
┌─────────────────────────────────────────────────────────────────┐
│  设备接收：receive_message_handle()                               │
│  ├─ 解析 topic：匹配 "property/set"                               │
│  ├─ 调用 cuiot_property_set_parse()                              │
│  │   ├─ 解析 JSON 中的 params                                    │
│  │   └─ for each property:                                      │
│  │       ├─ 查找对应的 set 函数                                  │
│  │       ├─ 参数类型校验                                          │
│  │       ├─ 调用 set_func()                                      │
│  │       │   └─ 写入配置文件 / 调用系统接口                       │
│  │       └─ 记录设置结果                                          │
│  │                                                               │
│  └─ 组装响应：                                                    │
│      {                                                           │
│        "id": "789",                                              │
│        "code": 200,                                              │
│        "data": {                                                 │
│          "ReportInterval": 0,  // 0=成功                         │
│          "LEDStatus": 0                                          │
│        }                                                         │
│      }                                                           │
│  └─ 发布到：$sys/{PK}/{DK}/property/set_reply                    │
└─────────────────────────────────────────────────────────────────┘

---

云平台调用服务
   │
   ↓
┌─────────────────────────────────────────────────────────────────┐
│  场景 2：服务调用（以重启为例）                                    │
│  Topic: $sys/{PK}/{DK}/service/invoke                            │
│  Payload:                                                        │
│    {                                                             │
│      "id": "1001",                                               │
│      "service": "Rebot",                                         │
│      "params": {                                                 │
│        "DelayTime": 5                                            │
│      }                                                           │
│    }                                                             │
└─────────────────────────────────────────────────────────────────┘
   │
   ↓
┌─────────────────────────────────────────────────────────────────┐
│  设备接收：receive_message_handle()                               │
│  ├─ 解析 topic：匹配 "service/invoke"                             │
│  ├─ 调用 cuiot_service_invoke_parse()                            │
│  │   ├─ 解析 JSON 中的 service 字段："Rebot"                      │
│  │   ├─ 在 g_service_function[] 查找对应服务                     │
│  │   ├─ 解析 params：{"DelayTime": 5}                            │
│  │   ├─ 调用 set_func_reboot()                                   │
│  │   │   ├─ 参数校验：DelayTime = 5                              │
│  │   │   ├─ 执行：system("sleep 5 && reboot &")                  │
│  │   │   └─ 返回：0 (成功)                                       │
│  │   └─ 记录结果                                                 │
│  │                                                               │
│  └─ 组装响应：                                                    │
│      {                                                           │
│        "id": "1001",                                             │
│        "code": 200,                                              │
│        "data": {                                                 │
│          "Rebot_Response": 0  // 0=成功                          │
│        }                                                         │
│      }                                                           │
│  └─ 发布到：$sys/{PK}/{DK}/service/invoke_reply                  │
└─────────────────────────────────────────────────────────────────┘
   │
   ↓
设备重启 (5秒后)
```

---

## 7. 子设备管理流程

```
网关启动并连接成功
   │
   ↓
解析子设备配置
   ├─ subdeviceInfo 数组
   ├─ 每个子设备：productKey, deviceName, deviceKey, deviceSecret
   └─ 子设备数量：subdeviceNum
   │
   ↓
订阅子设备相关主题
   ├─ $sys/{GW_PK}/{GW_DK}/topo/add_reply          # 添加子设备响应
   ├─ $sys/{GW_PK}/{GW_DK}/topo/login_reply        # 子设备登录响应
   ├─ $sys/{GW_PK}/{GW_DK}/topo/logout_reply       # 子设备登出响应
   └─ for each 子设备:
       ├─ $sys/{SUB_PK}/{SUB_DK}/property/batch_post_reply
       ├─ $sys/{SUB_PK}/{SUB_DK}/property/set
       └─ $sys/{SUB_PK}/{SUB_DK}/event/post_reply
   │
   ↓
┌─────────────────────────────────────────────────────────────────┐
│  流程 1：添加子设备到网关拓扑                                      │
│  (首次使用或子设备更新时)                                          │
├─────────────────────────────────────────────────────────────────┤
│  网关发送：                                                       │
│    Topic: $sys/{GW_PK}/{GW_DK}/topo/add                          │
│    Payload:                                                      │
│      {                                                           │
│        "id": "1234",                                             │
│        "params": [                                               │
│          {                                                       │
│            "productKey": "SUB_PK",                               │
│            "deviceName": "SUB_DN",                               │
│            "deviceKey": "SUB_DK",                                │
│            "deviceSecret": "SUB_DS",                             │
│            "sign": SHA256(...)                                   │
│          }                                                       │
│        ]                                                         │
│      }                                                           │
│  云平台响应：                                                     │
│    Topic: $sys/{GW_PK}/{GW_DK}/topo/add_reply                    │
│    Payload:                                                      │
│      {                                                           │
│        "id": "1234",                                             │
│        "code": 200,                                              │
│        "data": [...]                                             │
│      }                                                           │
└─────────────────────────────────────────────────────────────────┘
   │
   ↓
┌─────────────────────────────────────────────────────────────────┐
│  流程 2：子设备登录                                                │
├─────────────────────────────────────────────────────────────────┤
│  触发条件：                                                       │
│    ├─ 网关启动后                                                  │
│    ├─ 网关重连后                                                  │
│    └─ 定时检查子设备状态                                          │
│                                                                  │
│  网关发送 (批量登录):                                              │
│    Topic: $sys/{GW_PK}/{GW_DK}/topo/batchLogin                   │
│    Payload:                                                      │
│      {                                                           │
│        "id": "2345",                                             │
│        "params": [                                               │
│          {                                                       │
│            "productKey": "SUB_PK_1",                             │
│            "deviceKey": "SUB_DK_1",                              │
│            "timestamp": 1234567890,                              │
│            "sign": SHA256(...)                                   │
│          },                                                      │
│          {                                                       │
│            "productKey": "SUB_PK_2",                             │
│            "deviceKey": "SUB_DK_2",                              │
│            "timestamp": 1234567890,                              │
│            "sign": SHA256(...)                                   │
│          }                                                       │
│        ]                                                         │
│      }                                                           │
│  云平台响应：                                                     │
│    Topic: $sys/{GW_PK}/{GW_DK}/topo/batchLogin_reply             │
│    Payload:                                                      │
│      {                                                           │
│        "id": "2345",                                             │
│        "code": 200,                                              │
│        "data": [                                                 │
│          {"deviceKey": "SUB_DK_1", "result": 0},                │
│          {"deviceKey": "SUB_DK_2", "result": 0}                 │
│        ]                                                         │
│      }                                                           │
│  设备更新状态：                                                   │
│    subdevice[i].onlineState = 1 (在线)                           │
└─────────────────────────────────────────────────────────────────┘
   │
   ↓
┌─────────────────────────────────────────────────────────────────┐
│  流程 3：子设备数据上报                                            │
├─────────────────────────────────────────────────────────────────┤
│  网关代理上报 (使用子设备的 PK/DK):                                │
│    Topic: $sys/{SUB_PK}/{SUB_DK}/property/batch_post             │
│    Payload:                                                      │
│      {                                                           │
│        "id": "3456",                                             │
│        "params": {                                               │
│          "temperature": 28.5,                                    │
│          "humidity": 65.0                                        │
│        }                                                         │
│      }                                                           │
│  云平台响应：                                                     │
│    Topic: $sys/{SUB_PK}/{SUB_DK}/property/batch_post_reply       │
│    Payload:                                                      │
│      {                                                           │
│        "id": "3456",                                             │
│        "code": "000000"                                          │
│      }                                                           │
└─────────────────────────────────────────────────────────────────┘
   │
   ↓
┌─────────────────────────────────────────────────────────────────┐
│  流程 4：子设备登出                                                │
├─────────────────────────────────────────────────────────────────┤
│  触发条件：                                                       │
│    ├─ 配置中启用自动登出：subdevicelogoutSet = 1                  │
│    ├─ 超时时间：subdevicelogintime (秒)                           │
│    └─ 网关断线前主动登出                                          │
│                                                                  │
│  网关发送：                                                       │
│    Topic: $sys/{GW_PK}/{GW_DK}/topo/batchLogout                  │
│    Payload:                                                      │
│      {                                                           │
│        "id": "4567",                                             │
│        "params": [                                               │
│          {"productKey": "SUB_PK_1", "deviceKey": "SUB_DK_1"},   │
│          {"productKey": "SUB_PK_2", "deviceKey": "SUB_DK_2"}    │
│        ]                                                         │
│      }                                                           │
│  云平台响应：                                                     │
│    Topic: $sys/{GW_PK}/{GW_DK}/topo/batchLogout_reply            │
│    Payload: {"id": "4567", "code": 200}                         │
│  设备更新状态：                                                   │
│    subdevice[i].onlineState = 0 (离线)                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. 异常处理与重连机制

```
┌─────────────────────────────────────────────────────────────────┐
│  正常运行中 (MQTT_DEVINFO 状态)                                   │
└─────────────────────────────────────────────────────────────────┘
              │
              ↓
     mosquitto_loop(mosq, 1000, 1)
              │
              ├─ 返回 0：正常
              │   └─ 继续运行
              │
              └─ 返回非 0：异常
                  │
                  ↓
┌─────────────────────────────────────────────────────────────────┐
│  异常检测与处理                                                   │
├─────────────────────────────────────────────────────────────────┤
│  if (loop_ret != G3_SUCCEED):                                    │
│    1. 设置网络状态：report_message.conn_flag = NETWORK_STATE_FAIL│
│    2. 记录断线时间：reconn_time.time_start = get_timestamp()     │
│    3. 删除连接标志文件：unlink(CONNECTED_FLAG)                    │
│    4. 重置子设备状态：dmpcu_subdevice_reconnect_init()           │
│       └─ 所有子设备 onlineState = 0                              │
│    5. 触发断线回调：mqtt_cloud_disconnect_handle()               │
│    6. 设置重连标志：isreconnect = 1                              │
│    7. 状态转换：change_run_status(MQTT_RECONNECT_WAIT)          │
└─────────────────────────────────────────────────────────────────┘
              │
              ↓
┌─────────────────────────────────────────────────────────────────┐
│  MQTT_RECONNECT_WAIT 状态                                        │
├─────────────────────────────────────────────────────────────────┤
│  等待策略：                                                       │
│    ├─ 等待时间：reconnect_interval 秒 (配置文件指定)              │
│    ├─ 期间喂狗：每 30 秒更新 wdt_tick                             │
│    └─ 日志输出：下次重连倒计时                                    │
│                                                                  │
│  超时后：                                                         │
│    └─ change_run_status(MQTT_INIT)  # 回到初始化状态             │
└─────────────────────────────────────────────────────────────────┘
              │
              ↓
┌─────────────────────────────────────────────────────────────────┐
│  MQTT_INIT → MQTT_CONNECT                                        │
├─────────────────────────────────────────────────────────────────┤
│  重新初始化：                                                     │
│    ├─ mosquitto_username_pw_set()  (重新设置凭证)                │
│    ├─ mosquitto_connect()          (重新连接)                    │
│    └─ 连接成功 → MQTT_LOGIN → MQTT_DATA → MQTT_DEVINFO          │
└─────────────────────────────────────────────────────────────────┘
              │
              ↓
┌─────────────────────────────────────────────────────────────────┐
│  连接恢复后的处理                                                 │
├─────────────────────────────────────────────────────────────────┤
│  1. 记录重连成功时间：reconn_time.time_stop                       │
│  2. 计算断线时长：time_stop - time_start                          │
│  3. 重新订阅所有主题：dmpcu_topic_subscribe()                     │
│  4. 网关重新认证 (如需要)                                         │
│  5. 子设备批量重新登录：                                          │
│     └─ 发送 topo/batchLogin 消息                                 │
│  6. 恢复数据上报                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9. 线程间交互与同步

```
┌────────────────────────────────────────────────────────────────┐
│                          主线程                                  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  cuiotCloud()                                             │ │
│  │  └─ while(1):                                            │ │
│  │      ├─ sub_thread_monitor()  # 监控所有子线程           │ │
│  │      │   └─ 检查 wdt_tick 超时 (> 2*30秒 = 60秒)        │ │
│  │      └─ soft_watchdog_feed()  # 喂主线程看门狗           │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
              │
              │ 创建并监控
              ↓
┌────────────────────────────────────────────────────────────────┐
│  子线程 1: mqtt_new_handle()                                    │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  功能：MQTT 连接与消息收发                                │ │
│  │  看门狗喂狗：                                             │ │
│  │    mqtt_server->wdt_tick = COMM_get_uptime()  (每30秒)   │ │
│  │  与其他线程交互：                                         │ │
│  │    ├─ 读取：report_message.alarm_list (告警队列)         │ │
│  │    ├─ 读取：report_message.report_list (数据队列)        │ │
│  │    ├─ 写入：report_message.conn_flag (连接状态)          │ │
│  │    └─ 互斥锁：pthread_mutex_lock(&report_message.datalock)│ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│  子线程 2: report_message_strategy_handle()                     │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  功能：数据上报策略管理                                   │ │
│  │  数据来源：                                                │ │
│  │    └─ database_register() 注册回调 data_cb()             │ │
│  │  数据流向：                                                │ │
│  │    ├─ data_cb() 接收数据                                 │ │
│  │    ├─ publish_type_alarm() → alarm_list                  │ │
│  │    └─ publish_message_prepare() → report_list            │ │
│  │  互斥锁：                                                  │ │
│  │    └─ pthread_mutex_lock(&report_message.datalock)       │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│  子线程 3: mqtt_new_handle_getInfo()                            │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  功能：独立的设备信息查询连接                             │ │
│  │  特点：                                                    │ │
│  │    ├─ 独立的 mosquitto 实例 (mosq_getInfo)               │ │
│  │    ├─ 独立的状态机 (getInfo_status)                       │ │
│  │    └─ 不影响主连接的性能                                  │ │
│  │  看门狗喂狗：                                             │ │
│  │    mqtt_server->wdt_tick = COMM_get_uptime()             │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘

共享数据结构：
┌────────────────────────────────────────────────────────────────┐
│  report_message_st (全局变量)                                   │
│  ├─ conn_flag         : 网络连接状态                           │
│  ├─ alarm_flag        : 告警标志                               │
│  ├─ datalock          : pthread_mutex_t 互斥锁                 │
│  ├─ report_list       : 数据上报链表                           │
│  ├─ alarm_list        : 告警消息链表                           │
│  ├─ report_data       : 实时数据链表                           │
│  └─ report_data_rt    : 实时数据备份链表                       │
└────────────────────────────────────────────────────────────────┘
```

---

## 10. 配置文件结构与解析流程

```json
{
  "server": {
    "server1": {
      "protocol": "dmpcu",
      "ip": "mqtt.cuiot.cn",
      "port": 1883,
      "param": {
        "clientid": "device_12345",
        "usrname": "deviceName&productKey",
        "passwd": "签名字符串",
        "uploadsec": 30,
        "heartbeat": 60,
        "qos": 1,
        "upload_nums": 50,
        "report_interval": 60,
        "reconnect_interval": 10,
        "tls": {
          "disable": false,
          "version": "tlsv1.2",
          "ca_path": "/etc/certs/ca.crt",
          "client_pem": "/etc/certs/client.pem",
          "client_key": "/etc/certs/client.key"
        },
        "deviceInfo": {
          "productKey": "ABC123",
          "deviceName": "Gateway001",
          "deviceKey": "IMEI123456789",
          "deviceSecret": "secret123",
          "productSecret": "psecret456",
          "token": "",
          "authType": "2",
          "signMethod": "0",
          "operator": "0",
          "subdevicelogoutSet": "1",
          "subdevicelogintime": "600"
        },
        "subdeviceInfo": [
          {
            "productKey": "SUB_PK_1",
            "deviceName": "Sensor001",
            "deviceKey": "SUB_DK_1",
            "deviceSecret": "sub_secret_1",
            "authType": "0",
            "signMethod": "0"
          },
          {
            "productKey": "SUB_PK_2",
            "deviceName": "Sensor002",
            "deviceKey": "SUB_DK_2",
            "deviceSecret": "sub_secret_2",
            "authType": "1",
            "signMethod": "0"
          }
        ]
      }
    }
  }
}
```

**解析流程：**
```
mqtt_parse_project()
  ├─ json_parse_file_with_comments(PROJECT_CONFIG_FILE)
  ├─ 提取 root["server"]
  └─ for each server (server1, server2, ...):
      │
      └─ parse_server_configuration()
          ├─ 基础配置：ip, port, protocol
          ├─ parse_param_configuration()
          │   ├─ clientid, usrname, passwd
          │   ├─ uploadsec, heartbeat, qos
          │   ├─ upload_nums, report_interval
          │   └─ reconnect_interval
          ├─ parse_tlsparam_configuration()
          │   └─ 解析 TLS 配置
          └─ dmpcu_parse_data()
              ├─ 解析 deviceInfo (网关配置)
              │   ├─ productKey, deviceName
              │   ├─ deviceKey, deviceSecret
              │   ├─ token, authType, signMethod
              │   └─ subdevicelogoutSet, subdevicelogintime
              └─ 解析 subdeviceInfo[] (子设备数组)
                  └─ for each 子设备:
                      ├─ productKey, deviceName
                      ├─ deviceKey, deviceSecret
                      └─ authType, signMethod
```

---

## 总结

本文档详细描绘了 CUIOT MQTT 项目的核心流程和架构，包括：

1. **项目整体架构**：主线程 + 3 个子线程
2. **系统启动流程**：从初始化到运行的完整链路
3. **MQTT 连接状态机**：7 个状态的转换逻辑
4. **三种设备认证模式**：一机一密、一型一密预注册、一型一密免预注册
5. **数据上报机制**：从数据库 → 链表缓存 → MQTT 发送
6. **属性下发与服务调用**：云平台控制设备的流程
7. **子设备管理**：添加、登录、上报、登出的完整流程
8. **异常处理与重连**：断线检测、重连策略、状态恢复
9. **线程间交互**：看门狗、互斥锁、共享数据结构
10. **配置文件解析**：JSON 结构与解析流程

配合《CUIOT_MQTT项目深度学习方案_自下而上.md》学习文档使用，可快速掌握整个项目的运行机制。

