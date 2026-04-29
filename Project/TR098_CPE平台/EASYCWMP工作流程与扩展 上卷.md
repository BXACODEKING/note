	# easycwmp 工作流程及扩展指南

  

## 目录

1. [系统架构概述](#系统架构概述)

2. [TR-098与TR-181的区别机制](#tr-098与tr-181的区别机制)

3. [服务器连接建立到结束的完整流程](#服务器连接建立到结束的完整流程)

4. [扩展TR-098服务下发和数据上报](#扩展tr-098服务下发和数据上报)

  

---

  

## 系统架构概述

  

easycwmp系统由两个主要组件构成：

  

### 1. easycwmpd（协议交互主体）

- **位置**: `cwmpd/easycwmpd`

- **职责**: 负责与ACS（Auto Configuration Server）进行TR-069协议交互

- **功能**:

  - HTTP客户端/服务器管理

  - XML消息的构建和解析

  - 会话管理和事件处理

  - 与外部脚本（easycwmp）通信

  

### 2. easycwmp（信息获取主体）

- **位置**: `cwmp/easycwmp`

- **职责**: 以命令行方式存在，负责在CPE中获取各种信息状态

- **功能**:

  - 参数值的获取和设置

  - 数据模型的实现（TR-098/TR-181）

  - 设备信息采集

  

### 3. 通信机制

easycwmpd通过fork子进程执行easycwmp，使用管道（pipe）进行JSON格式的进程间通信。

  

---

  

## TR-098与TR-181的区别机制

  

### 区别原理

  

TR-098和TR-181的主要区别在于**数据模型的根对象名称**：

  

- **TR-098**: 根对象为 `InternetGatewayDevice`

- **TR-181**: 根对象为 `Device`

  

### 实现机制

  

#### 1. 配置读取（`cwmp/trosdt/trosdt.c`）

  

```c

void tr_boot()

{

    char* tmpP = get_uci_option("tr069.tr069.protocol_type");

    if(tmpP && strcmp(tmpP, "tr181") == 0) {

        cwmpnode_tr = &tr181node_tr;      // 使用TR-181节点表

        pDevice = &Device;                 // 使用Device根对象

    } else {

        cwmpnode_tr = &tr098node_tr;      // 使用TR-098节点表

        pDevice = &InternetGatewayDevice;  // 使用InternetGatewayDevice根对象

    }

    safeFree(tmpP);

}

```

  

**关键点**:

- 通过UCI配置项 `tr069.tr069.protocol_type` 决定使用哪个数据模型

- 配置值为 `"tr181"` 时使用TR-181，否则默认使用TR-098

  

#### 2. 节点表定义（`cwmp/trosdt/trosdt.c`）

  

```c

// TR-098节点表

#define NODE(field) cwmpNodeNew(InternetGatewayDevice.field, NULL),

cwmpnode_info tr098node_tr[] = {

    COMMON_NODE_LIST

    {NULL, NULL, NULL, NULL, 0}

};

  

// TR-181节点表

#define NODE(field) cwmpNodeNew(Device.field, NULL),

cwmpnode_info tr181node_tr[] = {

    COMMON_NODE_LIST

    {NULL, NULL, NULL, NULL, 0}

};

```

  

**说明**:

- 两个节点表使用相同的 `COMMON_NODE_LIST`（公共节点列表）

- 区别仅在于根对象名称的转换：

  - TR-098: `InternetGatewayDevice.DeviceInfo.Manufacturer`

  - TR-181: `Device.DeviceInfo.Manufacturer`

  

#### 3. 参数路径解析（`cwmp/trosdt/trosdt_api.c`）

  

参数路径解析函数 `parse_parameter()` 会解析完整的参数路径：

  

```

示例路径：

TR-098: InternetGatewayDevice.NetWorkInfo.LAN.1.Name

TR-181: Device.NetWorkInfo.LAN.1.Name

  

解析结果：

- data_model: "InternetGatewayDevice" 或 "Device"

- info_class: "NetWorkInfo"

- if_label: "LAN"

- index: "1"

- element: "Name"

```

  

#### 4. 运行时切换

  

在运行时，通过 `cwmpinfo_update()` 函数更新当前使用的节点表：

  

```c

void cwmpinfo_update()

{

    cwmpnode = cwmpnode_tr;  // 使用tr_boot()中设置的节点表

    trosdt_api_update();

}

```

  

### 配置方法

  

在UCI配置文件中设置：

  

```bash

# 使用TR-098（默认）

uci set tr069.tr069.protocol_type=tr098

uci commit tr069

  

# 使用TR-181

uci set tr069.tr069.protocol_type=tr181

uci commit tr069

```

  

---

  

## 服务器连接建立到结束的完整流程

  

### 阶段1: 系统启动与初始化

  

#### 1.1 主程序启动（`cwmpd/easycwmp.c`）

  

```c

int main(int argc, char **argv)

{

    // 1. 初始化uloop事件循环

    uloop_init();

    // 2. 初始化备份系统

    backup_init();

    // 3. 初始化外部脚本（fork easycwmp进程）

    external_init();

    // 4. 加载配置文件 /tmp/easycwmp.conf

    config_load();

    // 5. 初始化设备ID

    cwmp_init_deviceid();

    // 6. 初始化HTTP服务器（监听Connection Request）

    http_server_init();

    // 7. 初始化netlink（监听网络接口变化）

    netlink_init();

    // 8. 启动事件（如--boot参数）

    if (start_event & START_BOOT) {

        cwmp_add_event(EVENT_BOOT, NULL, 0, EVENT_BACKUP);

        cwmp_add_inform_timer();  // 10ms后触发Inform

    }

    // 9. 进入主事件循环

    uloop_run();

}

```

  

#### 1.2 设备ID初始化（`cwmpd/cwmp.c`）

  

```c

int cwmp_init_deviceid(void)

{

    // 调用外部脚本获取设备信息

    external_action_simple_execute("inform", "device_id", NULL);

    external_action_handle(json_handle_deviceid);

    // 验证必需字段

    // - product_class

    // - serial_number

    // - manufacturer

    // - oui

}

```

  

### 阶段2: Inform会话建立

  

#### 2.1 Inform触发（`cwmpd/cwmp.c`）

  

```c

void cwmp_add_inform_timer()

{

    uloop_timeout_set(&inform_timer, 10);  // 10ms后执行

}

  

static void cwmp_do_inform(struct uloop_timeout *timeout)

{

    cwmp_inform();  // 执行Inform流程

}

```

  

#### 2.2 Inform执行流程（`cwmpd/cwmp.c::cwmp_inform()`）

  

```c

int cwmp_inform(void)

{

    // 1. 初始化HTTP客户端

    http_client_init();

    // 2. 初始化外部脚本

    external_init();

    // 3. 构建并发送Inform消息

    rpc_inform();

    // 4. 解析InformResponse

    //    - 检查Fault

    //    - 获取MaxEnvelopes

    //    - 检查HoldRequests/NoMoreRequests

    // 5. 处理TransferComplete（如果有）

    while((node = backup_check_transfer_complete())) {

        rpc_transfer_complete(node, &method_id);

    }

    // 6. 处理GetRPCMethods（如果需要）

    if(cwmp->get_rpc_methods) {

        rpc_get_rpc_methods();

    }

    // 7. 进入消息处理循环

    cwmp_handle_messages();

    // 8. 结束会话

    cwmp_handle_end_session();

    // 9. 清理资源

    http_client_exit();

    xml_exit();

    external_exit();

}

```

  

#### 2.3 Inform消息构建（`cwmpd/xml.c::xml_prepare_inform_message()`）

  

```c

int xml_prepare_inform_message(char **msg_out)

{

    // 1. 创建Inform XML模板

    tree = mxmlLoadString(NULL, CWMP_INFORM_MESSAGE, ...);

    // 2. 填充设备信息

    //    - Manufacturer

    //    - OUI

    //    - ProductClass

    //    - SerialNumber

    // 3. 填充事件列表（Event）

    xml_prepare_events_inform(tree);

    // 4. 填充当前时间

    CurrentTime = mix_get_time();

    // 5. 获取参数值（通过外部脚本）

    external_action_simple_execute("inform", "parameter", NULL);

    external_action_handle(json_handle_get_parameter_value);

    // 6. 填充参数列表（ParameterList）

    //    - 从external_list_parameter获取参数值

    //    - 添加通知列表（notifications）

    // 7. 序列化为XML字符串

    *msg_out = mxmlSaveAllocString(tree, xml_format_cb);

}

```

  

#### 2.4 HTTP消息发送（`cwmpd/http.c::http_send_message()`）

  

```c

int8_t http_send_message(char *msg_out, char **msg_in)

{

    // 1. 设置HTTP头

    //    - Content-Type: text/xml; charset="utf-8"

    //    - SOAPAction

    //    - User-Agent: easycwmp

    // 2. 设置POST数据

    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, msg_out);

    // 3. 执行HTTP请求

    res = curl_easy_perform(curl);

    // 4. 处理重定向（302/307）

    if (httpCode == 302 || httpCode == 307) {

        // 重新初始化HTTP客户端并重试

    }

    // 5. 读取响应

    *msg_in = 响应内容

}

```

  

### 阶段3: RPC方法处理循环

  

#### 3.1 消息处理循环（`cwmpd/cwmp.c::cwmp_handle_messages()`）

  

```c

int cwmp_handle_messages(void)

{

    while (1) {

        // 1. 发送空HTTP请求（等待ACS的RPC方法）

        http_send_message(msg_out, &msg_in);

        // 2. 如果收到空响应，结束循环

        if (!msg_in) {

            break;  // ACS发送空消息表示会话结束

        }

        // 3. 解析并处理RPC方法

        xml_handle_message(msg_in, &msg_out);

        // 4. 发送响应

        // msg_out已在xml_handle_message中构建

    }

}

```

  

#### 3.2 RPC方法解析（`cwmpd/xml.c::xml_handle_message()`）

  

```c

int xml_handle_message(char *msg_in, char **msg_out)

{

    // 1. 解析XML

    tree_in = mxmlLoadString(NULL, msg_in, ...);

    // 2. 重建命名空间

    xml_recreate_namespace(tree_in);

    // 3. 提取cwmp:ID

    // 4. 查找Body中的RPC方法名

    // 5. 匹配RPC方法处理器

    const struct rpc_method rpc_methods[] = {

        { "SetParameterValues", xml_handle_set_parameter_values },

        { "GetParameterValues", xml_handle_get_parameter_values },

        { "GetParameterNames", xml_handle_get_parameter_names },

        { "GetParameterAttributes", xml_handle_get_parameter_attributes },

        { "SetParameterAttributes", xml_handle_set_parameter_attributes },

        { "AddObject", xml_handle_AddObject },

        { "DeleteObject", xml_handle_DeleteObject },

        { "Download", xml_handle_download },

        { "Upload", xml_handle_upload },

        { "Reboot", xml_handle_reboot },

        { "FactoryReset", xml_handle_factory_reset },

        { "ScheduleInform", xml_handle_schedule_inform },

    };

    // 6. 调用对应的处理器

    method->handler(body_in, tree_in, tree_out);

    // 7. 构建响应XML

    *msg_out = mxmlSaveAllocString(tree_out, xml_format_cb);

}

```

  

#### 3.3 SetParameterValues处理示例（`cwmpd/xml.c::xml_handle_set_parameter_values()`）

  

```c

int xml_handle_set_parameter_values(...)

{

    // 1. 解析参数列表

    while (遍历XML树) {

        // 提取Name和Value

        parameter_name = ...

        parameter_value = ...

        // 2. 调用外部脚本设置参数

        external_action_parameter_execute("set", "value",

                                         parameter_name, parameter_value);

    }

    // 3. 执行apply操作

    external_action_simple_execute("apply", "value", param_key);

    // 4. 处理响应

    external_action_handle(json_handle_set_parameter);

    // 5. 检查错误

    code = xml_check_fault_in_list_parameter();

    // 6. 构建响应

    if (成功) {

        // SetParameterValuesResponse + Status

    } else {

        // Fault消息

    }

}

```

  

#### 3.4 GetParameterValues处理示例（`cwmpd/xml.c::xml_handle_get_parameter_values()`）

  

```c

int xml_handle_get_parameter_values(...)

{

    // 1. 解析参数名列表

    while (遍历参数名) {

        parameter_name = ...

        // 2. 调用外部脚本获取参数值

        external_action_parameter_execute("get", "value",

                                         parameter_name, NULL);

        external_action_handle(json_handle_get_parameter_value);

    }

    // 3. 构建响应

    // GetParameterValuesResponse + ParameterList

    while (external_list_parameter) {

        // 添加ParameterValueStruct

        // - Name

        // - Value (带xsi:type)

    }

}

```

  

### 阶段4: 外部脚本交互（easycwmp）

  

#### 4.1 外部脚本初始化（`cwmpd/external.c::external_init()`）

  

```c

int external_init()

{

    // 1. 创建管道

    pipe(pfds_out);  // 用于读取easycwmp输出

    pipe(pfds_in);   // 用于向easycwmp输入

    // 2. fork子进程

    pid = fork();

    if (pid == 0) {

        // 子进程：执行easycwmp

        dup2(pfds_in[0], STDIN_FILENO);

        dup2(pfds_out[1], STDOUT_FILENO);

        execl("/usr/sbin/easycwmp", "easycwmp", "--json-input", NULL);

    }

}

```

  

#### 4.2 参数获取流程（`cwmp/cwmp_func.c::cwmpfunc_operate()`）

  

```c

int cwmpfunc_operate(cwmparam *param)

{

    // 1. 解析参数路径

    parse_parameter(param->parameter, &pare_parse);

    // 2. 遍历节点表查找匹配节点

    while(cwmpnode[i].name) {

        namestr = cwmplib_special_transform(cwmpnode[i].name, cur_loop);

        if (GET操作) {

            // 调用节点的get函数

            if(cwmpnode[i].get) {

                ret = cwmpnode[i].get(cwmpnode[i].name, param);

            } else {

                // 直接返回节点值

                libs_cjson_parameter_value(namestr, cwmpnode[i].value);

            }

        }

        if (SET操作) {

            // 调用节点的set函数

            if(cwmpnode[i].opt) {

                ret = (*(int(*)(cwmparam *))cwmpnode[i].opt)(param);

            }

        }

        i++;

    }

}

```

  

#### 4.3 JSON响应格式

  

easycwmp通过stdout输出JSON格式的响应：

  

```json

// 参数值响应

{"parameter": "InternetGatewayDevice.DeviceInfo.Manufacturer", "value": "XXX"}

  

// 参数名响应

{"parameter": "InternetGatewayDevice.DeviceInfo.Manufacturer", "writable": "0"}

  

// 状态响应

{"status": "0"}

  

// 错误响应

{"parameter": "...", "fault_code": "9005"}

```

  

### 阶段5: 会话结束

  

#### 5.1 会话结束处理（`cwmpd/cwmp.c::cwmp_handle_end_session()`）

  

```c

static void cwmp_handle_end_session(void)

{

    // 1. 执行apply操作

    external_action_simple_execute("apply", "service", NULL);

    // 2. 检查结束会话标志

    if (cwmp->end_session & ENDS_FACTORY_RESET) {

        external_action_simple_execute("factory_reset", NULL, NULL);

        exit(EXIT_SUCCESS);

    }

    if (cwmp->end_session & ENDS_REBOOT) {

        external_action_simple_execute("reboot", NULL, NULL);

        exit(EXIT_SUCCESS);

    }

    if (cwmp->end_session & ENDS_RELOAD_CONFIG) {

        config_load();

    }

}

```

  

#### 5.2 重试机制（`cwmpd/cwmp.c::cwmp_retry_session()`）

  

```c

static inline void cwmp_retry_session()

{

    // 计算重试间隔（指数退避）

    // retry_count: 0 -> 0s

    //              1 -> 7s

    //              2 -> 15s

    //              3 -> 30s

    //              ...

    //              10+ -> 3840s

    int rtime = cwmp_retry_count_interval(cwmp->retry_count);

    uloop_timeout_set(&inform_timer_retry, SECDTOMSEC * rtime);

}

```

  

### 阶段6: 定期Inform

  

#### 6.1 定期Inform初始化（`cwmpd/cwmp.c::cwmp_periodic_inform_init()`）

  

```c

void cwmp_periodic_inform_init(void)

{

    if (config->acs->periodic_enable && config->acs->periodic_interval) {

        if (config->acs->periodic_time != -1) {

            // 使用参考时间计算下次Inform时间

            uloop_timeout_set(&periodic_inform_timer,

                            cwmp_periodic_inform_time() * SECDTOMSEC);

        } else {

            // 直接使用间隔时间

            uloop_timeout_set(&periodic_inform_timer,

                            config->acs->periodic_interval * SECDTOMSEC);

        }

    }

}

```

  

#### 6.2 定期Inform触发（`cwmpd/cwmp.c::cwmp_periodic_inform()`）

  

```c

static void cwmp_periodic_inform(struct uloop_timeout *timeout)

{

    // 1. 设置下次定时器

    uloop_timeout_set(&periodic_inform_timer,

                     config->acs->periodic_interval * SECDTOMSEC);

    // 2. 添加PERIODIC事件

    cwmp_add_event(EVENT_PERIODIC, NULL, 0, EVENT_BACKUP);

    // 3. 触发Inform

    cwmp_add_inform_timer();

}

```

  

### 阶段7: Connection Request（ACS主动连接）

  

#### 7.1 HTTP服务器监听（`cwmpd/http.c::http_server_init()`）

  

```c

void http_server_init(void)

{

    // 1. 初始化Digest认证

    http_digest_init_nonce_priv_key();

    // 2. 创建TCP服务器socket

    http_s.http_event.fd = usock(USOCK_TCP | USOCK_SERVER,

                                 "0.0.0.0", config->local->port);

    // 3. 注册事件回调

    uloop_fd_add(&http_s.http_event, ULOOP_READ);

}

```

  

#### 7.2 处理Connection Request（`cwmpd/http.c::http_new_client()`）

  

```c

static void http_new_client(struct uloop_fd *ufd, unsigned events)

{

    // 1. 接受连接

    client = accept(ufd->fd, NULL, NULL);

    // 2. 读取HTTP请求头

    while (fgets(buffer, sizeof(buffer), fp)) {

        // 3. 验证认证（Digest或Basic）

        if (认证成功) {

            auth_status = 1;

        }

    }

    // 4. 发送HTTP响应

    if (auth_status) {

        fputs("HTTP/1.1 200 OK\r\n", fp);

        // 5. 触发Connection Request事件

        cwmp_connection_request(EVENT_CONNECTION_REQUEST);

    } else {

        fputs("HTTP/1.1 401 Unauthorized\r\n", fp);

    }

}

```

  

---

  

## 扩展TR-098服务下发和数据上报

  

### 扩展步骤概览

  

1. **定义数据模型节点**

2. **实现Get/Set函数**

3. **注册到节点表**

4. **实现Inform上报**

5. **实现ValueChange通知**

  

### 步骤1: 定义数据结构

  

在 `cwmp/trosdt/trosdt.h` 或相关头文件中定义数据结构：

  

```c

// 示例：添加新的服务节点

typedef struct {

    char ServiceName[64];

    char ServiceStatus[32];

    int ServicePort;

} ServiceInfo;

  

// 在osdt_ParamNode中添加

typedef struct {

    // ... 现有字段

    ServiceInfo Service[10];  // 支持最多10个服务实例

} InternetGatewayDevice;

```

  

### 步骤2: 实现Get函数

  

在 `cwmp/trosdt/` 目录下创建或修改文件，实现参数获取：

  

```c

// cwmp/trosdt/trosdt_service.c

  

#include "trosdt.h"

  

// Get函数：获取服务名称

int cwmpget_Service_Name(char *name, cwmparam *param)

{

    pare_parse_t parse_info;

    int index = 0;

    parse_parameter(name, &parse_info);

    index = atoi(parse_info.index);

    if (index >= 0 && index < 10) {

        libs_cjson_parameter_value(name,

            pDevice->Service[index].ServiceName);

        return E_CWMP_SUCCEED;

    }

    return E_INVALID_PARAMETER_NAME;

}

  

// Get函数：获取服务状态

int cwmpget_Service_Status(char *name, cwmparam *param)

{

    pare_parse_t parse_info;

    int index = 0;

    parse_parameter(name, &parse_info);

    index = atoi(parse_info.index);

    if (index >= 0 && index < 10) {

        libs_cjson_parameter_value(name,

            pDevice->Service[index].ServiceStatus);

        return E_CWMP_SUCCEED;

    }

    return E_INVALID_PARAMETER_NAME;

}

  

// Get函数：获取服务端口

int cwmpget_Service_Port(char *name, cwmparam *param)

{

        pare_parse_t parse_info;

    int index = 0;

  

    char port_str[16];

  

    parse_parameter(name, &parse_info);

  

    index = atoi(parse_info.index);

  

    if (index >= 0 && index < 10) {

        snprintf(port_str, sizeof(port_str), "%d",

                 pDevice->Service[index].ServicePort);

        libs_cjson_parameter_value(name, port_str);

        return E_CWMP_SUCCEED;

    }

    return E_INVALID_PARAMETER_NAME;

}

```

  

### 步骤3: 实现Set函数

  

```c

// Set函数：设置服务名称

int cwmpset_Service_Name(cwmparam *param)

{

    pare_parse_t parse_info;

    int index = 0;

    if (!param || !param->parameter || !param->argument) {

        return E_INVALID_ARGUMENTS;

    }

    parse_parameter(param->parameter, &parse_info);

    index = atoi(parse_info.index);

    if (index >= 0 && index < 10) {

        strncpy(pDevice->Service[index].ServiceName,

                param->argument,

                sizeof(pDevice->Service[index].ServiceName) - 1);

        // 更新实际服务配置

        update_service_config(index);

        return E_CWMP_SUCCEED;

    }

    return E_INVALID_PARAMETER_NAME;

}

  

// Set函数：设置服务状态

int cwmpset_Service_Status(cwmparam *param)

{

    pare_parse_t parse_info;

    int index = 0;

    if (!param || !param->parameter || !param->argument) {

        return E_INVALID_ARGUMENTS;

    }

    parse_parameter(param->parameter, &parse_info);

    index = atoi(parse_info.index);

    if (index >= 0 && index < 10) {

        strncpy(pDevice->Service[index].ServiceStatus,

                param->argument,

                sizeof(pDevice->Service[index].ServiceStatus) - 1);

        // 启动/停止服务

        if (strcmp(param->argument, "Enabled") == 0) {

            start_service(index);

        } else {

            stop_service(index);

        }

        return E_CWMP_SUCCEED;

    }

    return E_INVALID_PARAMETER_NAME;

}

  

// Set函数：设置服务端口

int cwmpset_Service_Port(cwmparam *param)

{

    pare_parse_t parse_info;

    int index = 0;

    int port = 0;

    if (!param || !param->parameter || !param->argument) {

        return E_INVALID_ARGUMENTS;

    }

    parse_parameter(param->parameter, &parse_info);

    index = atoi(parse_info.index);

    port = atoi(param->argument);

    if (index >= 0 && index < 10 && port > 0 && port < 65536) {

        pDevice->Service[index].ServicePort = port;

        // 更新服务配置

        update_service_config(index);

        return E_CWMP_SUCCEED;

    }

    return E_INVALID_PARAMETER_VALUE;

}

```

  

### 步骤4: 注册节点到节点表

  

在 `cwmp/trosdt/trosdt.c` 中添加节点定义：

  

```c

// 在COMMON_NODE_LIST中添加新节点

#define COMMON_NODE_LIST \

    // ... 现有节点 ...

    NODE(Service.$i.ServiceName) \

    NODE(Service.$i.ServiceStatus) \

    NODE(Service.$i.ServicePort) \

    // ... 其他节点 ...

  

// 在tr098node_tr和tr181node_tr中会自动包含这些节点

```

  

**注意**: `$i` 表示这是一个多实例节点，系统会自动处理索引转换。

  

如果需要自定义Get/Set函数，需要在节点表中指定：

  

```c

// 方式1: 使用宏定义（自动生成）

#define NODE(field) cwmpNodeNew(PREFIX.field, NULL),

  

// 方式2: 手动指定Get/Set函数

cwmpnode_info tr098node_tr[] = {

    // ... 其他节点 ...

    {"InternetGatewayDevice.Service.$i.ServiceName",

     InternetGatewayDevice.Service[0].ServiceName,

     (void *)cwmpset_Service_Name,

     cwmpget_Service_Name,

     1},  // muti_rule=1表示支持多实例

    {"InternetGatewayDevice.Service.$i.ServiceStatus",

     InternetGatewayDevice.Service[0].ServiceStatus,

     (void *)cwmpset_Service_Status,

     cwmpget_Service_Status,

     1},

    {"InternetGatewayDevice.Service.$i.ServicePort",

     InternetGatewayDevice.Service[0].ServicePort,

     (void *)cwmpset_Service_Port,

     cwmpget_Service_Port,

     1},

    {NULL, NULL, NULL, NULL, 0}

};

```

  

### 步骤5: 实现Inform上报

  

在 `cwmp/trosdt/trosdt.c` 的 `tr_inform()` 函数中添加参数上报：

  

```c

void tr_inform(cwmparam *param)

{

    cJSON *obj = NULL;

    if (!strcmp(param->class, "parameter")) {

        cwmparam param_get = {

            .command = cwmpopt[CWMPOPT_GET],

            .class = "value",

            .parameter = NULL,

        };

        // 上报现有参数

        param_get.parameter = ".DeviceInfo.";

        cwmpfunc_operate(&param_get);

        param_get.parameter = ".SoftwareVersion.";

        cwmpfunc_operate(&param_get);

        // 添加新服务的上报

        param_get.parameter = ".Service.";

        cwmpfunc_operate(&param_get);

        return E_CWMP_SUCCEED;

    }

    return E_CWMP_FAIL;

}

```

  

**说明**:

- `cwmpfunc_operate()` 会自动遍历节点表中匹配的参数

- 对于 `.Service.` 这样的路径，会遍历所有实例（Service.1, Service.2, ...）

- 参数值通过 `libs_cjson_parameter_value()` 输出到stdout，由easycwmpd收集

  

### 步骤6: 实现ValueChange通知

  

#### 6.1 添加通知机制

  

当服务状态或配置发生变化时，需要触发ValueChange事件：

  

```c

// 在服务状态变化时调用

void notify_service_status_change(int index, const char *status)

{

    char param_name[256];

    char notification[2] = "2";  // 2=Active Notification

    // 构建参数名

    snprintf(param_name, sizeof(param_name),

             "%s.Service.%d.ServiceStatus",

             (pDevice == &InternetGatewayDevice) ? "InternetGatewayDevice" : "Device",

             index);

    // 添加通知

    cwmp_add_notification(param_name, status, "xsd:string", notification);

    // notification: "0"=不通知, "1"=被动通知, "2"=主动通知

}

```

  

#### 6.2 在Set函数中触发通知

  

```c

int cwmpset_Service_Status(cwmparam *param)

{

    // ... 设置逻辑 ...

    // 触发ValueChange通知

    char param_name[256];

    snprintf(param_name, sizeof(param_name),

             "%s.Service.%d.ServiceStatus",

             (pDevice == &InternetGatewayDevice) ? "InternetGatewayDevice" : "Device",

             index);

    cwmp_add_notification(param_name, param->argument, "xsd:string", "2");

    return E_CWMP_SUCCEED;

}

```

  

#### 6.3 ValueChange检查机制

  

在 `cwmp/trosdt/trosdt.c` 的 `tr_value_notification()` 中添加检查：

  

```c

int tr_value_notification(cwmparam *param)

{

    cwmparam param_notify = {

        .command = cwmpopt[CWMPOPT_GET],

        .class = "notification",

        .parameter = NULL,

    };

    // 检查现有参数

    param_notify.parameter = ".SoftwareVersion.";

    cwmpfunc_operate(&param_notify);

    // 添加服务参数检查

    param_notify.parameter = ".Service.";

    cwmpfunc_operate(&param_notify);

    return E_CWMP_SUCCEED;

}

```

  

### 步骤7: 数据更新函数

  

创建数据更新函数，定期从系统获取最新数据：

  

```c

// cwmp/trosdt/trosdt_service.c

  

void trosdt_service_update(void)

{

    int i;

    FILE *fp;

    char buf[256];

    // 从系统获取服务信息（示例：从/proc或配置文件读取）

    for (i = 0; i < 10; i++) {

        // 示例：从配置文件读取服务名

        snprintf(buf, sizeof(buf), "/etc/config/service_%d", i);

        fp = fopen(buf, "r");

        if (fp) {

            fgets(pDevice->Service[i].ServiceName,

                  sizeof(pDevice->Service[i].ServiceName), fp);

            fclose(fp);

        }

        // 检查服务状态（示例：通过systemd或进程检查）

        if (check_service_running(i)) {

            strcpy(pDevice->Service[i].ServiceStatus, "Enabled");

        } else {

            strcpy(pDevice->Service[i].ServiceStatus, "Disabled");

        }

        // 获取服务端口（示例：从netstat或配置文件读取）

        pDevice->Service[i].ServicePort = get_service_port(i);

    }

}

```

  

在 `cwmp/trosdt/trosdt_api.c` 的 `trosdt_api_update()` 中调用：

  

```c

void trosdt_api_update(void)

{

    trosdt_info_update();

    trosdt_netif_update();

    trosdt_service_update();  // 添加服务更新

}

```

  

### 步骤8: 编译配置

  

在 `cwmp/trosdt/Makefile` 中添加新文件：

  

```makefile

OBJS = trosdt.o \

       trosdt_api.o \

       trosdt_info.o \

       trosdt_netif.o \

       trosdt_set.o \

       trosdt_service.o  # 添加新文件

```

  

### 完整示例：添加Service节点

  

#### 1. 数据结构定义（`cwmp/trosdt/trosdt.h`）

  

```c

typedef struct {

    char ServiceName[64];

    char ServiceStatus[32];

    int ServicePort;

} ServiceInfo;

  

typedef struct {

    // ... 现有字段 ...

    ServiceInfo Service[10];

} InternetGatewayDevice;

  

typedef struct {

    // ... 现有字段 ...

    ServiceInfo Service[10];

} Device;

```

  

#### 2. 实现文件（`cwmp/trosdt/trosdt_service.c`）

  

```c

#include "trosdt.h"

#include "cwmp.h"

  

// Get函数实现

int cwmpget_Service_Name(char *name, cwmparam *param) { /* ... */ }

int cwmpget_Service_Status(char *name, cwmparam *param) { /* ... */ }

int cwmpget_Service_Port(char *name, cwmparam *param) { /* ... */ }

  

// Set函数实现

int cwmpset_Service_Name(cwmparam *param) { /* ... */ }

int cwmpset_Service_Status(cwmparam *param) { /* ... */ }

int cwmpset_Service_Port(cwmparam *param) { /* ... */ }

  

// 数据更新函数

void trosdt_service_update(void) { /* ... */ }

```

  

#### 3. 节点注册（`cwmp/trosdt/trosdt.c`）

  

```c

#define COMMON_NODE_LIST \

    // ... 现有节点 ...

    NODE(Service.$i.ServiceName) \

    NODE(Service.$i.ServiceStatus) \

    NODE(Service.$i.ServicePort)

```

  

#### 4. Inform上报（`cwmp/trosdt/trosdt.c::tr_inform()`）

  

```c

if (!strcmp(param->class, "parameter")) {

    // ... 现有代码 ...

    param_get.parameter = ".Service.";

    cwmpfunc_operate(&param_get);

}

```

  

### 测试验证

  

#### 1. 编译

  

```bash

cd cwmp/trosdt

make clean

make

```

  

#### 2. 测试GetParameterValues

  

通过ACS发送GetParameterValues请求：

  

```xml

<GetParameterValues>

    <ParameterNames>

        <string>InternetGatewayDevice.Service.1.ServiceName</string>

        <string>InternetGatewayDevice.Service.1.ServiceStatus</string>

        <string>InternetGatewayDevice.Service.1.ServicePort</string>

    </ParameterNames>

</GetParameterValues>

```

  

#### 3. 测试SetParameterValues

  

```xml

<SetParameterValues>

    <ParameterList>

        <ParameterValueStruct>

            <Name>InternetGatewayDevice.Service.1.ServiceStatus</Name>

            <Value xsi:type="xsd:string">Enabled</Value>

        </ParameterValueStruct>

    </ParameterList>

    <ParameterKey>test_key</ParameterKey>

</SetParameterValues>

```

  

#### 4. 验证Inform上报

  

查看Inform消息中的ParameterList，应该包含Service相关参数。

  

### 注意事项

  

1. **参数路径一致性**: TR-098使用 `InternetGatewayDevice`，TR-181使用 `Device`

2. **多实例处理**: 使用 `$i` 标记多实例节点，系统会自动处理索引转换

3. **数据类型**: 确保参数类型与TR-098规范一致（string, int, unsignedInt等）

4. **通知机制**: 根据需求设置通知级别（0/1/2）

5. **错误处理**: Set函数需要验证参数有效性，返回适当的错误码

6. **线程安全**: 如果涉及多线程访问，需要添加锁机制

  

### 常见问题

  

#### Q1: 参数无法获取

- 检查节点是否注册到节点表

- 检查Get函数是否正确实现

- 检查参数路径是否正确（注意大小写）

  

#### Q2: Set操作失败

- 检查Set函数是否正确注册

- 检查参数值是否有效

- 检查错误码返回是否正确

  

#### Q3: Inform中缺少参数

- 检查 `tr_inform()` 中是否添加了参数路径

- 检查数据更新函数是否被调用

- 检查参数值是否为空

  

#### Q4: ValueChange不触发

- 检查通知级别设置（notification字段）

- 检查 `tr_value_notification()` 是否包含该参数

- 检查 `cwmp_add_notification()` 是否被调用

  

---

  

## 总结

  

本文档详细介绍了easycwmp的工作流程，包括：

  

1. **TR-098与TR-181的区别机制**: 通过UCI配置和节点表切换实现

2. **完整的会话流程**: 从启动到Inform，再到RPC处理，最后会话结束

3. **扩展方法**: 详细的步骤指导如何添加新的TR-098参数和服务

  

通过本文档，开发者可以：

- 理解easycwmp的整体架构和工作原理

- 掌握TR-098和TR-181的切换机制

- 快速扩展新的数据模型参数

- 实现服务下发和数据上报功能

  

---

  

**文档版本**: 1.0  

**最后更新**: 2026-01-19  

**维护者**: easycwmp开发团队