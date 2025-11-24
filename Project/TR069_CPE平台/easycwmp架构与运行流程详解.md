# EasyCWMP 项目架构与运行流程详解

## 1. 项目概述

### 1.1 简介
`easycwmp` 是一个标准 TR-069 (CWMP - CPE WAN Management Protocol) 协议的实现体，在协议中充当 CPE (Customer Premises Equipment) 的角色，通过标准的 TR-069 协议连接 ACS (Auto Configuration Server)，并通过各种通用的方法进行交互。

### 1.2 主要组件
项目编译后生成两个主要可执行文件：

1. **easycwmpd** (守护进程)
   - 协议交互主体
   - 负责与 ACS 进行连接交互
   - 处理 HTTP 通信和 CWMP 协议
   - 事件管理和定时任务

2. **easycwmp** (命令行工具)
   - 信息获取主体
   - 以命令行交互的方式存在
   - 负责在 CPE 中获取各种信息状态
   - 被 easycwmpd 调用

3. **cwmpDiagnostics** (诊断工具)
   - 网络诊断功能
   - 支持 Ping、Traceroute 等诊断

---

## 2. 项目架构

### 2.1 目录结构

```
easycwmp/
├── cwmpd/                  # 守护进程主目录
│   ├── easycwmp.c         # 主程序入口
│   ├── cwmp.c             # CWMP 协议核心逻辑
│   ├── http.c             # HTTP 客户端/服务器
│   ├── xml.c              # XML 消息解析
│   ├── config.c           # 配置管理
│   ├── external.c         # 外部脚本调用
│   ├── backup.c           # 数据备份和持久化
│   ├── ubus.c             # UBus 通信接口
│   ├── basicauth.c        # Basic 认证
│   ├── digestauth.c       # Digest 认证
│   ├── json.c             # JSON 处理
│   ├── log.c              # 日志管理
│   ├── time.c             # 时间管理
│   └── libmicroxml/       # XML 解析库
│
├── cwmp/                   # 数据模型与信息获取
│   ├── cwmp.c             # 主入口和命令解析
│   ├── cwmp_func.c        # 功能函数实现
│   ├── cwmp_libs.c        # 库函数
│   ├── cwmp_upgrade.c     # 升级功能
│   ├── common/            # 通用数据模型
│   │   ├── common_info.c  # 通用信息获取
│   │   ├── common_set.c   # 通用参数设置
│   │   ├── common_util.c  # 通用工具函数
│   │   └── cwmp_diagnostics.c  # 诊断功能
│   ├── tr098/             # TR-098 数据模型
│   │   ├── tr098.c        # 数据模型定义
│   │   ├── tr098_info.c   # 信息获取
│   │   └── tr098_set.c    # 参数设置
│   ├── tr181/             # TR-181 数据模型
│   ├── trh101c/           # TRH101C 自定义数据模型
│   ├── trz4/              # TRZ4 自定义数据模型
│   └── diagnostics/       # 诊断工具
│
├── Makefile               # 主编译文件
└── README.md              # 项目说明
```

### 2.2 核心模块架构

```
┌─────────────────────────────────────────────────────────────┐
│                        ACS Server                           │
│                    (Auto Config Server)                     │
└───────────────────────────┬─────────────────────────────────┘
                            │ TR-069/HTTP(S)
                            │ SOAP/XML
┌───────────────────────────┴─────────────────────────────────┐
│                      easycwmpd (守护进程)                    │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  HTTP Client │  │  HTTP Server │  │  XML Parser  │      │
│  │  (libcurl)   │  │  (Socket)    │  │ (libmicroxml)│      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                 │                  │              │
│  ┌──────┴─────────────────┴──────────────────┴───────┐      │
│  │          CWMP Protocol Handler                    │      │
│  │  - Inform / InformResponse                        │      │
│  │  - GetParameterValues / Response                  │      │
│  │  - SetParameterValues / Response                  │      │
│  │  - AddObject / DeleteObject                       │      │
│  │  - Download / Upload                              │      │
│  │  - Reboot / FactoryReset                          │      │
│  └──────────────────┬────────────────────────────────┘      │
│                     │                                        │
│  ┌──────────────────┴────────────────────────────────┐      │
│  │           Event & Session Manager                 │      │
│  │  - Periodic Inform Timer                          │      │
│  │  - Event Queue Management                         │      │
│  │  - Retry Logic                                    │      │
│  └──────────────────┬────────────────────────────────┘      │
│                     │                                        │
│  ┌──────────────────┴────────────────────────────────┐      │
│  │         Configuration & Backup                    │      │
│  │  - JSON Config (/tmp/easycwmp.conf)              │      │
│  │  - Event Backup                                   │      │
│  │  - Transfer Complete Backup                       │      │
│  └──────────────────┬────────────────────────────────┘      │
│                     │                                        │
│  ┌──────────────────┴────────────────────────────────┐      │
│  │         External Script Interface                 │      │
│  │  - 调用 easycwmp 获取参数                          │      │
│  │  - JSON 格式通信                                   │      │
│  │  - Pipe 通信机制                                   │      │
│  └───────────────────────────────────────────────────┘      │
└─────────────────────────────┬───────────────────────────────┘
                              │ JSON 命令/响应
                              │ Pipe 通信
┌─────────────────────────────┴───────────────────────────────┐
│                 easycwmp (命令行工具)                        │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────┐       │
│  │         Command Parser & Router                  │       │
│  │  - get / set / add / delete                     │       │
│  │  - inform / apply / reboot                      │       │
│  │  - download / upload                            │       │
│  │  - ping / traceroute                            │       │
│  └──────────────────┬───────────────────────────────┘       │
│                     │                                        │
│  ┌──────────────────┴───────────────────────────────┐       │
│  │      Data Model Layer (编译时选择)                │       │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐ │       │
│  │  │  TR-098    │  │  TR-181    │  │  TRH101C   │ │       │
│  │  │ InternetGW │  │  Device.   │  │ (Custom)   │ │       │
│  │  └────────────┘  └────────────┘  └────────────┘ │       │
│  │  ┌────────────┐                                  │       │
│  │  │   TRZ4     │                                  │       │
│  │  │ (Custom)   │                                  │       │
│  │  └────────────┘                                  │       │
│  └──────────────────┬───────────────────────────────┘       │
│                     │                                        │
│  ┌──────────────────┴───────────────────────────────┐       │
│  │         Common Module                            │       │
│  │  - DeviceInfo                                    │       │
│  │  - ManagementServer                              │       │
│  │  - Diagnostics (Ping/Traceroute)                │       │
│  └──────────────────┬───────────────────────────────┘       │
└─────────────────────┴─────────────────────────────────────┘
                      │
                      │ UCI / UBus / Platform API
                      │
┌─────────────────────┴─────────────────────────────────────┐
│            System Layer (OpenWrt/Linux)                   │
│  - UCI Configuration                                      │
│  - UBus System Bus                                        │
│  - Network Interfaces                                     │
│  - Platform Libraries                                     │
└───────────────────────────────────────────────────────────┘
```

### 2.3 数据模型架构

项目支持多种 TR-069 数据模型（编译时通过 `DATA_MODEL_XXX` 宏选择）：

#### TR-098 数据模型
- 根对象: `InternetGatewayDevice`
- 设备信息: `DeviceInfo`
- 管理服务器: `ManagementServer`
- WAN/LAN 设备配置
- 诊断功能

#### TR-181 数据模型
- 根对象: `Device`
- 更现代化的参数组织
- 更好的扩展性

#### TRH101C / TRZ4 (自定义数据模型)
- 基于 TR-098/181 扩展
- 添加厂商自定义参数
- 特定设备功能支持

---

## 3. 运行流程详解

### 3.1 easycwmpd 启动流程

```
启动 easycwmpd
    │
    ├─> 1. 解析命令行参数
    │     - foreground: 前台运行
    │     - boot: 启动事件 (1 BOOT)
    │     - getrpcmethod: 获取 RPC 方法
    │     - config: 配置文件路径
    │
    ├─> 2. 初始化日志系统
    │     - 打开 syslog
    │     - 设置日志级别
    │
    ├─> 3. 守护进程化 (如非前台模式)
    │     - fork() 进程
    │     - 创建新会话
    │     - 重定向标准输入输出
    │
    ├─> 4. 创建 PID 文件锁
    │     - /var/run/easycwmpd.pid
    │     - 防止重复运行
    │
    ├─> 5. 初始化 uloop 事件循环
    │     - libubox 事件循环框架
    │
    ├─> 6. 加载配置文件
    │     - 读取 /tmp/easycwmp.conf
    │     - 解析 JSON 配置
    │     - 设置 ACS URL, 认证信息等
    │
    ├─> 7. 初始化外部脚本接口
    │     - 准备调用 easycwmp
    │
    ├─> 8. 初始化备份系统
    │     - 加载持久化的事件
    │     - 加载 TransferComplete 等待列表
    │
    ├─> 9. 初始化 CWMP 模块
    │     - 创建事件队列
    │     - 初始化重试计数器
    │
    ├─> 10. 初始化 HTTP 客户端
    │     - 配置 libcurl
    │     - 设置 ACS URL
    │     - 配置 SSL 证书 (如有)
    │     - 设置认证方式 (Basic/Digest)
    │
    ├─> 11. 初始化 HTTP 服务器
    │     - 创建监听 socket
    │     - 绑定端口 (默认 7547)
    │     - 监听 ConnectionRequest
    │
    ├─> 12. 初始化 UBus (如启用)
    │     - 连接 UBus 总线
    │     - 注册服务和方法
    │
    ├─> 13. 注册 Netlink 监听
    │     - 监听网络接口变化
    │     - 更新 ConnectionRequestURL
    │
    ├─> 14. 添加启动事件
    │     - BOOT 事件 (如指定)
    │     - GET_RPC_METHODS (如指定)
    │
    ├─> 15. 启动定期上报定时器
    │     - 根据配置的 periodic_interval
    │     - 计算下次上报时间
    │
    ├─> 16. 触发首次 Inform
    │     - 10 秒后触发
    │
    └─> 17. 进入事件循环
          - uloop_run()
          - 处理定时器、网络事件等
```

### 3.2 CWMP Inform 会话流程

```
触发 Inform (定期/事件/连接请求)
    │
    ├─> 1. 检查是否有待发送事件
    │     - 遍历事件队列
    │     - 如果队列为空，不发送
    │
    ├─> 2. 初始化 HTTP 客户端
    │     - 配置 ACS URL
    │     - 设置认证信息
    │
    ├─> 3. 调用 easycwmp 获取设备信息
    │   │
    │   ├─> 通过 external_simple_exec() 调用
    │   │     {"command":"inform"}
    │   │
    │   ├─> easycwmp 处理:
    │   │     - 读取数据模型 (TR-098/181/TRZ4)
    │   │     - 获取 DeviceInfo
    │   │     - 获取 ManagementServer 信息
    │   │     - 返回 JSON 格式数据
    │   │
    │   └─> 解析返回的 JSON 数据
    │
    ├─> 4. 构建 Inform XML 消息
    │     - SOAP Envelope
    │     - DeviceId (制造商、序列号等)
    │     - Event 列表
    │     - ParameterList
    │     - MaxEnvelopes
    │     - CurrentTime
    │     - RetryCount
    │
    ├─> 5. 发送 Inform 到 ACS
    │     - HTTP POST
    │     - Content-Type: text/xml
    │     - SOAPAction header
    │
    ├─> 6. 接收 InformResponse
    │     - 解析 XML
    │     - 验证 MaxEnvelopes
    │     - 重置重试计数
    │
    ├─> 7. 清除已确认的事件
    │     - 根据事件移除策略
    │     - 更新备份文件
    │
    ├─> 8. 等待 ACS 的 RPC 请求
    │     - 空 HTTP POST
    │     - 或包含 RPC 方法的响应
    │
    └─> 9. 处理 RPC 请求/响应循环
          (见下节)
```

### 3.3 RPC 方法处理流程

#### GetParameterValues 流程
```
收到 GetParameterValues 请求
    │
    ├─> 1. 解析 XML 请求
    │     - 提取 ParameterNames
    │
    ├─> 2. 构建 easycwmp 命令
    │     {"command":"get", "parameter":"参数路径"}
    │
    ├─> 3. 调用 easycwmp 获取参数值
    │   │
    │   ├─> easycwmp 内部处理:
    │   │     - 解析参数路径
    │   │     - 匹配数据模型节点
    │   │     - 调用对应的 get 函数
    │   │     - 从系统获取实际值 (UCI/UBus/Platform API)
    │   │
    │   └─> 返回参数值和类型
    │
    ├─> 4. 解析 easycwmp 返回的 JSON
    │     - 参数名、值、类型
    │     - 错误代码 (如有)
    │
    ├─> 5. 构建 GetParameterValuesResponse XML
    │     - ParameterList
    │     - Name、Value、Type
    │
    ├─> 6. 发送响应到 ACS
    │
    └─> 7. 继续等待下一个 RPC 请求
```

#### SetParameterValues 流程
```
收到 SetParameterValues 请求
    │
    ├─> 1. 解析 XML 请求
    │     - 提取 ParameterList
    │     - ParameterKey
    │
    ├─> 2. 对每个参数调用 easycwmp
    │     {"command":"set", "parameter":"路径", "argument":"值"}
    │
    ├─> 3. easycwmp 处理设置
    │   │
    │   ├─> 验证参数是否可写
    │   ├─> 验证参数值类型和范围
    │   ├─> 调用对应的 set 函数
    │   └─> 将值写入系统 (UCI/UBus/Platform API)
    │
    ├─> 4. 收集设置结果
    │     - Status 0=成功
    │     - FaultCode (如失败)
    │
    ├─> 5. 构建 SetParameterValuesResponse XML
    │     - Status
    │
    ├─> 6. 发送响应到 ACS
    │
    ├─> 7. 如需应用配置
    │     - 调用 {"command":"apply"}
    │     - 重启服务或应用配置
    │
    └─> 8. 继续等待下一个 RPC 请求
```

#### Download (固件升级) 流程
```
收到 Download 请求
    │
    ├─> 1. 解析 XML 请求
    │     - FileType (固件类型)
    │     - URL (下载地址)
    │     - Username/Password
    │     - FileSize
    │     - DelaySeconds
    │
    ├─> 2. 验证参数
    │     - 检查 FileType 是否支持
    │     - 检查 URL 格式
    │
    ├─> 3. 构建 DownloadResponse XML
    │     - Status (1=下载未完成)
    │     - StartTime
    │     - CompleteTime
    │
    ├─> 4. 发送响应到 ACS
    │
    ├─> 5. 备份下载任务
    │     - 保存到 backup 文件
    │     - 以便重启后恢复
    │
    ├─> 6. 添加 DOWNLOAD 事件
    │     - 延迟 DelaySeconds 后执行
    │
    ├─> 7. 定时器到期后执行下载
    │   │
    │   ├─> 调用 easycwmp download
    │   ├─> 使用 curl/wget 下载文件
    │   ├─> 验证文件 (MD5/SHA)
    │   ├─> 执行升级脚本
    │   │     - sysupgrade (OpenWrt)
    │   │     - 或自定义升级流程
    │   │
    │   └─> 可能触发系统重启
    │
    ├─> 8. 下载完成后
    │     - 准备 TransferComplete 事件
    │     - FaultCode (0=成功)
    │     - StartTime / CompleteTime
    │
    ├─> 9. 下次 Inform 时发送 TransferComplete
    │     - 事件代码: "7 TRANSFER COMPLETE"
    │     - 包含下载结果
    │
    └─> 10. ACS 确认 TransferComplete
          - 从备份中移除
```

### 3.4 ConnectionRequest 流程

```
ACS 发起 ConnectionRequest
    │
    ├─> 1. HTTP 服务器接收请求
    │     - 绑定在 CPE 的 7547 端口
    │     - 请求路径通常为 /
    │
    ├─> 2. 验证认证
    │     - Basic 或 Digest 认证
    │     - 用户名/密码验证
    │
    ├─> 3. 如果认证失败
    │     - 返回 401 Unauthorized
    │     - 包含 WWW-Authenticate header
    │
    ├─> 4. 认证成功
    │     - 返回 200 OK
    │     - 或 204 No Content
    │
    ├─> 5. 添加 CONNECTION REQUEST 事件
    │     - 事件代码: "6 CONNECTION REQUEST"
    │     - 添加到事件队列
    │
    ├─> 6. 触发 Inform
    │     - 立即触发定时器 (10秒)
    │
    └─> 7. 建立新的 CWMP 会话
          - 发送 Inform 到 ACS
          - 等待 ACS 的 RPC 请求
```

### 3.5 定期上报流程

```
系统运行中 (Periodic Inform)
    │
    ├─> 1. 启动时计算首次上报时间
    │     - 如果有 periodic_time (参考时间)
    │     │   └─> 计算到下个周期的时间差
    │     │
    │     └─> 否则使用 periodic_interval
    │
    ├─> 2. 设置定时器
    │     - uloop_timeout_set(&periodic_inform_timer, ...)
    │
    ├─> 3. 定时器到期
    │     - 回调函数: cwmp_periodic_inform()
    │
    ├─> 4. 添加 PERIODIC 事件
    │     - 事件代码: "2 PERIODIC"
    │     - 保存到备份文件
    │
    ├─> 5. 触发 Inform
    │     - 添加 inform_timer (10秒)
    │
    ├─> 6. 执行 Inform 会话
    │     - 连接 ACS
    │     - 发送设备信息
    │     - 处理 RPC 请求
    │
    ├─> 7. 会话结束后
    │     - 清除 PERIODIC 事件
    │
    ├─> 8. 重新设置下次定时器
    │     - periodic_interval 秒后
    │
    └─> 9. 循环往复
```

### 3.6 重试机制

```
Inform 发送失败 (网络错误/ACS 不可达)
    │
    ├─> 1. http_send_message() 返回错误
    │
    ├─> 2. 检查事件的重试策略
    │     - EVENT_REMOVE_NO_RETRY: 不重试
    │     - 其他: 需要重试
    │
    ├─> 3. 如果需要重试
    │     - 增加 retry_count
    │     - 保留事件在队列中
    │
    ├─> 4. 计算重试间隔
    │     - retry_count 1: 7 秒
    │     - retry_count 2: 15 秒
    │     - retry_count 3: 30 秒
    │     - retry_count 4: 60 秒
    │     - retry_count 5: 120 秒
    │     - retry_count 6: 240 秒
    │     - retry_count 7: 480 秒
    │     - retry_count 8: 960 秒
    │     - retry_count 9: 1920 秒
    │     - retry_count 10+: 3840 秒
    │
    ├─> 5. 设置重试定时器
    │     - uloop_timeout_set(&inform_timer_retry, ...)
    │
    ├─> 6. 定时器到期
    │     - 再次尝试 Inform
    │
    ├─> 7. 如果成功
    │     - 重置 retry_count = 0
    │     - 清除已确认的事件
    │
    └─> 8. 如果继续失败
          - 继续重试，间隔逐渐增大
          - 最大间隔 64 分钟
```

---

## 4. 关键技术点

### 4.1 进程间通信

#### easycwmpd ←→ easycwmp
- **机制**: Pipe (管道)
- **格式**: JSON
- **流程**:
  1. `easycwmpd` 创建 pipe: `pfds_in`, `pfds_out`
  2. `fork()` 子进程运行 `easycwmp`
  3. 父进程写入 JSON 命令到 `stdin`
  4. 子进程处理后输出 JSON 结果到 `stdout`
  5. 父进程读取并解析结果

#### 命令格式示例
```json
// Get 命令
{
  "command": "get",
  "parameter": "InternetGatewayDevice.DeviceInfo.SerialNumber"
}

// Set 命令
{
  "command": "set",
  "parameter": "InternetGatewayDevice.ManagementServer.URL",
  "argument": "http://acs.example.com:7547/"
}

// Inform 命令
{
  "command": "inform"
}
```

#### 响应格式示例
```json
// Get 响应
{
  "status": "0",
  "parameter": "InternetGatewayDevice.DeviceInfo.SerialNumber",
  "value": "SN123456789",
  "type": "xsd:string"
}

// Inform 响应
{
  "status": "0",
  "parameter": {
    "Manufacturer": "YourCompany",
    "SerialNumber": "SN123456789",
    "SoftwareVersion": "1.0.0"
  }
}
```

### 4.2 数据持久化

#### 配置文件: `/tmp/easycwmp.conf`
```json
{
    "local": {
        "interface": "4g",
        "port": "7547",
        "username": "cpe_user",
        "password": "cpe_pass",
        "authentication": "Digest",
        "logging_level": "3"
    },
    "acs": {
        "url": "http://192.168.1.100:80/acs",
        "username": "acs_user",
        "password": "acs_pass",
        "periodic_enable": "on",
        "periodic_interval": "1800"
    },
    "device": {
        "software_version": "1.0.0"
    }
}
```

#### 事件备份
- **文件**: 由 `backup.c` 管理
- **内容**: 未确认的事件、TransferComplete 信息
- **用途**: 重启后恢复待发送事件

#### 通知值变化
- **文件**: `/etc/config/easycwmp_notification` (持久)
- **工作副本**: `/tmp/easycwmp_notification`
- **内容**: 需要监控变化的参数列表及当前值

### 4.3 事件管理

#### 事件类型
```c
EVENT_BOOTSTRAP          // 0 BOOTSTRAP
EVENT_BOOT               // 1 BOOT
EVENT_PERIODIC           // 2 PERIODIC
EVENT_SCHEDULED          // 3 SCHEDULED
EVENT_VALUE_CHANGE       // 4 VALUE CHANGE
EVENT_KICKED             // 5 KICKED
EVENT_CONNECTION_REQUEST // 6 CONNECTION REQUEST
EVENT_TRANSFER_COMPLETE  // 7 TRANSFER COMPLETE
EVENT_DIAGNOSTICS_COMPLETE // 8 DIAGNOSTICS COMPLETE
EVENT_M_REBOOT           // M Reboot
EVENT_M_DOWNLOAD         // M Download
```

#### 事件策略
- **SINGLE**: 单次事件，同类型不重复
- **MULTIPLE**: 可多次添加
- **REMOVE_AFTER_INFORM**: Inform 后删除
- **REMOVE_AFTER_TRANSFER_COMPLETE**: TransferComplete 后删除
- **REMOVE_NO_RETRY**: 失败不重试，直接删除

### 4.4 HTTP 通信

#### HTTP 客户端 (到 ACS)
- **库**: libcurl
- **特性**:
  - 支持 HTTP/HTTPS
  - Basic/Digest 认证
  - SSL 证书验证
  - Cookie 管理
  - 30 秒超时

#### HTTP 服务器 (接收 ConnectionRequest)
- **实现**: 原生 socket
- **端口**: 可配置 (默认 7547)
- **认证**: Basic/Digest
- **功能**: 只处理 ConnectionRequest

### 4.5 XML/SOAP 消息处理

#### XML 解析
- **库**: libmicroxml (内置)
- **特性**: 轻量级、适合嵌入式

#### SOAP 命名空间
```xml
xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
xmlns:xsd="http://www.w3.org/2001/XMLSchema"
xmlns:cwmp="urn:dslforum-org:cwmp-1-0"  (或 1-1, 1-2)
```

#### RPC 方法支持
- GetRPCMethods
- SetParameterValues / GetParameterValues
- GetParameterNames / GetParameterAttributes / SetParameterAttributes
- AddObject / DeleteObject
- Download / Upload
- Reboot / FactoryReset
- ScheduleInform

---

## 5. 数据模型详解

### 5.1 数据模型结构

#### TR-098 (InternetGatewayDevice)
```
InternetGatewayDevice.
├── DeviceInfo.
│   ├── Manufacturer
│   ├── SerialNumber
│   ├── SoftwareVersion
│   └── ...
├── ManagementServer.
│   ├── URL
│   ├── Username
│   ├── Password
│   ├── PeriodicInformEnable
│   ├── PeriodicInformInterval
│   └── ConnectionRequestURL
├── Time.
├── DeviceConfig.
├── LANDevice.{i}.
├── WANDevice.{i}.
├── IPPingDiagnostics.
├── TraceRouteDiagnostics.
└── X_HD.  (自定义扩展)
```

#### TRZ4 数据模型 (自定义扩展)
基于 TR-098 扩展，添加了特定设备的参数。

### 5.2 参数节点映射

#### 节点定义示例 (tr098.c)
```c
cwmpnode_info cwmpnode_tr[] = {
    // 参数名                                      // Set函数
    cwmpodeNew(InternetGatewayDevice.DeviceInfo.SerialNumber, NULL),
    cwmpodeNew(InternetGatewayDevice.ManagementServer.URL, NULL),
    // ... 更多参数
};
```

#### 信息获取函数 (tr098_info.c)
```c
void tr_info_update() {
    // 清零结构体
    bzero(&InternetGatewayDevice, sizeof(tr098_ParamNode));
    
    // 调用各模块的信息获取函数
    tr098_info_BaseInfo(&InternetGatewayDevice);
    common_info_DeviceInfo(&InternetGatewayDevice.DeviceInfo);
    common_info_ManagementServer(&InternetGatewayDevice.ManagementServer);
    // ...
}
```

#### 参数设置函数 (tr098_set.c)
```c
int tr_set_ManagementServer_URL(char *value) {
    // 验证参数
    // 调用系统 API 设置
    // 返回结果
}
```

### 5.3 命令处理映射

```c
static cwmpfunc func_list[] = {
    {"exit",                cwmpfunc_exit},
    {"end",                 cwmpfunc_end},
    {"apply",               cwmpfunc_apply},
    {"factory_reset",       cwmpfunc_reset},
    {"update_value_change", cwmpfunc_update},
    {"reboot",              cwmpfunc_reboot},
    {"inform",              cwmpfunc_inform},
    {"set",                 cwmpfunc_operate},
    {"get",                 cwmpfunc_operate},
    {"add",                 cwmpfunc_operate},
    {"delete",              cwmpfunc_operate},
    {"download",            cwmpfunc_download},
    {"upload",              cwmpfunc_upload},
    {"ping",                cwmpfunc_ping},
    {"traceroute",          cwmpfunc_traceroute},
};
```

---

## 6. 诊断功能

### 6.1 IPPing 诊断
- **参数**: Host, NumberOfRepetitions, Timeout, DataBlockSize, DSCP
- **执行**: 调用 `cwmpDiagnostics` 工具或系统 `ping` 命令
- **结果**: SuccessCount, FailureCount, AverageResponseTime, MinimumResponseTime, MaximumResponseTime

### 6.2 TraceRoute 诊断
- **参数**: Host, NumberOfTries, Timeout, DataBlockSize, MaxHopCount
- **执行**: 调用系统 `traceroute` 命令
- **结果**: ResponseTime, RouteHops (每一跳的信息)

### 6.3 诊断状态
- `None`: 未执行
- `Requested`: 已请求
- `Complete`: 已完成
- `Error_XXX`: 各种错误状态

---

## 7. 扩展功能

### 7.1 UBus 集成
- **用途**: 与 OpenWrt 系统其他组件通信
- **功能**: 
  - 注册 UBus 服务
  - 接收系统事件
  - 调用其他服务

### 7.2 XMPP 支持 (可选)
- **库**: libstrophe
- **用途**: 支持 XMPP 连接方式 (TR-069 Amendment 5)
- **编译选项**: `HAVE_XMPP`

### 7.3 值变化通知
- **机制**: 定期检查配置的参数值是否变化
- **定时器**: 由 `notify_timer` 控制
- **动作**: 如值变化，添加 VALUE_CHANGE 事件并 Inform

---

## 8. 安全性

### 8.1 认证方式
- **CPE 到 ACS**: Basic / Digest (libcurl 自动处理)
- **ACS 到 CPE**: Basic / Digest (自实现)

### 8.2 SSL/TLS
- **支持**: HTTPS
- **证书验证**: 可配置开启/关闭
- **客户端证书**: 支持配置

### 8.3 密码保护
- **配置文件**: `/tmp/easycwmp.conf` (敏感，应设置权限)
- **ManagementServer.Password**: 只写属性，Get 时返回空

---

## 9. 编译与部署

### 9.1 编译依赖
```
libubus, libuci, libubox, libjson-c, libcurl
curl, libapplowlevel, libcJSON, libconfiguration
libplatform, jshn, libstrophe (可选-XMPP)
```

### 9.2 编译选项
```makefile
# 数据模型选择 (四选一)
-DDATA_MODEL_TR098      # TR-098
-DDATA_MODEL_TR181      # TR-181
-DDATA_MODEL_TRH101C    # TRH101C 自定义
-DDATA_MODEL_TRZ4       # TRZ4 自定义

# 可选功能
-DHAVE_XMPP             # 启用 XMPP
-DUSE_UBUS              # 启用 UBus
-DHD_CUSTOM             # 宏定义自定义功能
```

### 9.3 编译步骤
```bash
# 方式1: 独立编译
make

# 方式2: OpenWrt 编译
# 将 osdt-easycwmp-make.zip 解压到 package/hongdian/apps
# make menuconfig 选择 easycwmp
# make package/easycwmp/compile V=s
```

### 9.4 安装文件
```
/usr/bin/easycwmpd           # 守护进程
/usr/bin/easycwmp            # CLI 工具
/usr/bin/cwmpDiagnostics     # 诊断工具
/etc/init.d/tr069            # 启动脚本
/etc/config/tr069            # UCI 配置
/tmp/easycwmp.conf           # 运行时配置
```

---

## 10. 运行时文件

### 10.1 配置文件
| 文件路径 | 用途 |
|---------|------|
| `/tmp/easycwmp.conf` | 主配置文件 (JSON) |
| `/etc/config/tr069` | UCI 配置 |
| `/etc/easycwmp_notification` | 值变化通知配置 (持久) |
| `/tmp/easycwmp_notification` | 值变化通知工作副本 |

### 10.2 运行时文件
| 文件路径 | 用途 |
|---------|------|
| `/var/run/easycwmpd.pid` | 进程 PID 文件 |
| `/tmp/.cwmp_backup` | 事件备份文件 (假设) |
| `/tmp/.cwmp_transfer_complete` | TransferComplete 备份 |
| `/tmp/.cwmp.IPPingDiagnostics.json` | Ping 诊断结果 |
| `/tmp/.cwmp.TraceRouteDiagnostics.json` | Traceroute 诊断结果 |
| `/tmp/.cwmp.DownloadDiagnostics.json` | 下载诊断结果 |
| `/tmp/.cwmp.UploadDiagnostics.json` | 上传诊断结果 |
| `/tmp/easycwmp_cookies` | HTTP Cookie 文件 |

---

## 11. 调试与日志

### 11.1 日志级别
```c
L_CRIT    = 0,  // Critical
L_WARNING = 1,  // Warning
L_NOTICE  = 2,  // Notice
L_INFO    = 3,  // Info
L_DEBUG   = 4   // Debug
```

配置: `local.logging_level` in `/tmp/easycwmp.conf`

### 11.2 日志输出
- **方式**: syslog
- **查看**: `logread | grep easycwmp`

### 11.3 调试编译
```makefile
# 启用详细日志
CFLAGS += -DDEBUG       # 一般调试
CFLAGS += -DDEVEL       # 开发调试 (更详细)
```

### 11.4 抓包分析
```bash
# 抓取 ACS 通信
tcpdump -i any -s 0 -w /tmp/cwmp.pcap port 80 or port 7547

# 使用 Wireshark 分析 SOAP/XML 消息
```

---

## 12. 常见流程时序图

### 12.1 完整 Inform 会话时序

```
CPE (easycwmpd)         easycwmp              ACS Server
      |                     |                       |
      |--[定时器到期]-------->                       |
      |                     |                       |
      |--fork/pipe--------->|                       |
      |                     |                       |
      |--{"command":"inform"}|                      |
      |                     |                       |
      |                     |--[获取设备信息]        |
      |                     |--[读取数据模型]        |
      |                     |                       |
      |<--[JSON设备信息]-----|                       |
      |                     |                       |
      |--[构建Inform XML]--->                       |
      |                                             |
      |----------[HTTP POST Inform]---------------->|
      |                                             |
      |<---------[InformResponse]--------------------|
      |                                             |
      |--[清除已确认事件]-->                         |
      |                                             |
      |<---------[空POST或RPC请求]-------------------|
      |                                             |
      |--[如有RPC]--------->                         |
      |                     |                       |
      |--fork/pipe--------->|                       |
      |--{"command":"get"}->|                       |
      |<--[返回参数值]-------|                       |
      |                     |                       |
      |----------[RPC Response]-------------------->|
      |                                             |
      |<---------[空POST或下一RPC]-------------------|
      |                                             |
      |-----[循环处理直到ACS空POST]----------------->|
      |                                             |
      |<---------[空POST]----------------------------|
      |                                             |
      |----------[204 No Content]------------------>|
      |                                             |
      |--[会话结束]------->                          |
      |                                             |
```

---

## 13. 总结

### 13.1 架构优势
1. **模块化设计**: 守护进程与数据模型分离
2. **多数据模型支持**: 编译时选择，灵活适配
3. **标准协议**: 完整实现 TR-069 规范
4. **嵌入式优化**: 适合路由器等资源受限设备
5. **可扩展性**: 易于添加自定义参数和功能

### 13.2 关键组件
- **easycwmpd**: 协议引擎，事件驱动
- **easycwmp**: 数据模型实现，参数操作
- **libcurl**: HTTP 客户端通信
- **libmicroxml**: XML 解析
- **libubox/uloop**: 事件循环框架

### 13.3 核心机制
- **事件驱动**: uloop 管理定时器和 I/O
- **进程通信**: Pipe + JSON
- **会话管理**: Inform → RPC循环 → 空POST结束
- **可靠性**: 事件备份 + 重试机制

### 13.4 适用场景
- 家庭网关 / 路由器
- 工业物联网设备
- 需要远程管理的 CPE 设备
- OpenWrt / 嵌入式 Linux 系统

---

## 附录

### A. 参考文档
- TR-069 Amendment 6 (Broadband Forum)
- TR-098 Internet Gateway Device Data Model
- TR-181 Device:2 Data Model
- TR-069.pdf (项目根目录)

### B. 相关链接
- 原始仓库: http://172.16.8.42/oversea/z1_se (odm-STC分支)

### C. 版本信息
- EasyCWMP 版本: 1.8.6
- 协议版本: CWMP 1.0 / 1.1 / 1.2

---

**文档生成时间**: 2025-11-06  
**项目路径**: `X:\gitlab\Z4\build\package_build\easycwmp`  
**作者**: AI 架构分析

