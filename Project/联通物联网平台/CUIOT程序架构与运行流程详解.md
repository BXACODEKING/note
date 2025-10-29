# CUIOT 程序架构与运行流程详解

## 一、总体架构概览

### 1.1 架构图
```
┌─────────────────────────────────────────────────────────────────┐
│                        Main Entry Point                         │
│                     cuiotCloud() 主线程                          │
└──────────────────────┬──────────────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │  初始化阶段 (Initialization) │
        └──────────────┬──────────────┘
                       │
        ┌──────────────┴────────────────────────┐
        │                                        │
   ┌────▼─────┐                          ┌──────▼──────┐
   │ 基础初始化 │                         │ 服务初始化   │
   └────┬─────┘                          └──────┬──────┘
        │                                        │
        │ mqtt_cloud_init()                      │ cuiot_service_init()
        │ dmpcu_init()                           │
        │ mqtt_parse_project()                   │
        └────────────────┬───────────────────────┘
                         │
                    ┌────▼─────┐
                    │ 线程创建  │
                    └────┬─────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   ┌────▼────┐    ┌──────▼───────┐  ┌───▼─────────┐
   │ GetInfo │    │ MQTT主线程   │  │ Report线程  │
   │ 线程     │    │              │  │             │
   └────┬────┘    └──────┬───────┘  └───┬─────────┘
        │                │              │
        │          ┌─────▼─────┐       │
        │          │ 订阅Topic  │       │
        │          │ 接收消息   │       │
        │          └─────┬─────┘       │
        │                │              │
        └────────────────┼──────────────┘
                         │
                    ┌────▼─────┐
                    │ 稳定运行  │
                    └──────────┘
```

### 1.2 核心组件
| 组件 | 文件 | 功能 |
|------|------|------|
| 主控制器 | `mqtt_dmpcudata.c` | CUIOT协议主逻辑 |
| MQTT引擎 | `mqttCloud.c` | MQTT连接管理 |
| 数据解析 | `mqtt_parsedata.c` | 配置文件解析 |
| 数据上报 | `mqtt_reportdata.c` | 数据上报策略 |
| 属性管理 | `cuiot_property_get.c` | 属性采集 |
| 服务管理 | `cuiot_sevice.c` | 服务下发处理 |
| 工具函数 | `cuiot_utils.c` | 通用工具 |

---

## 二、程序启动与初始化流程

### 2.1 主入口函数：`cuiotCloud()`
**文件：** `mqtt_dmpcudata.c:107`

```c
void cuiotCloud(void *param)
{
    bool thread_valid;
    
    // 1. 启动线程环境
    sal_thread_start();
    sal_thread_cleanup_push(clean_function_dmpcu, mqtt_server_group);
    
    // 2. 打印版本信息
    msg(M_INFO, "[%s]%s plib run", PLIB_NAME, DMPCU_PROTOCOL_NAME);
    plib_version(DMPCU_PROTOCOL_NAME, LIB_VERSION);
    
    // 3. 基础初始化
    mqtt_cloud_init();      // 初始化互斥锁
    dmpcu_init();           // 初始化DMPCU特定配置
    
    // 4. 清空全局数据结构
    memset(mqtt_server_group, 0, sizeof(mqtt_server_group));
    memset(&dmpcu_device_config, 0, sizeof(dmpcu_device_config_st));
    loginin_time = 0;
    
    // 5. 解析配置文件并创建线程
    mqtt_parse_project(mqtt_server_group, PROJECT_CONFIG_FILE);
    
    // 6. 主循环：监控子线程健康状态
    while(1) {
        msleep(100);
        thread_valid = (bool)sub_thread_monitor(mqtt_server_group);
        
        if (thread_valid)
            soft_watchdog_feed(get_threadid());  // 喂狗
    }
    
    sal_thread_cleanup_pop(1);
    sal_thread_exit();
}
```

### 2.2 初始化详细步骤

#### 2.2.1 `mqtt_cloud_init()` - 基础初始化
**文件：** `mqttCloud.c:74`
```c
void mqtt_cloud_init(void)
{
    // 初始化上报消息的互斥锁
    pthread_mutex_init(&report_message.datalock, NULL);
}
```

#### 2.2.2 `dmpcu_init()` - DMPCU特定初始化
**文件：** `mqtt_dmpcudata.c:76`

**核心功能：**
1. **解析设备Token文件路径**
   ```c
   strncpy(project_config_file, PROJECT_CONFIG_FILE, sizeof(project_config_file));
   pos = strrchr(project_config_file, '/');
   if(pos) {
       *pos = '\0';
       snprintf(device_token, sizeof(device_token), "%s/%s", 
                project_config_file, "mqtt_cuiot_deviceToken.para");
       snprintf(device_key, sizeof(device_key), "%s/%s", 
                project_config_file, "mqtt_cuiot_subdeviceToken.para");
       DMPCU_DEVICE_TOKEN = strdup(device_token);
       DMPCU_DEVICE_KEY = strdup(device_key);
   }
   ```

2. **初始化服务功能表**
   ```c
   cuiot_service_init();  // 初始化19个服务功能
   ```

**关键修复点：**
- `g_service_function` 数组**不能**声明为 `const`
- 原因：初始化时需要动态分配 `param_list` 内存并赋值
- 声明为 `const` 会导致段错误（写入只读内存）

#### 2.2.3 `cuiot_service_init()` - 服务初始化
**文件：** `cuiot_sevice.c:1793`

**初始化的19个服务：**
```c
service_function_t g_service_function[T_MAX_F] = {
    {T_Reboot_F, ...},              // 0. 网关重启
    {T_Firmware_F, ...},            // 1. 固件升级
    {T_ParameterWAN_F, ...},        // 2. WAN参数配置
    {T_ParameterLAN_F, ...},        // 3. LAN参数配置
    {T_ParameterModem_F, ...},      // 4. Modem参数配置
    {T_Parameter5GLANModem_F, ...}, // 5. 5G LAN配置
    {T_ParameterWIFI24_F, ...},     // 6. WiFi 2.4G配置
    {T_ParameterWIFI5_F, ...},      // 7. WiFi 5G配置
    {T_ParameterICMP_F, ...},       // 8. ICMP配置
    {T_ParameterNTP_F, ...},        // 9. NTP配置
    {T_Reset_F, ...},               // 10. 恢复出厂设置
    {T_DNAT_F, ...},                // 11. DNAT配置
    {T_MASQ_F, ...},                // 12. MASQ配置
    {T_ParameterLOG_F, ...},        // 13. 日志配置
    {T_ParameterVLAN_F, ...},       // 14. VLAN配置
    {T_ParameterVXLAN_F, ...},      // 15. VXLAN配置
    {T_Ping_F, ...},                // 16. Ping测试
    {T_TraceRoute_F, ...},          // 17. TraceRoute测试
    {T_Lock_F, ...}                 // 18. 锁定功能
};

for (int i = 0; i < T_MAX_F; i++) {
    res = g_service_function[i].init_func(&g_service_function[i]);
    if (-1 == res) break;
}
```

**每个服务初始化做什么：**
- 分配参数列表内存：`calloc(sizeof(service_param_t) * params)`
- 设置参数ID和类型：`strdup(id)`
- 分配参数值内存：`calloc(data_size)`

#### 2.2.4 `mqtt_parse_project()` - 配置解析与线程创建
**文件：** `mqtt_parsedata.c:14`

**解析流程：**
```
1. 读取配置文件 (PROJECT_CONFIG_FILE)
   ↓
2. 解析JSON格式配置
   {
     "server": {
       "cuiot": {
         "protocol": "dmpcu",
         "address": "xxx.xxx.xxx.xxx",
         "port": 1883,
         "param": { ... },
         "tls": { ... }
       }
     }
   }
   ↓
3. 填充 mqtt_server_group[] 数组
   ├─ 服务器地址、端口
   ├─ 客户端ID、用户名、密码
   ├─ Topic配置
   ├─ 上报间隔、QoS等参数
   └─ 设备信息（productKey, deviceKey等）
   ↓
4. 创建GetInfo线程
   pthread_create(&tid_mqtt_getInfo, NULL, mqtt_new_handle_getInfo, ...)
```

##### **配置示例：**

```json
"server": {
        "cuiot": {
            "description": "",
            "protocol": "cuiotCloud",
            "host": "dmp-mqtt.cuiot.cn",
            "port": 1883,
            "param": {
                "client_id": "",
                "qos": 0,
                "keepalive": 30,
                "reconnect_time": 5,
                "report_interval":60,
                "mqtt_version": 0,
                "publish": "",
                "subscribe": "",
                "alarm_publish": "",
                "history_data_publish": "",
                "package_nums": 10,
                "package_limitedtime": 5,
                "pkey": "Z1NRXL2507291914",
                "gatewayInfo": {
                    "productKey": "cu4ss7hvdmubgtzf",
                    "deviceKey": "IsvFDsXAVs1zSHb",
                    "productSecret": "1065089c0ef35c20d87fd521d35b2093",
                    "deviceSecret": "989041A88FC77A2A37678E589AD6E4D4",
                    "token": "None",
                    "productName": "Z1",
                    "deviceName": "Z1TEST",
                    "authType": "2",
                    "signMethod": "0",
                    "operator": "0",
                    "logoutSet": "0",
                    "loginTime": "10"
                },
                "username": "",
                "password": "",
                "tls": {
                    "disable": true
                }
            },
            "upload": {
                "mode": 2,
                "period": 30
            }
        }
    }
```

---

## 三、线程模型详解

### 3.1 线程架构图
```
                    ┌───────────────────┐
                    │  主线程 (Main)     │
                    │  cuiotCloud()      │
                    └─────────┬─────────┘
                              │
                              │ 创建并监控
            ┌─────────────────┼─────────────────┐
            │                 │                 │
            │                 │                 │
    ┌───────▼────────┐ ┌──────▼──────┐  ┌──────▼────────┐
    │ GetInfo线程    │ │ MQTT线程     │  │ Report线程     │
    │ (认证/获取信息) │ │ (消息收发)   │  │ (数据上报)     │
    └───────┬────────┘ └──────┬──────┘  └──────┬────────┘
            │                 │                 │
            │                 │                 │
      ┌─────▼─────┐    ┌──────▼───────┐ ┌──────▼─────┐
      │设备认证    │    │订阅Topic     │ │采集数据    │
      │获取Token   │    │接收下发      │ │打包上报    │
      │完成后退出  │    │心跳保活      │ │策略管理    │
      └───────────┘    └──────────────┘ └────────────┘
```

### 3.2 线程1：GetInfo线程 - 设备认证与信息获取

**文件：** `mqttCloud.c:502`  
**函数：** `mqtt_new_handle_getInfo()`

#### 3.2.1 线程状态机
```
MQTT_INIT
   ↓
MQTT_CONNECTING (连接MQTT服务器)
   ↓
MQTT_CONNECTED (连接成功，订阅认证Topic)
   ↓
MQTT_GETINFO (等待认证响应)
   ↓
MQTT_IDEL (认证完成，创建主线程)
```

#### 3.2.2 详细流程
```c
void *mqtt_new_handle_getInfo(void *arg)
{
    mqtt_para_st *mqtt_server = arg;
    
    // 1. 检查是否已有Token
    if (dmpcu_device_config.authType >= 1)
        token_get_ret = dmpcu_device_token_get(DMPCU_DEVICE_TOKEN, 
                                                dmpcu_device_config.deviceKey,
                                                dmpcu_device_config.token, 
                                                sizeof(dmpcu_device_config.token));
    
    // 2. 如果已有Token，直接创建主线程
    if (1 == token_get_ret) {
        mqtt_server->getInfo_success = 2;
        change_run_getInfo_status(mqtt_server, MQTT_IDEL);
        
        // 创建主业务线程
        pthread_create(&mqtt_server->tid_mqtt, NULL, mqtt_new_handle, mqtt_server);
        pthread_create(&mqtt_server->tid_report, NULL, report_message_strategy_handle, mqtt_server);
        return NULL;
    }
    
    // 3. 无Token，需要进行设备认证
    mosquitto_lib_init();
    mosq_getInfo = mosquitto_new(mqtt_server->ctx->client_id, true, NULL);
    
    // 4. 设置回调
    mosquitto_user_data_set(mosq_getInfo, mqtt_server);
    mosquitto_message_callback_set(mosq_getInfo, receive_message_handle_getInfo);
    mosquitto_connect_callback_set(mosq_getInfo, mqtt_cloud_connect_handle_getInfo);
    
    // 5. 状态机循环
    while(1) {
        switch(mqtt_server->getInfo_status) {
            case MQTT_INIT:
                // 初始化完成，准备连接
                change_run_getInfo_status(mqtt_server, MQTT_CONNECTING);
                break;
                
            case MQTT_CONNECTING:
                // 连接MQTT服务器
                ret = mosquitto_connect(mosq_getInfo, 
                                       mqtt_server->ctx->address, 
                                       mqtt_server->ctx->port, 60);
                if (ret == MOSQ_ERR_SUCCESS) {
                    change_run_getInfo_status(mqtt_server, MQTT_CONNECTED);
                }
                break;
                
            case MQTT_CONNECTED:
                // 订阅认证相关Topic
                dmpcu_device_regist_subscribe_getInfo(mosq_getInfo, mqtt_server);
                // 发送认证请求
                dmpcu_device_regist_publish(mosq_getInfo, mqtt_server);
                change_run_getInfo_status(mqtt_server, MQTT_GETINFO);
                break;
                
            case MQTT_GETINFO:
                // 等待认证响应（在消息回调中处理）
                if (mqtt_server->getInfo_success == 1) {
                    // 认证成功，断开连接
                    mosquitto_disconnect(mosq_getInfo);
                    mqtt_server->getInfo_success = 2;
                    change_run_getInfo_status(mqtt_server, MQTT_IDEL);
                }
                break;
                
            case MQTT_IDEL:
                // 认证完成，创建主业务线程
                if (mqtt_server->getInfo_success == 2) {
                    dmpcu_device_config.onlineState = 3;
                    dmpcu_device_init(mqtt_server);
                    
                    pthread_create(&mqtt_server->tid_mqtt, NULL, 
                                 mqtt_new_handle, mqtt_server);
                    pthread_create(&mqtt_server->tid_report, NULL, 
                                 report_message_strategy_handle, mqtt_server);
                    
                    mqtt_server->getInfo_success = 3;
                }
                // 定期喂狗
                current_time = get_uptime();
                if(current_time - watchdog_tick >= 30) {
                    watchdog_tick = get_uptime();
                    mqtt_server->wdt_tick = COMM_get_uptime();
                }
                break;
        }
        
        // MQTT事件循环
        mosquitto_loop(mosq_getInfo, 10, 1);
        msleep(100);
    }
}
```

**认证流程示意：**
```
设备                                      平台
  │                                        │
  │ ── 发送认证请求 ──────────────────────→ │
  │    Topic: $sys/{pk}/{dk}/ext/regist    │
  │    Payload: { productKey, deviceName } │
  │                                        │
  │ ←─ 返回Token ─────────────────────────│
  │    Topic: $sys/{pk}/{dk}/ext/regist_reply
  │    Payload: { token, code }            │
  │                                        │
  │ ── 保存Token到文件 ────────────────────│
  │    /etc/config/industry/mqtt_cuiot_deviceToken.para
  │                                        │
  │ ── 创建主业务线程 ─────────────────────│
  │                                        │
```

### 3.3 线程2：MQTT主线程 - 消息收发

**文件：** `mqttCloud.c:299`  
**函数：** `mqtt_new_handle()`

#### 3.3.1 线程状态机
```
MQTT_INIT
   ↓
MQTT_CONNECTING (连接中)
   ↓
MQTT_CONNECTED (已连接，订阅Topic)
   ↓
[稳定运行] ←──┐
   │          │
   ↓          │
MQTT_RECONNECT (断线重连)
   └──────────┘
```

#### 3.3.2 详细流程
```c
void *mqtt_new_handle(void *arg)
{
    mqtt_para_st *mqtt_server = arg;
    
    // 1. 初始化
    sal_thread_start();
    sal_thread_cleanup_push(clean_function, NULL);
    mqtt_server->status = MQTT_INIT;
    
    // 2. 创建Mosquitto实例
    mosquitto_lib_init();
    mosq = mosquitto_new(mqtt_server->ctx->client_id, true, NULL);
    mqtt_server->mosq = mosq;
    
    // 3. 设置回调函数
    mosquitto_user_data_set(mosq, mqtt_server);
    mosquitto_message_callback_set(mosq, receive_message_handle);
    mosquitto_log_callback_set(mosq, mqtt_cloud_log_handle);
    mosquitto_connect_callback_set(mosq, mqtt_cloud_connect_handle);
    mosquitto_disconnect_callback_set(mosq, mqtt_cloud_disconnect_handle);
    mosquitto_subscribe_callback_set(mosq, mqtt_cloud_subscribe_handle);
    mosquitto_publish_callback_set(mosq, mqtt_cloud_publish_handle);
    
    // 4. 主循环
    while(1) {
        msleep(100);
        current_time = get_uptime();
        
        switch(mqtt_server->status) {
            case MQTT_INIT:
                // 初始化完成，准备连接
                change_run_status(mqtt_server, MQTT_CONNECTING);
                break;
                
            case MQTT_CONNECTING:
                // 尝试连接MQTT服务器
                mosquitto_ret = mosquitto_connect(mosq, 
                                                 mqtt_server->ctx->address,
                                                 mqtt_server->ctx->port, 60);
                if (mosquitto_ret == MOSQ_ERR_SUCCESS) {
                    change_run_status(mqtt_server, MQTT_CONNECTED);
                    login_time = current_time;
                }
                break;
                
            case MQTT_CONNECTED:
                // 订阅所有需要的Topic
                mqtt_subscribe(mosq, mqtt_server);
                
                // 上报设备信息
                mqtt_publish_devinfo_message(&report_message, mosq, mqtt_server);
                
                // 上报设备状态
                mqtt_publish_devstatus_message(&report_message, mosq, mqtt_server);
                
                // 定期心跳
                if(current_time - report_tick >= mqtt_server->ctx->heartbeat) {
                    report_tick = current_time;
                    mqtt_publish_heartbeat_message(&report_message, mosq, mqtt_server);
                }
                
                // 定期喂狗
                if(current_time - watchdog_tick >= mqtt_server->softdog_interval) {
                    watchdog_tick = current_time;
                    mqtt_server->wdt_tick = COMM_get_uptime();
                }
                break;
                
            case MQTT_RECONNECT:
                // 断线重连
                mosquitto_disconnect(mosq);
                msleep(mqtt_server->ctx->reconnect_interval * 1000);
                change_run_status(mqtt_server, MQTT_CONNECTING);
                break;
        }
        
        // MQTT事件循环
        loop_ret = mosquitto_loop(mosq, 10, 1);
        if (loop_ret != MOSQ_ERR_SUCCESS) {
            change_run_status(mqtt_server, MQTT_RECONNECT);
        }
    }
}
```

#### 3.3.3 订阅的Topic列表
**函数：** `dmpcu_topic_subscribe()` - `mqtt_dmpcudata.c`

```c
订阅的Topic格式：$sys/{productKey}/{deviceKey}/{suffix}

1. ext/regist_reply         - 设备注册应答
2. ext/auto_regist_reply    - 自动注册应答
3. topo/add_reply           - 拓扑添加应答
4. topo/delete_reply        - 拓扑删除应答
5. topo/batch_add_reply     - 批量添加应答
6. property/batch_reply     - 属性批量上报应答
7. event/batch_reply        - 事件批量上报应答
8. service/pub              - 服务下发（异步）
9. sync/pub                 - 服务下发（同步）
10. property/set            - 属性设置

网关订阅：$sys/{productKey}/{deviceKey}/#
子设备订阅：$sys/{productKey}/+/#
```

### 3.4 线程3：Report线程 - 数据上报策略

**文件：** `mqtt_reportdata.c:130`  
**函数：** `report_message_strategy_handle()`

#### 3.4.1 数据上报机制
```
┌─────────────────────────┐
│  数据采集（各协议插件）   │
│  database_register()     │
└──────────┬──────────────┘
           │
           │ 回调
           ▼
┌──────────────────────────┐
│  data_cb() 数据处理回调   │
│  ├─ 数据引用计数管理      │
│  ├─ 区分告警/普通数据     │
│  └─ 调用策略处理          │
└──────────┬───────────────┘
           │
           ▼
┌─────────────────────────┐
│ publish_message_prepare()│
│  数据上报策略处理         │
└──────────┬──────────────┘
           │
    ┌──────┴──────┐
    │             │
    ▼             ▼
┌────────┐   ┌─────────┐
│原始上报 │   │间隔上报  │
│立即发送 │   │缓存合并  │
└────────┘   └─────────┘
```

#### 3.4.2 数据上报策略
**1. 策略类型：**
- `policy_original` - 原始上报：数据到达立即上报
- `policy_change` - 变化上报：数据变化时上报
- `policy_interval` - 间隔上报：按时间间隔批量上报（默认）

**2. 间隔上报流程：**
```c
publish_type_interval(report_msg, data_pointer)
   ↓
1. 查找设备是否已在缓存列表中
   list_for_each_entry_safe(report_node, n, &report_msg->report_data, list)
   ↓
2. 如果已存在，更新数据
   update_to_report_record_list(ptr, data_pointer)
   ↓
3. 如果不存在，添加到列表
   add_to_list(&report_msg->report_data, data_pointer, sizeof(data_format_st))
   ↓
4. 定时触发上报（在MQTT主线程中）
   if(current_time - report_tick >= mqtt_server->ctx->upload_sec) {
       mqtt_publish_interval_message(&report_message, mosq, mqttserver);
   }
```

**3. 实时数据上报：**
```c
publish_type_rt(report_msg, data_pointer)
   ↓
1. 维护实时数据列表
   &report_msg->report_data_rt
   ↓
2. 立即触发上报
   report_rt_message(report_msg, mosq, mqttserver)
```

---

## 四、消息处理流程

### 4.1 下行消息处理流程图
```
MQTT Broker
     │
     │ Publish Message
     ▼
mosquitto_message_callback
     │
     ▼
receive_message_handle()
     │
     ▼
receive_cloudmsg_parse()
     │
     ├─ 通用配置？→ dpuc_config_parse_project()
     │
     └─ DMPCU协议？→ dmpcu_receive_msg_parse()
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
   ext/regist      service/pub      property/set
   认证应答         服务下发          属性设置
        │                │                │
        ▼                ▼                ▼
   保存Token      cuiot_set_propety() 设置属性值
                  执行服务逻辑      上报设置结果
```

### 4.2 下行消息类型详解

#### 4.2.1 设备认证应答 - `ext/regist_reply`
**Topic:** `$sys/{productKey}/{deviceKey}/ext/regist_reply`

**处理函数：** `dmpcu_parse_device_regist()`

**消息格式：**
```json
{
  "code": "000000",
  "message": "Success",
  "data": {
    "productKey": "cu10x0wd72sk56jf",
    "deviceKey": "2jZA855df8t9jCD",
    "token": "a1b2c3d4e5f6g7h8"
  }
}
```

**处理流程：**
```c
1. 解析JSON获取 token
2. 保存到本地文件
   dmpcu_file_write(DMPCU_DEVICE_TOKEN, 
                    "deviceKey:token\n", 
                    offset, strlen(msg))
3. 更新设备在线状态
   dmpcu_device_config.onlineState = 2
4. 触发GetInfo线程完成认证流程
   mqttserver->getInfo_success = 1
```

#### 4.2.2 服务下发 - `service/pub` (异步)
**Topic:** `$sys/{productKey}/{deviceKey}/service/pub`

**处理函数：** `cuiot_set_propety()` - `cuiot_property_set.c`

**消息格式：**
```json
{
  "messageId": "12345",
  "params": {
    "identifier": "Rebot",           // 服务标识
    "Rebot": "restart_now"            // 服务参数
  }
}
```

**处理流程：**
```c
1. 解析消息ID和服务标识
   cJSON_GetObjectItem(root, "messageId")
   cJSON_GetObjectItem(params, "identifier")

2. 查找对应的服务处理函数
   service_type = cuiot_get_service_type(identifier)
   sft = &g_service_function[service_type]

3. 解析服务参数
   cuiot_get_service_parameters(sft, params)

4. 执行服务处理函数
   sft->set_func(&private_param, sft, cmd, len)
   例如：set_func_reboot() - 执行重启命令

5. 生成响应消息
   reply = reply_func_general(sft, mid, res)

6. 发送响应
   mqtt_message_publish(mosq, out_data, strlen(out_data), 
                       reply_topic, qos)
   Topic: $sys/{pk}/{dk}/service/pub_reply
```

**服务处理示例 - 重启服务：**
```c
static int set_func_reboot(service_private_param_t *private_param,
                          service_function_t *sft, 
                          char *cmd, size_t len)
{
    // 1. 验证参数
    if (sft->param_list[0].param_value) {
        char *reboot_cmd = (char *)sft->param_list[0].param_value;
        
        // 2. 执行重启命令
        if (strcmp(reboot_cmd, "restart_now") == 0) {
            system("reboot");
            return 0;
        }
    }
    return -1;
}
```

#### 4.2.3 属性设置 - `property/set`
**Topic:** `$sys/{productKey}/{deviceKey}/property/set`

**消息格式：**
```json
{
  "messageId": "67890",
  "params": {
    "wan_enable": 1,
    "wan_ipaddr": "192.168.1.100"
  }
}
```

**处理流程：**
```c
1. 解析属性键值对
2. 调用系统接口设置属性
3. 生成响应并上报
   Topic: $sys/{pk}/{dk}/property/set_reply
```

### 4.3 上行消息处理流程

#### 4.3.1 属性上报 - `cuiot_public_propety()`
**文件：** `cuiot_property_get.c:3357`

**触发时机：**
- 定时上报（每60秒）
- 设备状态变化
- 平台主动查询

**上报流程：**
```c
int cuiot_public_propety(struct mosquitto *mosq, mqtt_para_st* mqttserver)
{
    // 1. 创建JSON根对象
    root = cJSON_CreateObject();
    
    // 2. 添加messageId
    srand(COMM_GetTime());
    sprintf(messageId, "%d", rand());
    cJSON_AddStringToObject(root, "messageId", messageId);
    
    // 3. 创建params对象和data数组
    params = cJSON_CreateObject();
    data = cJSON_CreateArray();
    cJSON_AddItemToObject(root, "params", params);
    cJSON_AddItemToObject(params, "data", data);
    
    // 4. 根据系统类型选择采集列表
    if (is_opensdt_system()) {
        // OpenSDT系统配置列表
        for(int i = 0; i < sizeof(g_cuiot_list_osdt)/sizeof(g_cuiot_list_osdt[0]); i++) {
            if(g_cuiot_list_osdt[i].cb) {
                // 调用各个属性采集函数
                g_cuiot_list_osdt[i].cb(mosq, mqttserver);
            }
        }
    } else {
        // 标准系统配置列表
        for(int i = 0; i < sizeof(g_cuiot_list)/sizeof(g_cuiot_list[0]); i++) {
            if(g_cuiot_list[i].cb) {
                g_cuiot_list[i].cb(mosq, mqttserver);
            }
        }
    }
    
    // 5. 序列化JSON并发送
    out_data = cJSON_Print(root);
    dmpcu_topic_packet(topic, DMPCU_TOPIC_SYS, 
                      dmpcu_device_config.productKey, 
                      dmpcu_device_config.deviceKey, 
                      DMPCU_TOPIC_PROPATCH);
    mqtt_message_publish(mosq, out_data, strlen(out_data), topic, qos);
    
    // 6. 清理资源
    cJSON_Delete(root);
    free(out_data);
    
    return E_OK;
}
```

**属性采集列表（OpenSDT系统）：**
```c
cuiot_info_st g_cuiot_list_osdt[] = {
    {"basic"     , basic_info      },  // 基本信息（SN、MAC等）
    {"time"      , time_info       },  // 时间信息
    {"load"      , load_aver_info  },  // 负载信息
    {"memory"    , memory_info     },  // 内存信息
    {"cpu"       , cpu_info        },  // CPU信息
    {"temp"      , temp_info       },  // 温度信息
    {"state"     , state_info      },  // 运行状态
    {"network"   , network_info    },  // 网络接口信息
    {"lan"       , lan_info        },  // LAN配置
    {"gps"       , gps_info        },  // GPS信息
    {"modem"     , osdt_modem_info },  // Modem信息
    {"apn"       , osdt_apn_info   },  // APN配置
    {"dhcp"      , osdt_dhcp_info  },  // DHCP信息
    {"uci"       , uci_info        },  // UCI配置
    {"cli_lan"   , cli_lan_info    },  // CLI LAN配置
    {"cli_rule"  , osdt_uci_rule   },  // UCI规则
};
```

**单个属性采集示例 - Modem信息：**
```c
void osdt_modem_info(struct mosquitto *mosq, mqtt_para_st* mqttserver)
{
    // 1. 初始化设备信息结构
    cuiot_devinfo_st cuiot_modem_info[] = {
        {"modem_enable"    , NULL, cuiot_string, NULL, cuiot_modem_enable   , NULL},
        {"modem_model"     , NULL, cuiot_string, NULL, cuiot_modem_model    , NULL},
        {"modem_imei"      , NULL, cuiot_string, NULL, cuiot_modem_imei     , NULL},
        {"modem_iccid"     , NULL, cuiot_string, NULL, cuiot_modem_iccid    , NULL},
        {"modem_imsi"      , NULL, cuiot_string, NULL, cuiot_modem_imsi     , NULL},
        {"modem_csq"       , NULL, cuiot_int32 , NULL, cuiot_modem_csq      , NULL},
        {"modem_network"   , NULL, cuiot_string, NULL, cuiot_modem_network  , NULL},
        // ... 更多字段
    };
    
    // 2. 获取Modem数量
    int len = sizeof(cuiot_modem_info) / sizeof(cuiot_modem_info[0]);
    
    // 3. 调用采集函数初始化数据
    for (int i = 0; i < modem_count; i++) {
        for (int j = 0; j < len; j++) {
            if(cuiot_modem_info[j].init_cb) {
                cuiot_modem_info[j].init_cb(&cuiot_modem_info[j], common);
            }
        }
        
        // 4. 发布采集到的数据
        if(cuiot_modem_info[j].data) {
            cuiot_public_propety_pub(mosq, mqttserver, &cuiot_modem_info, j);
        }
    }
}
```

**数据发布函数：**
```c
void cuiot_public_propety_pub(struct mosquitto *mosq, 
                              mqtt_para_st* mqttserver,
                              cuiot_devinfo_st *devinfo, 
                              int i)
{
    // 1. 检查全局root对象
    if (root == NULL) return;
    
    // 2. 获取data数组
    cJSON *params = cJSON_GetObjectItem(root, "params");
    cJSON *data = cJSON_GetObjectItem(params, "data");
    
    // 3. 创建单个属性对象
    param_json = cJSON_CreateObject();
    cJSON_AddStringToObject(param_json, "key", devinfo[i].name);
    
    // 4. 根据数据类型添加value
    switch (devinfo[i].type) {
        case cuiot_int32:
            cJSON_AddNumberToObject(param_json, "value", atoi(devinfo[i].data));
            break;
        case cuiot_string:
            cJSON_AddStringToObject(param_json, "value", devinfo[i].data);
            break;
        // ... 其他类型
    }
    
    // 5. 添加到data数组
    cJSON_AddItemToArray(data, param_json);
}
```

**上报消息格式：**
```json
{
  "messageId": "123456",
  "params": {
    "data": [
      {"key": "sn", "value": "SN20250101001"},
      {"key": "mac", "value": "00:11:22:33:44:55"},
      {"key": "modem_enable", "value": "1"},
      {"key": "modem_csq", "value": 25},
      {"key": "wan_ipaddr", "value": "192.168.1.100"}
    ]
  }
}
```

**Topic:** `$sys/{productKey}/{deviceKey}/property/batch`

---

## 五、关键数据结构

### 5.1 MQTT服务器参数 - `mqtt_para_st`
```c
typedef struct {
    // 线程ID
    pthread_t tid_mqtt;           // MQTT主线程
    pthread_t tid_report;         // 数据上报线程
    pthread_t tid_mqtt_getInfo;   // GetInfo线程
    
    // MQTT实例
    struct mosquitto *mosq;
    
    // 连接信息
    connect_info_st *ctx;         // 服务器配置
    char server_name[64];         // 服务器名称
    char protocol_name[64];       // 协议名称
    int protocol;                 // 协议类型
    
    // 状态
    int status;                   // MQTT状态
    int getInfo_status;           // GetInfo状态
    int getInfo_success;          // GetInfo成功标志
    
    // 定时器
    uint32_t wdt_tick;            // 看门狗时间戳
    uint32_t softdog_interval;    // 看门狗间隔
    
    // 标志
    bool valid_flag;              // 有效标志
} mqtt_para_st;
```

### 5.2 设备配置 - `dmpcu_device_config_st`
```c
typedef struct {
    // 网关信息
    char productKey[32];          // 产品Key
    char deviceName[64];          // 设备名称
    char deviceKey[32];           // 设备Key
    char token[128];              // 认证Token
    
    // 认证方式
    int authType;                 // 0:一机一密 1:一型一密 2:动态注册
    int onlineState;              // 在线状态
    
    // 子设备信息
    int subdeviceNum;             // 子设备数量
    int subdeviceCheck;           // 子设备校验方式
    struct {
        char productKey[32];
        char deviceName[64];
        char deviceKey[32];
        char token[128];
        int authType;
        int onlineState;
    } subdevice[MAX_SUBDEVICE];
} dmpcu_device_config_st;
```

### 5.3 服务功能表 - `service_function_t`
```c
typedef struct service_function_struct {
    f_type_t func_type;                    // 服务类型
    d_type_t reply_type;                   // 响应数据类型
    char *func_id;                         // 服务标识
    int param_count;                       // 参数数量
    service_param_t *param_list;           // 参数列表（动态分配）
    char *reply_id;                        // 响应标识
    
    // 函数指针
    int (*init_func)(struct service_function_struct *sfs);      // 初始化函数
    int (*set_func)(service_private_param_t *private_param,
                   struct service_function_struct *sfs, 
                   char *cmd, size_t len);                      // 设置函数
    int (*reply_func)(struct service_function_struct *sfs);     // 响应函数
} service_function_t;
```

---

## 六、运行时序图

### 6.1 完整启动时序
```
时间轴 →
───┬────────────────────────────────────────────────────────────
   │
 0s│ ■ cuiotCloud() 启动
   │   └─ mqtt_cloud_init()
   │   └─ dmpcu_init()
   │       └─ cuiot_service_init()  [初始化19个服务]
   │   └─ mqtt_parse_project()
   │       └─ 创建 GetInfo线程 ━━┓
   │                              ┃
 1s│                              ┃ GetInfo线程运行
   │                              ┃ ├─ 连接MQTT
   │                              ┃ ├─ 订阅认证Topic
   │                              ┃ ├─ 发送认证请求
   │                              ┃ └─ 等待Token
 2s│                              ┃
   │                              ┃ 收到Token响应
   │                              ┃ ├─ 保存Token
   │                              ┃ ├─ 断开连接
   │                              ┃ └─ 创建主线程 ━━┳━━ MQTT主线程
   │                              ┃                 ┃   ├─ 连接MQTT
 3s│                              ┃                 ┃   ├─ 订阅业务Topic
   │                              ┃                 ┃   ├─ 上报设备信息
   │                              ┗━ (空闲状态)     ┃   └─ 开始心跳
   │                                                ┃
   │                                                ┣━━ Report线程
 4s│                                                ┃   ├─ 注册数据回调
   │                                                ┃   └─ 等待数据采集
   │                                                ┃
   │ ┌────────────  稳定运行阶段  ────────────┐   ┃
   │ │                                         │   ┃
60s│ │  定时上报属性（每60秒）                 │   ┃
   │ │    ↓                                    │   ┃
   │ │  cuiot_public_propety()                 │   ┃
   │ │    ├─ 采集basic                         │   ┃
   │ │    ├─ 采集modem                         │   ┃
   │ │    ├─ 采集network                       │   ┃
   │ │    └─ 发送到平台                        │   ┃
   │ │                                         │   ┃
   │ │  心跳保活（每30秒）                     │   ┃
   │ │    ↓                                    │   ┃
   │ │  mqtt_publish_heartbeat_message()       │   ┃
   │ │                                         │   ┃
   │ │  接收平台下发                           │   ┃
   │ │    ↓                                    │   ┃
   │ │  receive_message_handle()               │   ┃
   │ │    └─ dmpcu_receive_msg_parse()         │   ┃
   │ │        ├─ service/pub → 执行服务        │   ┃
   │ │        └─ property/set → 设置属性       │   ┃
   │ └─────────────────────────────────────────┘   ┃
   │                                                ┃
```

### 6.2 属性上报详细时序
```
Report线程      MQTT线程         平台
    │              │              │
    │ 采集数据      │              │
    │──────────────▶│              │
    │ data_cb()     │              │
    │              │              │
    │ 缓存数据      │              │
    │ (间隔策略)    │              │
    │              │              │
    ├─ 60秒到 ─────▶│              │
    │              │              │
    │              │ 组装JSON     │
    │              │ cuiot_public_propety()
    │              │              │
    │              │ 发送 ────────▶│
    │              │              │
    │              │◀─── 应答 ─────│
    │              │              │
```

### 6.3 服务下发处理时序
```
平台           MQTT线程        服务处理
 │               │              │
 │ service/pub   │              │
 │──────────────▶│              │
 │               │              │
 │               │ 解析消息     │
 │               │ cuiot_set_propety()
 │               │              │
 │               │ 查找服务 ────▶│
 │               │              │
 │               │              │ cuiot_get_service_type()
 │               │              │ g_service_function[type]
 │               │              │
 │               │              │ 执行服务
 │               │◀─── 结果 ────│
 │               │              │
 │               │ 生成响应     │
 │◀── reply ─────│              │
 │               │              │
```

---

## 七、关键配置文件

### 7.1 主配置文件 - `project_conf.json`
**路径：** `/etc/config/industry/project_conf.json`

```json
{
  "server": {
    "cuiot": {
      "protocol": "dmpcu",
      "address": "mqtt.cloud.example.com",
      "port": 1883,
      "param": {
        "client_id": "device_${SN}",
        "username": "device_user",
        "password": "device_password",
        "qos": 1,
        "upload_sec": 60,
        "heartbeat": 30,
        "upload_nums": 50,
        "report_interval": 60,
        "reconnect_interval": 10,
        "deviceInfo": {
          "productKey": "cu10x0wd72sk56jf",
          "deviceName": "gateway_001",
          "deviceKey": "2jZA855df8t9jCD",
          "deviceSecret": "",
          "authType": 1,
          "subdeviceCheck": 0
        },
        "subdeviceInfo": [
          {
            "productKey": "sub_product_001",
            "deviceName": "子设备1",
            "deviceKey": "sub_device_key_001",
            "authType": 2
          }
        ],
        "tls": {
          "enable": 0,
          "ca_file": "/etc/ssl/ca.crt",
          "cert_file": "/etc/ssl/client.crt",
          "key_file": "/etc/ssl/client.key"
        }
      }
    }
  }
}
```

### 7.2 Token存储文件
**路径：** `/etc/config/industry/mqtt_cuiot_deviceToken.para`

```
格式：deviceKey:token

2jZA855df8t9jCD:a1b2c3d4e5f6g7h8i9j0
sub_device_key_001:k1l2m3n4o5p6q7r8s9t0
```

---

## 八、故障处理与调试

### 8.1 常见问题排查

#### 问题1：段错误（Segmentation Fault）
**现象：** 程序启动时崩溃
**原因：** `g_service_function` 被声明为 `const`
**解决：** 去掉 `const` 关键字
```c
// 错误
const service_function_t g_service_function[T_MAX_F] = { ... };

// 正确
service_function_t g_service_function[T_MAX_F] = { ... };
```

#### 问题2：无法连接MQTT服务器
**排查步骤：**
1. 检查网络连通性：`ping mqtt.cloud.example.com`
2. 检查端口开放：`telnet mqtt.cloud.example.com 1883`
3. 查看日志：`/var/log/mqtt.log`
4. 检查配置文件：`cat /etc/config/industry/project_conf.json`

#### 问题3：属性上报失败
**排查步骤：**
1. 检查MQTT连接状态
2. 检查Topic订阅是否成功
3. 检查数据采集函数是否正常
4. 查看JSON格式是否正确

### 8.2 调试方法

#### 方法1：添加调试日志
```c
printf("[DEBUG] %s/%d: 变量名=%值\n", __FUNCTION__, __LINE__, var);
fflush(stdout);  // 立即刷新输出
```

#### 方法2：使用msg日志系统
```c
msg(M_INFO, "信息日志");
msg(M_DEBU, "调试日志");
msg(M_ERRO, "错误日志");
```

#### 方法3：GDB调试
```bash
# 编译时添加调试信息
make CFLAGS="-g -O0"

# 启动GDB
gdb ./ppe1
(gdb) run
(gdb) bt     # 查看堆栈
(gdb) p var  # 打印变量
```

---

## 九、性能优化建议

### 9.1 内存优化
- 及时释放不用的内存
- 使用对象池减少频繁分配
- 定期检查内存泄漏

### 9.2 网络优化
- 合并多个小消息
- 使用QoS 1（至少一次）
- 启用消息压缩

### 9.3 CPU优化
- 减少不必要的JSON解析
- 使用缓存避免重复计算
- 优化循环逻辑

---

## 十、总结

CUIOT程序采用**多线程架构**，通过**状态机驱动**实现稳定的MQTT通信：

1. **初始化阶段**：加载配置、初始化服务、创建线程
2. **认证阶段**：GetInfo线程获取设备Token
3. **连接阶段**：主线程连接MQTT服务器并订阅Topic
4. **运行阶段**：周期性采集数据上报，接收平台下发并处理
5. **容错机制**：断线自动重连、看门狗监控、异常恢复

整个架构**清晰分层**、**职责明确**、**易于扩展**，是典型的IoT设备端程序设计范例。

