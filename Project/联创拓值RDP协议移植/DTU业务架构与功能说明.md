# DTU业务架构与功能说明文档

## 1. 项目概述

### 1.1 什么是DTU
DTU（Data Transfer Unit，数据传输单元）是一个嵌入式设备通信模块，主要用于工业物联网场景中实现：
- **数据采集**：从串口设备（如传感器、仪表）采集数据
- **协议处理**：支持多种通信协议（TCP/UDP/DDP）
- **远程传输**：通过蜂窝网络（2G/3G/4G）将数据传输到数据中心
- **双向通信**：支持数据中心下发指令到现场设备

### 1.2 应用场景
- 工业自动化设备远程监控
- 传感器数据采集与上报
- 远程设备控制与参数配置
- 环境监测数据传输

---

## 2. 总体架构设计

### 2.1 架构模式
```
┌─────────────────────────────────────────────────────────────┐
│                      DTU 主控制器                            │
│                    (dtu_ctrl.c)                             │
└────────────┬────────────────────────────────┬───────────────┘
             │                                │
     ┌───────▼────────┐              ┌───────▼────────┐
     │  串口通信层     │              │  网络通信层     │
     │  (RS232)       │              │  (Socket)      │
     └───────┬────────┘              └───────┬────────┘
             │                                │
     ┌───────▼────────┐              ┌───────▼────────┐
     │  RDP协议处理   │              │  DDP协议处理   │
     │  (rdp.c)       │              │ (droute_loop)  │
     └───────┬────────┘              └───────┬────────┘
             │                                │
     ┌───────▼────────┐              ┌───────▼────────┐
     │  设备信息管理   │              │  连接管理       │
     │(rdp_devinfo.c) │              │ (dtu_conn.c)   │
     └────────────────┘              └────────────────┘
```

### 2.2 工作模式
- **客户端模式（Client）**：主动连接数据中心服务器（最常用）
- **服务器模式（Server）**：作为服务器等待连接（较少使用）

### 2.3 支持的协议
1. **TCP协议**：可靠的字节流传输
2. **UDP协议**：无连接的数据报传输
3. **DDP协议**：自定义的设备数据协议（Device Data Protocol）

---

## 3. 核心模块功能详解

### 3.1 主控制模块 (dtu_ctrl.c/h)

#### 功能职责
- 系统初始化和配置加载
- 主循环调度和流程控制
- 信号处理（SIGTERM、SIGCHLD）
- 多中心服务器支持（双中心/三中心）

#### 关键数据结构
```c
typedef struct dtu_config {
    char mode;                      // 'c'=客户端, 's'=服务器
    char protocol;                  // 't'=TCP, 'u'=UDP
    char keepalive;                 // TCP保活开关
    int keepalive_interval;         // 保活间隔
    int connect_times;              // 连接重试次数
    int reconnect_interval;         // 重连间隔
    data_frame_t data;              // 数据帧参数
    server_param_t server[4];       // 最多支持4个服务器
    heartbeat_param_t heartbeat;    // 心跳参数
    char key[65];                   // AES加密密钥
    int encry_id;                   // 加密ID
    char logindata[65];             // 登录数据
} dtu_t;
```

#### 主要流程
```
1. init_config()           // 从配置文件加载参数
2. init_signal()           // 安装信号处理器
3. dtu_check_interface()   // 检查网络接口
4. open_rs232()            // 打开串口
5. init_rs232()            // 初始化串口参数
6. 主循环:
   - 检查网络链路
   - 建立服务器连接
   - data_process()        // 数据处理主循环
```

### 3.2 连接管理模块 (dtu_conn.c)

#### 功能职责
- TCP/UDP连接建立
- DNS解析
- 连接重试机制
- TCP KeepAlive配置
- 本地端口绑定

#### 关键函数
```c
// 服务器连接主函数
int connect_server(dtu_t *dtu_p, int rs232_fd);

// TCP连接
int tcp_conn(uint32_t int_svr_ip, int port, int conn_time_out, dtu_t *dtu);

// UDP连接
int udp_conn(uint32_t int_svr_ip, int port, dtu_t *dtu);

// DNS解析
int get_svr_ip(char *svr_name_str, uint32_t *ip_int);

// TCP保活设置
int set_keepalive(int tcp_sockfd, int keepalive, int sleeptime);
```

#### TCP KeepAlive参数
- **idle_time**: 300秒（5分钟）
- **intvl**: 60秒
- **cnt**: 3次

### 3.3 数据路由循环模块 (droute_loop.c)

#### 功能职责
- 串口与网络之间的双向数据转发
- DDP协议封装与解析
- 心跳包生成与发送
- 数据缓冲管理
- RDP协议识别

#### 核心函数
```c
// 主数据处理循环（定义在后续代码中）
int data_process(int rs232_fd, int sock, dtu_t *options);

// 构造DDP登录包
int make_ddp_login_package(int channel, char *ret_buf, int buf_size, int tmp);

// 构造DDP心跳包
int make_ddp_heartbeat_package(int channel, char *ret_buf, int buf_size, int tmp);

// 构造DDP数据包
int make_ddp_data_package(int mode, u8 *src_buf, int src_len, u8 *target, int length);

// Socket读取
static int socket_read_len(int fd, char* buf, ssize_t len, int msec, heartbeat_param_t* heart);

// Socket写入
int socket_write_len(int fd, char* buf, ssize_t len, int msec);
```

#### DDP协议格式
```
TCP格式: 7B 09/89 XX XX DTUID 数据 7B
UDP格式: 7B 09/89 00 10 DTUID 7B 数据

字段说明:
- 7B: 起始/结束标志
- 09/89: 数据类型（09=DTU上传，89=DSC下发）
- XX XX: 数据长度（网络字节序）
- DTUID: 11字节设备ID
```

### 3.4 RDP协议模块 (rdp.c/h)

#### 功能职责
- RDP（Remote Device Protocol）协议处理
- 串口命令队列管理
- 设备状态查询响应
- 参数设置/获取

#### RDP帧格式
```
┌─────┬─────┬──────┬──────────┬─────┬─────┐
│ HEAD│ LEN │ TYPE │   DATA   │ CRC │ REAR│
│ 3B  │ 2B  │  2B  │ LEN-11B  │ 1B  │ 3B  │
└─────┴─────┴──────┴──────────┴─────┴─────┘

- HEAD: 0x7D7D7D (3字节)
- LEN:  帧总长度（网络字节序）
- TYPE: 命令类型（网络字节序）
- DATA: 数据部分
- CRC:  CRC8校验
- REAR: 0x7F7F7F (3字节)
```

#### 支持的命令类型
```c
// RTU -> DTU 命令
RTU_DTU_CMD_GET_PARAM       = 0x01  // 获取参数
RTU_DTU_CMD_SET_PARAM       = 0x02  // 设置参数
RTU_DTU_CMD_SAVE_PARAM      = 0x03  // 保存参数
RTU_DTU_CMD_RESET_DTU       = 0x04  // 复位DTU
RTU_DTU_CMD_SEND_DATA       = 0x05  // 发送数据
RTU_DTU_CMD_SEND_SMS        = 0x06  // 发送短信
RTU_DTU_CMD_GET_DTU_STATUS  = 0x07  // 获取DTU状态
RTU_DTU_CMD_CTRL_GPIO       = 0x08  // 控制GPIO
RTU_DTU_CMD_GET_GPIO_INFO   = 0x09  // 获取GPIO信息

// DTU -> RTU 响应
DTU_RTU_CMD_GET_PARAM_R     = 0x81
DTU_RTU_CMD_SET_PARAM_R     = 0x82
// ... (响应码 = 请求码 + 0x80)
```

#### 队列机制
- **输入队列（inq）**：存储从串口接收的RDP命令
- **输出队列（outq）**：存储待发送到串口的RDP响应
- **线程模型**：
  - 输入线程：`process_input_entry()` 处理接收到的命令
  - 输出线程：`process_output_entry()` 发送响应数据

### 3.5 设备信息模块 (rdp_devinfo.c/h)

#### 功能职责
- 获取Modem模块信息（信号强度、运营商、IMEI等）
- 获取SIM卡信息（ICCID、IMSI等）
- 获取系统信息（版本号、运行时间等）
- PLMN（运营商网络）解析

#### 关键功能
```c
// 获取设备状态
char *get_dev_status(char *data, int dlen, short *len);

// 从文件读取配置项
int get_item_value(const char *file, const char *key, char *val, int vlen);

// Modem1信息获取
int modem1_getv_def(info_unit_t *iut);

// Modem2信息获取
int modem2_getv_def(info_unit_t *iut);

// 系统信息获取
int sys_getv_def(info_unit_t *iut);
```

#### 信息源文件
- `/tmp/modem.info` - Modem1模块信息
- `/tmp/modem2.info` - Modem2模块信息
- `/tmp/sys.info` - 系统信息

### 3.6 PLMN解析模块 (resolv_plmn.c/h)

#### 功能职责
根据IMSI号识别运营商网络名称

#### 工作原理
- 读取PLMN配置文件
- 匹配IMSI前5位（MCC+MNC）
- 返回对应的运营商名称

#### 示例
```
IMSI: 46000XXXXXXXXX
前5位: 46000
匹配结果: 中国移动
```

### 3.7 CRC校验模块 (crc7.c/h)

#### 功能职责
提供CRC8校验算法

---

## 4. 多中心服务器支持

### 4.1 双中心模式 (DOUBLE_CENTER)
- 支持主服务器和备份服务器
- 主服务器连接失败时自动切换到备份服务器
- 轮询机制确保连接可用性

### 4.2 三中心模式 (treble_center) - 当前启用
- 支持最多3个数据中心
- 两种工作模式：
  - **多通道模式**：同时连接3个服务器
  - **主备模式**：仅连接主服务器和一个备份服务器

#### 关键函数
```c
// 初始化三中心配置
int inti_treble_center(dtu_t* dtu_tmp);

// 三中心连接
int treble_center_connect(dtu_t *dtu_tmp, int rs232_fd);

// 三中心接口检查
int treble_center_check_interface();
```

#### 全局结构
```c
typedef struct _treble_socket_t {
    int sock[3];          // 3个Socket连接
    int sock_err[3];      // 错误标志
} Treble_socket_t;

Treble_socket_t g_treble_sock;  // 全局三中心Socket
```

---

## 5. 数据加密功能

### 5.1 AES加密
- **算法**：AES-ECB模式
- **密钥长度**：支持128/192/256位
- **应用场景**：敏感数据传输加密

### 5.2 关键函数
```c
// AES加密
void aes_box_encrypt(char *source_string, char *dest_string);

// AES解密
void aes_box_decrypt(char *source_string, char *dest_string);

// AES + Base64编码
void AES_ENCODE(char *in_buf, char *out_buf);

// Base64解码 + AES解密
int AES_DECODE(char *encode_buf, int len, char *out_buf);
```

---

## 6. 串口通信

### 6.1 支持的串口设备
- `/dev/ttyXRUSB0` (COM1)
- `/dev/ttyXRUSB1` (COM2)

### 6.2 串口参数
从配置文件读取：
- 波特率（Baudrate）
- 数据位（Data bits）
- 停止位（Stop bits）
- 校验位（Parity）
- 流控制（Flow control）

---

## 7. 配置管理

### 7.1 配置来源
通过 `cli_api.h` 提供的接口从配置文件加载参数：
```c
struct dtu_paremeter_struct {
    char mode_pare[32];              // 工作模式
    char protocol_pare[32];          // 协议类型
    char destination_pare[128];      // 主服务器地址
    char server_port_pare[16];       // 主服务器端口
    char destination_bak_pare[128];  // 备份服务器地址
    char server_port_bak_pare[16];   // 备份服务器端口
    char destination_bak2_pare[128]; // 第二备份服务器
    char server_port_bak2_pare[16];  // 第二备份端口
    char serial_com_pare[32];        // 串口选择
    char channel_type_pare[32];      // 通道类型（treble/double）
    // ... 更多配置项
};
```

### 7.2 配置加载流程
```c
static int init_config() {
    // 1. 初始化默认值
    memset(&dtu, 0, sizeof(dtu));
    
    // 2. 从配置文件读取
    cli_config_get(&dtu_paremeter, sizeof(struct dtu_paremeter_struct), SAME_PARE_ON);
    
    // 3. 解析配置项
    // - 工作模式（client/server）
    // - 协议类型（TCP/UDP/DDP）
    // - 服务器地址和端口
    // - 加密密钥
    // - 心跳参数
    
    // 4. 返回配置结果
    return 0;
}
```

---

## 8. 心跳机制

### 8.1 心跳目的
- 保持连接活跃
- 检测网络断线
- 定期上报设备状态

### 8.2 心跳流程
```
1. 定时器触发（heartbeat_interval秒）
2. 构造心跳包（DDP或自定义格式）
3. 发送到数据中心
4. 等待响应
5. 超时未响应则标记连接异常
```

### 8.3 心跳参数
```c
typedef struct heartbeat_param_st {
    char heartbeat;              // 心跳开关
    int  heartbeat_interval;     // 心跳间隔（秒）
    char router_id[12];          // 设备ID（11字节+'\0'）
    char content[1024];          // 心跳内容
} heartbeat_param_t;
```

---

## 9. 异常处理与容错

### 9.1 链路检查
```c
int dtu_check_interface() {
    // 1. 服务器模式直接返回成功
    // 2. 客户端模式检查到服务器的路由
    // 3. 路由接口变化时返回错误，触发重连
}
```

### 9.2 重连机制
- 连接失败自动重试
- 可配置重试次数（svr_connect_times）
- 可配置重试间隔（svr_connect_interval）
- 可配置总重连间隔（reconnect_interval）

### 9.3 信号处理
```c
// SIGCHLD - 子进程退出处理
// SIGTERM - 优雅退出处理
void sig_process(int signo);
```

---

## 10. 关键业务流程

### 10.1 客户端模式启动流程
```
1. 加载配置文件
   ↓
2. 初始化信号处理器
   ↓
3. 检查网络接口可达性
   ↓
4. 打开并初始化串口
   ↓
5. 连接数据中心服务器
   │
   ├─ DNS解析
   ├─ TCP/UDP连接
   ├─ 登录认证（如果配置）
   └─ 注册DDP（如果使用DDP协议）
   ↓
6. 进入数据转发循环
   │
   ├─ 从串口读数据 → 封装协议 → 发送到服务器
   ├─ 从服务器读数据 → 解析协议 → 发送到串口
   ├─ 定期发送心跳包
   ├─ 检查网络状态
   └─ 处理RDP命令（如果有）
   ↓
7. 异常时断开连接
   ↓
8. 返回步骤3重新开始
```

### 10.2 数据转发流程（简化）
```c
while (1) {
    // 1. 使用select监听串口和网络Socket
    select(maxfd, &rset, NULL, NULL, &timeout);
    
    // 2. 串口有数据
    if (FD_ISSET(rs232_fd, &rset)) {
        // 读取串口数据
        len = rs232_read_len(rs232_fd, buf, sizeof(buf), timeout);
        
        // 检查是否是RDP协议
        if (is_rdp(buf, len, &rdp_len, &off)) {
            // RDP协议单独处理（加入队列）
            continue;
        }
        
        // 封装为DDP包（如果需要）
        if (DDP_TYPE == app_type) {
            len = make_ddp_data_package(mode, buf, len, send_buf, sizeof(send_buf));
        }
        
        // 发送到服务器
        socket_write_len(sock, send_buf, len, timeout);
    }
    
    // 3. 网络Socket有数据
    if (FD_ISSET(sock, &rset)) {
        // 读取网络数据
        len = socket_read_len(sock, buf, sizeof(buf), timeout, &heartbeat);
        
        // 解析DDP包（如果需要）
        if (DDP_TYPE == app_type) {
            // 去掉DDP头，提取数据部分
        }
        
        // 发送到串口
        rs232_write_len(rs232_fd, buf, len, timeout);
    }
    
    // 4. 心跳定时器
    if (time_to_send_heartbeat()) {
        send_heartbeat(sock);
    }
    
    // 5. 链路检查
    if (link_error_detected()) {
        break;  // 退出循环，触发重连
    }
}
```

### 10.3 DDP协议注册流程
```
1. 建立TCP/UDP连接
   ↓
2. 构造DDP注册包
   - 起始标志: 0x7B
   - 命令类型: 0x01 (DDP_DTU_TYPE_REGISTER)
   - 包长度: 22字节
   - DTU ID: 11字节设备编号
   - 本地IP: 4字节
   - 本地端口: 2字节
   - 结束标志: 0x7B
   ↓
3. 发送注册包到服务器
   ↓
4. 等待服务器响应
   - 响应类型: 0x81 (DDP_DSC_TYPE_REG_ACK)
   ↓
5. 注册成功，标记状态
```

---

## 11. 编译与部署

### 11.1 编译命令
```bash
make
```

### 11.2 清理
```bash
make clean
```

### 11.3 安装
```bash
make DESTBIN=/usr/bin install
```

### 11.4 编译选项
- `COMPILE_PATCH_VERSION`: 版本号
- `-DBIN_VERSION`: 二进制版本宏
- `-lcrypto`: 链接OpenSSL加密库
- `-lpthread`: 链接POSIX线程库

---

## 12. 代码模块依赖关系

```
dtu_ctrl (主控制器)
  ├── dtu_conn (连接管理)
  ├── droute_loop (数据转发)
  │     ├── rdp (RDP协议)
  │     │     ├── rdp_devinfo (设备信息)
  │     │     │     └── resolv_plmn (PLMN解析)
  │     │     └── crc7 (CRC校验)
  │     └── dtu_base_define (基础定义)
  ├── rs232_ctrl (串口控制) [外部库]
  ├── cli_api (配置API) [外部库]
  └── index (通用头文件) [外部库]
```

---

## 13. 常见问题排查

### 13.1 无法连接服务器
**现象**：日志显示"Failed to connect"

**排查步骤**：
1. 检查网络是否正常：`ping <服务器IP>`
2. 检查路由是否正确：`route -n`
3. 检查配置文件中的服务器地址和端口
4. 检查防火墙规则
5. 查看DNS解析是否成功

### 13.2 串口无数据
**现象**：网络正常，但串口无数据交互

**排查步骤**：
1. 检查串口设备是否存在：`ls -l /dev/ttyXRUSB*`
2. 检查串口参数配置（波特率、数据位等）
3. 使用串口调试工具测试物理连接
4. 检查DTU日志中的串口初始化信息

### 13.3 频繁断线重连
**现象**：连接建立后很快断开

**排查步骤**：
1. 检查心跳配置是否正确
2. 检查TCP KeepAlive参数
3. 查看网络信号质量
4. 检查服务器端是否有超时踢出机制

### 13.4 RDP命令无响应
**现象**：发送RDP命令后无响应

**排查步骤**：
1. 确认RDP帧格式正确（HEAD/REAR标志）
2. 检查CRC校验
3. 查看队列是否堵塞
4. 检查命令类型是否支持

---

## 14. 开发建议

### 14.1 调试技巧
1. 启用DEBUG宏：在`dtu_ctrl.c`中定义`#define _DEBUG`
2. 查看日志输出：使用`msg()`函数打印调试信息
3. 抓包分析：使用tcpdump抓取网络包
4. 串口监控：使用minicom或其他工具监听串口数据

### 14.2 新增协议支持
1. 在`dtu_base_define.h`中定义协议常量
2. 在`droute_loop.c`中实现协议封装/解析函数
3. 在主循环中添加协议判断逻辑
4. 更新配置文件支持新协议类型

### 14.3 新增设备信息
1. 在`rdp_devinfo.c`中添加信息获取函数
2. 在`rdp_devinfo.h`中定义信息单元
3. 在`get_dev_status()`中注册新信息项

### 14.4 代码规范
- 函数命名：小写字母+下划线（如：`dtu_check_interface`）
- 宏定义：大写字母+下划线（如：`DDP_B_FLAG`）
- 结构体：小写字母+下划线+`_t`后缀（如：`dtu_t`）
- 注释：使用中英文混合，关键逻辑必须注释

---

## 15. 关键宏定义

```c
// 工作模式
#define treble_center           // 启用三中心模式
//#define DOUBLE_CENTER         // 双中心模式（未启用）
//#define HEIMDAL               // 本地服务器模式（未启用）

// 缓冲区大小
#define DROUTE_MAXBUF    4096*8    // 数据缓冲区
#define BUFLEN           512        // 通用缓冲区

// 协议相关
#define DDP_B_FLAG       0x7B       // DDP起始/结束标志
#define RDP_HEAD_SIGN    0x7D       // RDP帧头标志
#define RDP_REAR_SIGN    0x7F       // RDP帧尾标志

// 设备
#define COM1_DEVICE "/dev/ttyXRUSB0"
#define COM2_DEVICE "/dev/ttyXRUSB1"

// 文件路径
#define MODEM_INFO_FILE  "/tmp/modem.info"
#define MODEM2_INFO_FILE "/tmp/modem2.info"
#define SYS_INFO_FILE    "/tmp/sys.info"
```

---

## 16. 总结

### 16.1 系统特点
✅ **优点**：
- 模块化设计，职责清晰
- 支持多种协议和工作模式
- 完善的异常处理和重连机制
- 支持多中心容灾
- 支持数据加密
- RDP协议提供丰富的设备管理功能

⚠️ **注意事项**：
- 代码中存在条件编译宏，需根据需求选择
- 部分函数依赖外部库（cli_api、index等）
- 配置文件格式需与系统匹配
- 多线程操作需注意线程安全

### 16.2 快速上手建议
1. **先理解整体流程**：从`main()`函数开始，了解启动流程
2. **聚焦核心模块**：重点关注`dtu_ctrl.c`和`droute_loop.c`
3. **阅读协议定义**：理解DDP和RDP协议格式
4. **动手实践**：编译运行，结合日志理解代码
5. **逐步深入**：根据需求深入研究各子模块

### 16.3 扩展方向
- 添加新的通信协议支持
- 优化数据缓冲机制
- 增强安全性（TLS/SSL）
- 支持更多设备类型
- 添加本地存储和离线缓存
- Web配置界面

---

**文档版本**：v1.0  
**生成时间**：2025-11-24  
**适用版本**：当前DTU代码版本
