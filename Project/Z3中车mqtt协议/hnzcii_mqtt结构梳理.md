## 1. 总体结构概览
- 入口 `hnzciiCloud()` 驱动整个 hnzcii MQTT 服务。该入口由框架加载后运行，负责初始化通信线程、解析项目配置、注册 MQTT 服务器对象，并维持主线程看门狗。
- 主要数据结构：
  - `mqtt_para_st`：框架定义的 MQTT 连接上下文，保存 `mosquitto` 客户端句柄、历史上报配置、回调函数集合、看门狗时间戳等。
  - `hnzcii_info_t`：hnzcii 客制化私有数据，包含 `hnzcii_config_t`（UserID/ProductID/EquipID）及 `report_status` 状态机（空闲/实时/历史）。
  - `report_message_st`（框架提供）：缓存最新采样数据、历史补传队列、网络状态标志等。
- 服务分为五条核心链路：配置与 Topic、MQTT 订阅与指令处理、实时上报、历史补传、看门狗/清理。以下按线程生命周期梳理。

## 2. 入口初始化与主循环
1. `sal_thread_start()` 启动通信用 sal 线程环境，同时注册 `clean_function()` 作为线程退出清理钩子（调用 `clear_thread_source(HNZCII_PROTOCOL_NAME)`）。
2. 初始化 `mqtt_para_st servers[MQTT_MAX_NUMS]`，对每个实例注册回调：
   - `prepare_func = hnzcii_parse_config`
   - `package_func = hnzcii_realtime_data_publish`
   - `parse_func = hnzcii_receive_msg_parse`
   - `extern_func = hnzcii_history_data_info`
   - `sub_func = hnzcii_mqtt_subscribe`
3. `mqtt_parse_project()` 读取 `PROJECT_CONFIG_FILE`，填充服务器数量与基础参数。
4. 为每个有效 server 申请 `hnzcii_info_t`，保存到 `mqtt_para_st.private`，并通过 `mqtt_register_object()` 注册至框架，之后由框架拉起独立的连接/上报线程。
5. 主线程进入看门狗循环：每秒扫描所有 server，如果 `COMM_get_uptime() - wdt_tick > 3 * softdog_interval` 则判定线程异常；只要无异常就调用 `soft_watchdog_feed()` 喂狗，保障进程常驻。

## 3. 配置解析与 Topic 体系
### 3.1 `hnzcii_parse_config()`
- 从项目配置 JSON (`OBJ_PARAM`) 读取：
  - `UserID` / `ProductID` / `EquipID` → 存入 `hnzcii_info->config`。
  - `history_report_enable` / `history_report_mode` → 写入 `mqtt_para_st`，历史模式 0 默认改为 3。
  - 历史模式影响实时/历史互斥：当 `history_mode == 2` 且历史线程在发数据时，实时上报会被抑制。
- 同步打印配置和 `report_interval` 以便诊断。

### 3.2 Topic 生成 `hnzcii_topic_packet()`
- 根据 Topic 类型编号拼接：`<业务前缀>/<UserID>/<ProductID>/<EquipID>`。
- 支持 6 类：实时 (`Dev/Status`)、批量 (`Dev/BatchStatus`)、读写请求/应答 (`Dev/Attr/R/W/(Req|Res)`)，所有发/订阅都通过此函数统一拼 Topic，避免硬编码。

## 4. MQTT 订阅与指令处理
### 4.1 订阅
- `hnzcii_mqtt_subscribe()` 在连接建立后由框架调用，订阅：
  - 读指令 `Dev/Attr/R/Req/...`
  - 写指令 `Dev/Attr/W/Req/...`
- QoS 使用 `mqttserver->ctx.qos` 配置值。

### 4.2 消息解析 `hnzcii_receive_msg_parse()`
1. 使用 `parson` 将 payload 解析为 JSON。
2. 根据 Topic 中 `/R/Req/` 或 `/W/Req/` 判断命令类型：
   - **读指令**：`hnzcii_parse_read_cmd()`
     - 读取 `uuid`、`Content` 中请求的变量列表。
     - 通过 `get_record_data(&mqttserver->report_message, &blk_vc)` 获取最新采样缓存，按 variable_name 匹配填值；未命中则填空字符串并置 `ErrCode = -1`。
     - 构造应答 JSON（`uuid`、`deviceID`、`ErrCode`、`Content`），再通过 `hnzcii_topic_packet(..., READ_RES)` 发布。
   - **写指令**：`hnzcii_parse_write_cmd()`
     - 解析 `Content` 数组，逐项写入：通过 `database_get_node()` 申请缓冲，将 name/value 填入 `data_format_st`，写入头部 `data_store_to_head()`。
     - 等待 `mqttserver->report_message.response`（底层回写结果），最多 10 秒超时；结果映射为 `0/ -1 /9`。
     - `hnzcii_create_write_response()` 汇总 `ErrCode`（全成功=0，全超时=9，部分成功=1，其余=-1），`Content` 中给出逐项结果，再通过写应答 Topic 发送。
3. JSON 对象释放，确保不泄露。

## 5. 实时数据上报链路
### 5.1 `hnzcii_realtime_data_publish()`
- 由框架定时触发 `package_func`：
  1. 若 `report_status == report_history` 且 `history_mode == 2`（历史优先）则直接返回失败，防止历史/实时并发冲突。
  2. 设置状态为 `report_real`，调用 `hnzcii_create_realtime_data()` 生成 payload。
  3. 通过 `hnzcii_topic_packet(..., STATUS)` 得到 Topic 后调用 `mqtt_message_publish()`。
  4. 发布成功则返回 `E_OK`；失败则置 `report_message.conn_flag = NETWORK_STATE_FAIL`，驱动上层重连。
  5. 最后恢复 `report_status = report_idle`。

### 5.2 JSON 打包 `hnzcii_create_realtime_data()`
- `get_record_data()` 读取 `report_message` 中最新采样记录（向量 `blk_vc`），对每个 `data_format_st`：
  - 第一条记录的 `unix_timestamp` 作为整个报文的时间基准。
  - 尝试将 `variable_value` 转为浮点，否则按字符串写入。
- 额外添加 `TIMESTAMP_LOCAL`（格式 `%Y-%m-%d %H:%M:%S`），满足 hnzcii 平台要求。
- 使用 `cJSON_Print` 输出扁平 JSON，外部负责释放。

## 6. 历史补传链路
### 6.1 启动条件 `hnzcii_history_data_info()`
- 若 `history_enable` 为真且 `reconn_time.time_start != time_stop`，并且 `HISTORY_CONF_FILE` 存在，则创建线程 `hnzcii_history_handle()`。

### 6.2 历史线程 `hnzcii_history_handle()`
1. 每 500ms 轮询历史任务队列 `report_message.report_time_record`：
   - 仅当 `history_mode == 1` 时需要确保 `report_status == report_idle` 且网络状态正常。
   - 一旦取到 `record_report_time` 节点，记录 `history_report_time` 并释放节点内存。
2. 调用 `historydata_query_data(HISTORYDATA_GENERAL_DATA, history_report_time, history_report_time, hnzcii_data_cb, mqtt_server)` 查询该时间点数据。查询期间 `hnzcii_data_cb()` 将同一时间戳的 `data_format_st` 聚合入 map。
3. 查询完成后，遍历 map 中的每个时间片列表，调用 `hnzcii_batch_history_data_publish()` 批量发布：
   - `hnzcii_create_batch_data()` 构造数组 JSON：同一时间戳的多点在一个对象里，附加 `TIMESTAMP_LOCAL` 字段。
   - Topic 使用 `Dev/BatchStatus/...`。
4. 当待补传时间全部处理完毕，线程退出并将 `report_status` 置回 `report_idle`。

### 6.3 回调 `hnzcii_data_cb()`
- 负责按时间戳拆分 `historydata_query_data` 返回的数据：
  - 如果新的 `unix_timestamp` 到来，会先触发前一批数据的发送（调用 `hnzcii_batch_history_data_publish()`），再为新的时间戳初始化 `List`。
  - 数据推入 `List` 后由主线程统一发布，发布完成后释放 `List` 与 map 节点。

## 7. 看门狗与清理
- **看门狗**：主线程定期检查 `mqtt_server->wdt_tick` 是否在 `softdog_interval` 三倍内。若某个子线程停喂狗，会打印调试日志并导致外部监控触发重启。
- **线程清理**：采用 `sal_thread_cleanup_push(clean_function, NULL)`，确保线程退出时调用 `clear_thread_source()` 释放注册资源；最终 `sal_thread_cleanup_pop(1)` 与 `sal_thread_exit()` 完整收尾。

## 8. 关键交互与调试要点
- 配置错误会在 `hnzcii_parse_config()` 中被日志提示（缺失 UserID/ProductID/EquipID 或对象为空）。
- 写指令链路依赖 `mqttserver->report_message.response` 由底层驱动回写，排查写超时时需确认 `data_store_to_head()` 流程与驱动响应路径。
- 历史补传依赖 `history_report_mode`：
  - `mode == 1`：实时与历史互斥，需等待实时空闲。
  - `mode == 2`：历史优先，实时被阻塞。
  - `mode == 3`：允许实时与历史并行（仅在 `hnzcii_realtime_data_publish()` 未做额外限制的情况下）。
- 所有 Topic、设备 ID、错误码等常量集中在 `mqtt_hnzcdata.h`，适合作为协议对接文档的来源。

