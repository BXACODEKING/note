# RDP设备信息查询模块

## 概述

本模块实现了RDP协议的设备状态查询功能(0x07命令)，参考Z1-ODM lctz客户实现，支持双Modem和三种卡模式。

## 核心设计思想

### 架构特点 (参考Z1实现)

- **函数复用**: ~20个函数通过key参数复用，支持41个TAG查询
- **泛型设计**: 使用`info_unit_t`数组 + 函数指针实现按需查询
- **按需查询**: 只调用请求的TAG的获取函数，避免无效IO操作
- **全量查询**: 支持一次性获取所有TAG数据

### 函数数量对比

| 实现方式 | 函数总数 | 说明 |
|---------|---------|------|
| ❌ 每TAG一个函数 | 41个 | 过度设计 |
| ✅ Z1实际实现 | ~18个 | 通用函数+泛型函数 |
| ✅ 当前实现 | ~20个 | 参考Z1 + Z4适配 |

## 文件说明

### 1. RDP_devinfo.h

定义TAG枚举、数据结构和外部接口：

```c
// TAG定义
TAG_MODEM1_START = 0xF001  // Modem1: 0xF001~0xF00E (14项)
TAG_MODEM2_START = 0xF021  // Modem2: 0xF021~0xF02E (14项)
TAG_SYS_START    = 0xF051  // System: 0xF051~0xF05C (12项)
TAG_NET_START    = 0xF071  // Network: 0xF071~ (1项+)

// 外部接口
char *rdp_devinfo_get_status(char *in, int inlen, int *olen);
```

### 2. RDP_devinfo.c

实现设备信息获取逻辑：

#### **工具函数**
- `get_item_value()` - 从文件读取key-value
- `get_sim_value()` - 根据sim_select读取SIM卡信息
- `get_module_lice()` - 读取卡模式配置
- `get_operator_by_imsi()` - 根据IMSI判断运营商

#### **Modem通用函数 (modem1/modem2复用)**
```c
modem_get_exist()        // 存在性 (通过iut->key区分modem1/modem2)
modem_get_sim_state()    // SIM卡状态
modem_get_dialup_state() // 拨号状态
modem_get_csq()          // 信号强度
modem_get_online_time()  // 在线时长
modem_get_cell()         // 小区值
modem_get_vender()       // 厂商
modem_get_operator()     // 运营商
modem_get_model()        // 型号
modem_get_ip()           // IP地址
```

#### **泛型函数 (通过iut->key读取不同字段)**
```c
modem1_getv_def()        // Modem1泛型读取 (nettype, meid等)
modem1_sim_getv_def()    // Modem1 SIM字段读取 (imsi, iccid)
modem2_getv_def()        // Modem2泛型读取
modem2_sim_getv_def()    // Modem2 SIM字段读取
sys_getv_def()           // 系统信息泛型读取
```

#### **特殊函数**
```c
gps_info()               // GPS定位
net_defrt()              // 默认路由
```

#### **核心查询函数**
```c
get_all_tags()           // 获取全部41个TAG
get_part_tags()          // 按TAG列表查询 (核心按需查询)
```

### 3. RDP_parse.c (集成修改)

在`getStatusCmdProc()`函数中集成设备信息查询：

```c
// 1. 检测设备信息TAG (0xF001~0xF0FF)
if (first_tag >= 0xF001 && first_tag <= 0xF0FF) {
    devinfo_buf = rdp_devinfo_get_status((char*)data, dataLength, &devinfo_len);
    // 返回TLV数据
}

// 2. 全量查询 (无TAG列表)
if (dataLength == 0 || GET_ALL == subFuncCode) {
    devinfo_buf = rdp_devinfo_get_status(NULL, 0, &devinfo_len);
}

// 3. 原有标准DTU状态查询逻辑保持不变
```

## 三种卡模式支持

### Module_Lice配置

读取自`/etc/hdconfig/sysinfo/system.info`中的`Module_Lice`字段：

| 值 | 模式 | 文件 | SIM卡处理 |
|----|------|------|----------|
| 1 | 单模单卡 | /tmp/modem.info | 只有sim1 |
| 2 | 单模双卡 | /tmp/modem.info | sim1和sim2在同一文件，根据sim_select切换 |
| 3 | 双模双卡 | /tmp/modem.info<br>/tmp/modem2.info | 两个文件，各有sim_select |

### 卡模式处理逻辑

```c
// 单模单卡 (Module_Lice=1)
- 只读取 /tmp/modem.info
- 只有modem1，没有modem2
- 固定读取sim1信息

// 单模双卡 (Module_Lice=2)
- 只读取 /tmp/modem.info
- 只有modem1，没有modem2
- 根据sim_select (1或2) 选择sim1或sim2 section

// 双模双卡 (Module_Lice=3)
- 读取 /tmp/modem.info (modem1)
- 读取 /tmp/modem2.info (modem2)
- 每个文件有独立的sim_select
```

## 使用示例

### 1. 按TAG查询 (按需查询)

```c
// 请求TAG列表 (小端序)
uint8_t tag_list[] = {
    0xF0, 0x01,  // TAG_MODEM1_EXIST
    0xF0, 0x08,  // TAG_MODEM1_IMSI
    0xF0, 0x51,  // TAG_SYS_DEVICE_MODEL
};

// 调用查询
int len = 0;
char *result = rdp_devinfo_get_status((char*)tag_list, sizeof(tag_list), &len);

// result返回TLV格式数据:
// [0xF001][LEN][VALUE] [0xF008][LEN][VALUE] [0xF051][LEN][VALUE]
```

### 2. 全量查询

```c
// 不传TAG列表
int len = 0;
char *result = rdp_devinfo_get_status(NULL, 0, &len);

// 返回所有41个TAG的TLV数据
```

## TLV编码格式

```
[TAG (2字节)] [LEN (2字节)] [VALUE (LEN字节)]

示例: IMSI "460001234567890"
0xF0 0x08  0x00 0x10  "460001234567890\0"
```

## 待完善项 (TODO)

以下功能已预留接口，需要后续补充：

### 1. IP地址获取
```c
// 文件: RDP_devinfo.c
// 函数: modem_get_ip()
// TODO: 调用网络接口API获取modem.0或modem2.0的IP
// 参考: interface_get(ifname, ip, sizeof(ip), NULL, 0, NULL, 0);
```

### 2. 在线时长计算
```c
// 文件: RDP_devinfo.c
// 函数: modem_get_online_time()
// TODO: 计算实际在线时长 = system_time_get() - upsystime
```

### 3. GPS数据解析
```c
// 文件: RDP_devinfo.c
// 函数: gps_info()
// TODO: 
// 1. 读取GPS串口路径(从配置文件)
// 2. 打开GPS串口
// 3. 读取NMEA RMC数据
// 4. 解析经纬度
// 5. 格式化: "N:30.297318,E:104.041786"
```

### 4. 小区值完善
```c
// 文件: RDP_devinfo.c
// 函数: modem_get_cell()
// TODO: 添加CDMA网络支持 (SID+NID+BID)
```

### 5. 系统信息完善
```c
// 文件: RDP_devinfo.c
// 函数: sys_getv_def()
// TODO: 确认system.info文件中所有字段名称是否匹配
// 当前使用: "Device_Model =", "Device_ID =", 等
```

## 编译配置

### Makefile添加

```makefile
# 在RDP_engine的Makefile中添加
SRCS += RDP_devinfo.c
```

### 头文件依赖

```c
#include "RDP_devinfo.h"   // 主头文件
#include "trace.h"         // 日志输出
#include <sys/stat.h>      // stat()
```

## 测试建议

### 1. 单元测试

```bash
# 准备测试数据文件
mkdir -p /tmp
cp test_data/modem.info /tmp/
cp test_data/modem2.info /tmp/
cp test_data/system.info /etc/hdconfig/sysinfo/

# 测试按需查询 (请求3个TAG)
echo "F001 F008 F051" | xxd -r -p | ./test_rdp_devinfo

# 测试全量查询
./test_rdp_devinfo --get-all
```

### 2. 集成测试

```bash
# 通过串口发送RDP命令
# 命令: 0x07 (GET_DTU_STATUS)
# 子命令: 0x02 (GET_BY_ID)
# 数据: TAG列表

# 完整帧格式:
# [7D 7D 7D] [LEN] [07] [02] [TAG_DATA] [CHECKSUM] [7F 7F 7F]
```

### 3. 卡模式测试

```bash
# 测试单模单卡
echo "Module_Lice = 1" > /etc/hdconfig/sysinfo/system.info

# 测试单模双卡
echo "Module_Lice = 2" > /etc/hdconfig/sysinfo/system.info
echo "sim_select:1" > /tmp/modem.info

# 测试双模双卡
echo "Module_Lice = 3" > /etc/hdconfig/sysinfo/system.info
```

## 注意事项

1. **内存管理**: `info_unit_t->data`使用`calloc`分配，使用后需调用`free`释放
2. **线程安全**: 当前实现非线程安全，如需多线程访问需添加互斥锁
3. **缓冲区大小**: `g_devinfo_buf`固定4096字节，确保足够容纳所有TLV数据
4. **错误处理**: 文件读取失败时返回空数据，不会阻塞主流程
5. **卡模式**: 启动时读取一次`Module_Lice`配置，不支持动态切换

## 参考文档

- `RDP协议报文定义.txt` - TAG定义和协议格式
- `卡模式判断.txt` - Module_Lice三种模式说明
- `Z1-ODM/odm/customer/lctz/hongdian/app/dtu/` - Z1原始实现

## 版本历史

- **v1.0** (2025-11-26)
  - 初始版本
  - 实现41个TAG基础框架
  - 支持按需查询和全量查询
  - 支持三种卡模式
  - 预留TODO接口供后续完善
