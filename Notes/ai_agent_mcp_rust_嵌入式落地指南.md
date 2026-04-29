# AI Agent + MCP + Rust 嵌入式落地指南

## 一、整体认知（必须先建立）

### 1. 什么是 LLM

LLM（Large Language Model）本质是一个函数：

```
输入（Prompt） → 输出（文本/决策）
```

在工程中，它是：
- 一个HTTP接口（云端）
- 或本地推理服务

作用：
- 做决策
- 做推理
- 不直接执行操作

---

### 2. 什么是 Agent

Agent = LLM + Tool + Workflow

本质：
- 会思考
- 会调用工具
- 会循环执行任务

典型流程：

```
用户输入 → LLM分析 → 调用Tool → 获取结果 → 再分析 → 输出
```

---

### 3. 什么是 Tool

Tool = 给 AI 调用的函数接口

示例：

```python
def get_signal_strength():
    return "-90 dBm"
```

作用：
- 获取数据
- 控制设备
- 执行操作

---

### 4. 什么是 MCP

MCP（Model Context Protocol）本质：

- Tool标准化
- Tool调用协议
- 上下文管理

可以理解为：

```
AI调用工具的统一接口标准
```

---

### 5. Rust 在体系中的作用

Rust适合：
- 写 Tool Server
- 写高并发服务
- 做安全控制

推荐分工：

```
C：底层驱动
Rust：服务/工具层
Python：Agent/AI逻辑
```

---

## 二、目标场景：设备掉线自动排查

### 目标流程

```
1. 检测设备状态
2. 如果掉线：
   - 查询modem状态
   - 查询信号强度
   - 查询APN
3. 判断原因
4. 自动修复（重拨号）
5. 上报结果
```

---

## 三、系统架构（推荐方案）

```
设备（C程序）
   ↓
Tool层（Rust / Shell / Python）
   ↓
Agent（Python）
   ↓
LLM（云端）
```

---

## 四、关键设计：本地自愈 + 云端分析

### 1. 本地逻辑（必须）

```c
if (ping_fail) {
    restart_dial();
}
```

作用：
- 保证设备恢复联网
- 不依赖AI

---

### 2. 云端逻辑（Agent）

```
恢复网络 → 上报状态 → Agent分析 → 给出优化策略
```

---

## 五、Tool设计（核心）

### 1. Tool列表

#### 网络类
- ping_test
- check_route

#### modem类
- get_modem_status
- get_signal_strength
- get_apn

#### 控制类
- restart_dial
- reboot_device

#### 上报类
- mqtt_publish

---

### 2. Tool实现方式

#### 方式1：Shell封装

```python
import os

def restart_dial():
    os.system("ifdown wan && ifup wan")
```

#### 方式2：调用C程序

```python
import subprocess

subprocess.run("./modem_tool --restart")
```

#### 方式3：Rust HTTP服务

```rust
#[post("/restart")]
async fn restart() {
    // 执行系统命令
}
```

---

## 六、Agent实现（核心逻辑）

### 1. 基础循环

```python
while True:
    action = llm_decide(context)
    result = run_tool(action)
    context.append(result)
```

---

### 2. 示例流程

```
LLM：设备掉线
→ 调用 get_modem_status
→ 返回：未注册网络
→ 调用 get_signal_strength
→ 返回：-110
→ 判断：信号差
→ 调用 restart_dial
```

---

## 七、MCP 接入（进阶）

### MCP做的事情

- Tool统一描述
- Tool统一调用
- 多工具协同

示例：

```json
{
  "name": "restart_dial",
  "description": "重启拨号",
  "input": {}
}
```

---

## 八、部署方案

### 推荐架构

```
设备：
- C程序（驱动）
- Tool接口（HTTP/CLI）

云端：
- Agent（Python）
- LLM
- MCP Server
```

---

## 九、开发步骤（从0到1）

### Step 1：写规则脚本

```python
if ping_fail():
    restart_dial()
```

---

### Step 2：封装Tool

- 每个能力一个函数

---

### Step 3：接入LLM

- 用LLM替代if判断

---

### Step 4：实现Agent循环

---

### Step 5：接入MQTT

- 上报状态
- 接收控制

---

### Step 6：引入MCP

---

## 十、关键工程原则

### 1. AI不能替代基础逻辑
必须有本地兜底逻辑

---

### 2. Tool要简单可靠
- 不要复杂
- 单一职责

---

### 3. Agent要可控
- 限制调用次数
- 超时控制

---

### 4. 分层设计

```
AI（决策）
↓
Tool（执行）
↓
设备（实现）
```

---

## 十一、最终总结

```
LLM = 大脑
Agent = 控制器
Tool = 手脚
设备 = 执行体
```

核心思想：

AI不直接操作设备，而是通过Tool间接控制系统。

---

## 十二、你下一步可以做什么

1. 实现3个基础Tool
   - get_signal
   - get_modem_status
   - restart_dial

2. 写一个简单Agent循环

3. 接入MQTT上报

4. 再逐步接入LLM

---

（完）

