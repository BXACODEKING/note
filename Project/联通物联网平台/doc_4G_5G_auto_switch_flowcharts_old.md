# 4G/5G自动切换功能 - 详细流程图

> 基于 `doc_4G_5G_auto_switch_design.md` 设计文档生成
> 
> 文档版本：2.0 | 生成日期：2025-12-31

---

## 流程图索引

- [4G/5G自动切换功能 - 详细流程图](#4g5g自动切换功能---详细流程图)
  - [流程图索引](#流程图索引)
  - [1. 监控系统初始化与生命周期](#1-监控系统初始化与生命周期)
  - [2. 主监控循环流程](#2-主监控循环流程)
  - [3. 质量判断与决策逻辑](#3-质量判断与决策逻辑)
  - [4. 场景1：5G→4G切换流程](#4-场景15g4g切换流程)
  - [5. 场景2：4G→5G切换流程（质量差）](#5-场景24g5g切换流程质量差)
  - [6. 场景3：4G→5G回归流程（定期尝试）](#6-场景34g5g回归流程定期尝试)
  - [7. 完整状态机总览](#7-完整状态机总览)
  - [8. 异常处理流程](#8-异常处理流程)
  - [9. 配置与启动条件流程](#9-配置与启动条件流程)
  - [10. 质量检测详细流程](#10-质量检测详细流程)
  - [11. 防抖与冷却机制详细流程](#11-防抖与冷却机制详细流程)
  - [12. 时间轴示例场景](#12-时间轴示例场景)
    - [场景A：5G质量持续差，切换到4G并保持](#场景a5g质量持续差切换到4g并保持)
    - [场景B：4G质量差，立即回切5G](#场景b4g质量差立即回切5g)
    - [场景C：4G正常，定期尝试回归5G](#场景c4g正常定期尝试回归5g)
  - [13. 参数配置对比表](#13-参数配置对比表)
  - [附录：关键数据结构](#附录关键数据结构)
  - [流程图使用说明](#流程图使用说明)

---

## 1. 监控系统初始化与生命周期

```mermaid
graph TD
    Start([进程启动/配置变更/掉线重拨]) --> Init[modem_status_init调用]
    Init --> Cleanup1{是否存在旧nqm_ctx?}
    Cleanup1 -->|是| CleanupOld[清理旧监控上下文]
    Cleanup1 -->|否| CheckStatus
    CleanupOld --> CheckStatus{检查modem状态}
    
    CheckStatus -->|LINK_WORK| CheckConfig{检查配置}
    CheckStatus -->|其他状态| WaitLink[等待网络连接]
    WaitLink --> CheckStatus
    
    CheckConfig -->|force_type=5G系列<br/>latency_threshold>0| AllocCtx[分配nqm_context_t内存]
    CheckConfig -->|条件不满足| NoMonitor[不启动监控]
    
    AllocCtx --> InitMutex[初始化互斥锁]
    InitMutex --> InitBuffer[初始化环形缓冲区<br/>buffer_size=12]
    InitBuffer --> SetParams[设置参数:<br/>threshold/duration/target<br/>keep_time/debounce_time]
    SetParams --> CreateThread[创建监控线程<br/>DETACHED/8KB栈]
    CreateThread --> ThreadStart[monitor_thread启动]
    ThreadStart --> Running[监控运行中]
    
    Running --> Event1{触发事件}
    Event1 -->|配置变更MD5| Reinit[重新初始化]
    Event1 -->|进程退出| Exit[进程退出清理]
    Event1 -->|VIF重拨| KeepRunning[保持运行不清理]
    Event1 -->|网络切换| KeepRunning
    
    Reinit --> Init
    Exit --> StopThread[停止监控线程]
    StopThread --> DestroyMutex[销毁互斥锁]
    DestroyMutex --> FreeMemory[释放内存]
    FreeMemory --> End([结束])
    
    KeepRunning --> Running
    NoMonitor --> End
    
    style Start fill:#e1f5ff
    style End fill:#ffe1e1
    style Running fill:#e1ffe1
    style Cleanup1 fill:#fff4e1
    style CheckStatus fill:#fff4e1
    style CheckConfig fill:#fff4e1
    style Event1 fill:#fff4e1
```

**关键点说明**：
- ✅ **创建时机**：首次进入LINK_WORK + 5G模式 + threshold>0
- ✅ **清理时机**：进程启动/配置变更/掉线重拨/进程退出
- ❌ **禁止清理**：VIF重拨、网络切换（保持连续性）

---

## 2. 主监控循环流程

```mermaid
graph TD
    ThreadStart([监控线程启动]) --> InitMode[记录初始网络模式<br/>mode_start_time=当前时间]
    InitMode --> LogStart[输出启动日志]
    LogStart --> MainLoop{thread_running?}
    
    MainLoop -->|false| ThreadExit([线程退出])
    MainLoop -->|true| CheckVIF{检查VIF/Modem状态}
    
    CheckVIF -->|异常| Sleep5s[sleep 5秒]
    CheckVIF -->|正常| GetCurrentMode[获取当前网络模式]
    
    GetCurrentMode --> CheckModeChange{模式是否变化?}
    CheckModeChange -->|是| ResetModeTime[重置mode_start_time]
    CheckModeChange -->|否| KeepTime[保持mode_start_time]
    
    ResetModeTime --> DoPing[执行ping测试]
    KeepTime --> DoPing
    
    DoPing --> RecordLatency[记录延迟到环形缓冲区<br/>覆盖最旧数据]
    RecordLatency --> LogLatency[输出延迟日志]
    LogLatency --> CheckQuality{分析质量<br/>计算keep_time}
    
    CheckQuality --> Decision[执行决策逻辑]
    Decision --> StatsLog{5分钟统计周期?}
    
    StatsLog -->|是| OutputStats[输出统计信息]
    StatsLog -->|否| Sleep5s
    OutputStats --> Sleep5s
    
    Sleep5s --> MainLoop
    
    style ThreadStart fill:#e1f5ff
    style ThreadExit fill:#ffe1e1
    style MainLoop fill:#fff4e1
    style CheckVIF fill:#fff4e1
    style CheckModeChange fill:#fff4e1
    style CheckQuality fill:#fff4e1
    style StatsLog fill:#fff4e1
    style DoPing fill:#ffffcc
    style Decision fill:#ffccff
```

**关键参数**：
- 📊 **采样间隔**：5秒（固定）
- 📊 **缓冲区大小**：12个点（覆盖60秒）
- 📊 **统计周期**：5分钟输出一次统计

---

## 3. 质量判断与决策逻辑

```mermaid
graph TD
    Start([决策入口]) --> CheckDebounce{是否在防抖期?<br/>current_time - last_switch_time < debounce}
    
    CheckDebounce -->|是| CalcDebounce[计算防抖剩余时间]
    CalcDebounce --> CheckFailure{连续失败次数>=3?}
    CheckFailure -->|是| CalcCooldown[动态冷却时间<br/>= 60s × failure_count]
    CheckFailure -->|否| UseDebouce[使用基础防抖60s]
    CalcCooldown --> SkipDecision[跳过决策]
    UseDebouce --> SkipDecision
    
    CheckDebounce -->|否| AnalyzeQuality[分析质量数据]
    AnalyzeQuality --> CheckDuration{duration时长内<br/>所有采样点都超阈值?}
    
    CheckDuration -->|否| QualityGood[质量正常]
    CheckDuration -->|是| QualityPoor[质量差]
    
    QualityGood --> CheckMode1{当前模式?}
    CheckMode1 -->|5G| Continue5G[继续监控]
    CheckMode1 -->|4G| CheckKeepTime1{达到keep_time?}
    
    CheckKeepTime1 -->|否| Continue4G[继续监控]
    CheckKeepTime1 -->|是| Scenario3[场景3:<br/>4G正常回切5G]
    
    QualityPoor --> CheckMode2{当前模式?}
    CheckMode2 -->|5G| CheckKeepTime2{达到keep_time?}
    CheckMode2 -->|4G| Scenario2[场景2:<br/>4G差立即切5G]
    
    CheckKeepTime2 -->|否| WaitKeep[等待保持时间<br/>避免频繁切换]
    CheckKeepTime2 -->|是| Scenario1[场景1:<br/>5G差切4G并检测]
    
    SkipDecision --> Return([返回主循环])
    Continue5G --> Return
    Continue4G --> Return
    WaitKeep --> Return
    Scenario1 --> Execute1[执行切换流程]
    Scenario2 --> Execute2[执行切换流程]
    Scenario3 --> Execute3[执行切换流程]
    Execute1 --> Return
    Execute2 --> Return
    Execute3 --> Return
    
    style Start fill:#e1f5ff
    style Return fill:#e1ffe1
    style CheckDebounce fill:#fff4e1
    style CheckFailure fill:#fff4e1
    style CheckDuration fill:#fff4e1
    style CheckMode1 fill:#fff4e1
    style CheckMode2 fill:#fff4e1
    style CheckKeepTime1 fill:#fff4e1
    style CheckKeepTime2 fill:#fff4e1
    style Scenario1 fill:#ffcccc
    style Scenario2 fill:#ccffcc
    style Scenario3 fill:#ccccff
```

**决策核心**：
- 🔹 **防抖机制**：60秒基础 + 失败次数动态延长
- 🔹 **质量判断**：duration时长内所有点都超阈值
- 🔹 **保持时间**：5G需等待，4G差立即切

---

## 4. 场景1：5G→4G切换流程

```mermaid
graph TD
    Start([5G质量差检测]) --> CheckKeep{达到keep_time?<br/>默认600秒}
    CheckKeep -->|否| Wait[继续等待]
    CheckKeep -->|是| LogSwitch[输出切换日志]
    
    LogSwitch --> SetSkipFreq[设置skip_freq_lock=1<br/>跳过锁频加快切换]
    SetSkipFreq --> SetNetMode[设置网络模式为4G<br/>MDM_CTRL_NET_CUSTOM]
    SetNetMode --> TriggerVIF[触发VIF RULE_UPDATE<br/>启动重拨]
    TriggerVIF --> ResetSkipFreq[恢复skip_freq_lock=0]
    
    ResetSkipFreq --> WaitAttach[等待4G附网<br/>max 120秒]
    WaitAttach --> CheckLoop{循环检查VIF状态}
    
    CheckLoop --> CheckTimeout{超时120秒?}
    CheckTimeout -->|是| AttachFailed[附网失败]
    CheckTimeout -->|否| CheckVIFStatus{VIF状态?}
    
    CheckVIFStatus -->|LINK_WORK| AttachSuccess[附网成功]
    CheckVIFStatus -->|其他| Sleep1s[sleep 1秒]
    Sleep1s --> CheckLoop
    
    AttachFailed --> LogError1[记录超时错误]
    LogError1 --> IncrementFailure1[增加失败计数]
    IncrementFailure1 --> SwitchBack5G1[切回5G模式]
    SwitchBack5G1 --> UpdateTime1[更新last_switch_time<br/>更新mode_start_time]
    UpdateTime1 --> End1([切换失败结束])
    
    AttachSuccess --> LogAttach[输出附网成功日志<br/>记录耗时]
    LogAttach --> StableWait[稳定等待10秒]
    StableWait --> StartDetection[开始4G质量检测<br/>duration=60秒]
    
    StartDetection --> DetectLoop{检测循环}
    DetectLoop --> CheckNetStatus{网络状态?}
    CheckNetStatus -->|断开| NetBroken[网络断开]
    CheckNetStatus -->|正常| DoPing[执行ping测试]
    
    DoPing --> RecordPing[记录延迟]
    RecordPing --> CheckDetectTime{检测满60秒?}
    CheckDetectTime -->|否| Sleep5s[sleep 5秒]
    Sleep5s --> DetectLoop
    CheckDetectTime -->|是| AnalyzeResult[分析检测结果]
    
    NetBroken --> LogError2[记录断网错误]
    LogError2 --> IncrementFailure2[增加失败计数]
    IncrementFailure2 --> SwitchBack5G2[切回5G模式]
    SwitchBack5G2 --> UpdateTime2[更新时间戳]
    UpdateTime2 --> End2([切换失败结束])
    
    AnalyzeResult --> CheckResult{4G质量?}
    CheckResult -->|质量差| Log4GPoor[输出4G质量差日志]
    CheckResult -->|质量好| Log4GGood[输出4G质量好日志]
    
    Log4GPoor --> IncrementFailure3[增加失败计数]
    IncrementFailure3 --> SwitchBack5G3[切回5G模式]
    SwitchBack5G3 --> UpdateTime3[更新时间戳]
    UpdateTime3 --> End3([切换失败结束])
    
    Log4GGood --> ResetFailure[重置失败计数=0]
    ResetFailure --> UpdateSuccess[更新last_switch_time<br/>更新mode_start_time<br/>switch_count++]
    UpdateSuccess --> End4([切换成功，保持4G])
    
    Wait --> EndWait([继续监控])
    
    style Start fill:#e1f5ff
    style End1 fill:#ffcccc
    style End2 fill:#ffcccc
    style End3 fill:#ffcccc
    style End4 fill:#ccffcc
    style EndWait fill:#e1ffe1
    style CheckKeep fill:#fff4e1
    style CheckTimeout fill:#fff4e1
    style CheckVIFStatus fill:#fff4e1
    style CheckNetStatus fill:#fff4e1
    style CheckDetectTime fill:#fff4e1
    style CheckResult fill:#fff4e1
    style StartDetection fill:#ffffcc
```

**流程特点**：
- ⏱️ **保持时间**：600秒（避免频繁切换）
- 🔍 **4G检测**：60秒质量检测（必须通过）
- ⏳ **附网超时**：120秒上限
- 🔄 **失败处理**：切回5G，增加失败计数

---

## 5. 场景2：4G→5G切换流程（质量差）

```mermaid
graph TD
    Start([4G质量差检测]) --> Log[输出切换日志<br/>4G质量差，立即切5G]
    
    Log --> SetSkipFreq[设置skip_freq_lock=1]
    SetSkipFreq --> SetNetMode[设置网络模式为5G]
    SetNetMode --> TriggerVIF[触发VIF RULE_UPDATE]
    TriggerVIF --> ResetSkipFreq[恢复skip_freq_lock=0]
    
    ResetSkipFreq --> ResetFailure[重置失败计数=0]
    ResetFailure --> UpdateTime[更新last_switch_time<br/>更新mode_start_time<br/>switch_count++]
    UpdateTime --> NoDetection[不执行质量检测<br/>直接切换]
    
    NoDetection --> LogSuccess[输出切换成功日志]
    LogSuccess --> End([返回主循环监控5G])
    
    style Start fill:#e1f5ff
    style End fill:#ccffcc
    style NoDetection fill:#ffffcc
```

**流程特点**：
- ⚡ **立即切换**：无需等待keep_time
- 🚫 **无质量检测**：避免检测期间抖动误判
- 🎯 **优先回归**：5G是主用网络
- 🔁 **后续监控**：由主循环监控5G质量

**设计理念**：
- 4G是临时备用网络，质量差应快速回到主用5G
- 若5G仍质量差，会通过场景1再次切回4G
- 形成"5G优先，动态调整"的策略

---

## 6. 场景3：4G→5G回归流程（定期尝试）

```mermaid
graph TD
    Start([4G质量正常]) --> CheckKeep{达到keep_time?<br/>默认600秒}
    CheckKeep -->|否| Wait[继续监控]
    CheckKeep -->|是| Log[输出回切日志<br/>4G质量好但尝试回归5G]
    
    Log --> SetSkipFreq[设置skip_freq_lock=1]
    SetSkipFreq --> SetNetMode[设置网络模式为5G]
    SetNetMode --> TriggerVIF[触发VIF RULE_UPDATE]
    TriggerVIF --> ResetSkipFreq[恢复skip_freq_lock=0]
    
    ResetSkipFreq --> ResetFailure[重置失败计数=0]
    ResetFailure --> UpdateTime[更新last_switch_time<br/>更新mode_start_time<br/>switch_count++]
    UpdateTime --> NoDetection[不执行质量检测<br/>直接切换]
    
    NoDetection --> LogSuccess[输出切换成功日志]
    LogSuccess --> End([返回主循环监控5G])
    
    Wait --> EndWait([继续监控])
    
    style Start fill:#e1f5ff
    style End fill:#ccccff
    style EndWait fill:#e1ffe1
    style CheckKeep fill:#fff4e1
    style NoDetection fill:#ffffcc
```

**流程特点**：
- ⏱️ **定期尝试**：600秒周期性回归
- 🎯 **5G优先策略**：即使4G好也要尝试5G
- 🚫 **无质量检测**：直接切换
- 🔁 **后续监控**：由主循环监控5G质量

**设计理念**：
- 避免长期停留在备用网络（4G）
- 定期尝试主用网络（5G）是否恢复
- 平衡网络质量和优先级策略

---

## 7. 完整状态机总览
![[Pasted image 20251231111045.png]]
```mermaid
stateDiagram-v2
    [*] --> 系统初始化
    
    系统初始化 --> 监控未启动: 条件不满足<br/>(非5G/threshold=0)
    系统初始化 --> 5G监控中: 条件满足<br/>(5G模式+threshold>0)
    
    监控未启动 --> [*]
    
    5G监控中 --> 5G监控中: 质量正常<br/>继续监控
    5G监控中 --> 5G等待切换: 质量差<br/>但未达keep_time
    5G等待切换 --> 5G监控中: 质量恢复
    5G等待切换 --> 切换到4G: 质量差持续<br/>达到keep_time(600s)
    
    切换到4G --> 4G附网中: 设置4G模式<br/>触发VIF重拨
    4G附网中 --> 4G质量检测: 附网成功<br/>(120s内)
    4G附网中 --> 5G监控中: 附网超时<br/>切回5G
    
    4G质量检测 --> 4G监控中: 检测通过<br/>4G质量好(60s)
    4G质量检测 --> 5G监控中: 检测失败<br/>4G质量差/断网
    
    4G监控中 --> 4G监控中: 质量正常<br/>未达keep_time
    4G监控中 --> 切换到5G_质量差: 质量变差<br/>立即切换
    4G监控中 --> 切换到5G_定期: 质量正常<br/>达到keep_time(600s)
    
    切换到5G_质量差 --> 5G监控中: 直接切换<br/>无质量检测
    切换到5G_定期 --> 5G监控中: 直接切换<br/>无质量检测
    
    5G监控中 --> 配置变更: UCI配置MD5变化
    4G监控中 --> 配置变更: UCI配置MD5变化
    配置变更 --> 系统初始化: 清理并重新初始化
    
    5G监控中 --> [*]: 进程退出
    4G监控中 --> [*]: 进程退出
    
    note right of 5G监控中
        每5秒采样
        环形缓冲12个点
        质量判断基于duration
    end note
    
    note right of 4G监控中
        质量差立即切5G
        质量好定期尝试5G
        两种回归策略
    end note
    
    note right of 切换到4G
        带质量检测
        防止无效切换
        附网超时保护
    end note
```


**状态说明**：
- 🟢 **5G监控中**：主状态，优先网络
- 🟡 **5G等待切换**：质量差但未达切换条件
- 🔄 **切换到4G**：执行切换并检测
- 🟠 **4G监控中**：备用状态
- 🔙 **切换到5G**：回归主网络（两种触发）

---

## 8. 异常处理流程

```mermaid
graph TD
    Start([异常发生]) --> Type{异常类型?}
    
    Type -->|4G附网超时| Timeout[等待120秒未附网]
    Type -->|质量检测断网| Disconnect[检测期间网络断开]
    Type -->|切换失败| SwitchFail[切换操作失败]
    Type -->|ping失败| PingFail[ping测试超时/失败]
    
    Timeout --> LogTimeout[记录超时错误日志]
    LogTimeout --> IncrementFail1[switch_failure_count++]
    IncrementFail1 --> Rollback1[切回5G模式]
    Rollback1 --> UpdateTime1[更新时间戳]
    UpdateTime1 --> CheckCount1{失败次数>=3?}
    
    Disconnect --> LogDisconnect[记录断网错误日志]
    LogDisconnect --> IncrementFail2[switch_failure_count++]
    IncrementFail2 --> Rollback2[切回5G模式]
    Rollback2 --> UpdateTime2[更新时间戳]
    UpdateTime2 --> CheckCount2{失败次数>=3?}
    
    SwitchFail --> LogFail[记录切换失败日志]
    LogFail --> IncrementFail3[switch_failure_count++]
    IncrementFail3 --> CheckCount3{失败次数>=3?}
    
    PingFail --> RecordMax[记录最大延迟10000ms]
    RecordMax --> ContinuePing{连续ping失败?}
    ContinuePing -->|是| TriggerPoor[触发质量差判断]
    ContinuePing -->|否| ContinueMonitor[继续监控]
    
    CheckCount1 -->|是| LogWarning1[输出告警日志]
    CheckCount1 -->|否| SetCooldown1[设置冷却期]
    CheckCount2 -->|是| LogWarning2[输出告警日志]
    CheckCount2 -->|否| SetCooldown2[设置冷却期]
    CheckCount3 -->|是| LogWarning3[输出告警日志]
    CheckCount3 -->|否| SetCooldown3[设置冷却期]
    
    LogWarning1 --> DynamicCooldown1[动态冷却<br/>60s × failure_count]
    LogWarning2 --> DynamicCooldown2[动态冷却<br/>60s × failure_count]
    LogWarning3 --> DynamicCooldown3[动态冷却<br/>60s × failure_count]
    
    SetCooldown1 --> Return1([返回主循环])
    SetCooldown2 --> Return2([返回主循环])
    SetCooldown3 --> Return3([返回主循环])
    DynamicCooldown1 --> Return1
    DynamicCooldown2 --> Return2
    DynamicCooldown3 --> Return3
    
    TriggerPoor --> DecisionLogic[进入决策逻辑]
    ContinueMonitor --> Return4([返回主循环])
    DecisionLogic --> Return4
    
    style Start fill:#e1f5ff
    style Return1 fill:#ffe1e1
    style Return2 fill:#ffe1e1
    style Return3 fill:#ffe1e1
    style Return4 fill:#e1ffe1
    style Type fill:#fff4e1
    style CheckCount1 fill:#fff4e1
    style CheckCount2 fill:#fff4e1
    style CheckCount3 fill:#fff4e1
    style ContinuePing fill:#fff4e1
```

**异常处理机制**：
- ⚠️ **附网超时**：120秒保护，防止长时间等待
- ⚠️ **断网保护**：检测期间断网立即中止
- ⚠️ **失败计数**：记录连续失败，触发动态冷却
- ⚠️ **动态冷却**：60秒 × 失败次数（最小60s）
- ⚠️ **ping失败**：记录最大值，触发质量差判断

---

## 9. 配置与启动条件流程

```mermaid
graph TD
    Start([配置检查]) --> CheckForceType{force_type?}
    
    CheckForceType -->|E_5G=4| Check5G
    CheckForceType -->|E_5G_NSA=5| Check5G
    CheckForceType -->|E_5G_SA=6| Check5G
    CheckForceType -->|其他| Disable1[监控未启用<br/>非5G模式]
    
    Check5G --> CheckThreshold{latency_threshold?}
    CheckThreshold -->|0| Disable2[监控未启用<br/>功能禁用]
    CheckThreshold -->|<100| Adjust1[自动调整为100]
    CheckThreshold -->|>10000| Adjust2[自动调整为10000]
    CheckThreshold -->|100-10000| ValidThreshold[阈值有效]
    
    Adjust1 --> CheckDuration
    Adjust2 --> CheckDuration
    ValidThreshold --> CheckDuration{latency_duration?}
    
    CheckDuration -->|<30| Adjust3[自动调整为30]
    CheckDuration -->|>300| Adjust4[自动调整为300]
    CheckDuration -->|30-300| ValidDuration[持续时间有效]
    
    Adjust3 --> CheckKeepTime
    Adjust4 --> CheckKeepTime
    ValidDuration --> CheckKeepTime{nettype_keep_time?}
    
    CheckKeepTime -->|<60| Adjust5[自动调整为60]
    CheckKeepTime -->|>3600| Adjust6[自动调整为3600]
    CheckKeepTime -->|60-3600| ValidKeepTime[保持时间有效]
    
    Adjust5 --> CheckStatus
    Adjust6 --> CheckStatus
    ValidKeepTime --> CheckStatus{Modem状态?}
    
    CheckStatus -->|LINK_WORK| Enable[启用监控]
    CheckStatus -->|其他| Wait[等待连接]
    Wait --> CheckStatus
    
    Enable --> CreateContext[创建监控上下文]
    CreateContext --> StartThread[启动监控线程]
    StartThread --> Running([监控运行中])
    
    Disable1 --> End([监控未启动])
    Disable2 --> End
    
    style Start fill:#e1f5ff
    style Running fill:#ccffcc
    style End fill:#ffe1e1
    style CheckForceType fill:#fff4e1
    style CheckThreshold fill:#fff4e1
    style CheckDuration fill:#fff4e1
    style CheckKeepTime fill:#fff4e1
    style CheckStatus fill:#fff4e1
```

**配置要求**：
- ✅ **force_type**：必须是5G系列（4/5/6）
- ✅ **latency_threshold**：100-10000ms（0=禁用）
- ✅ **latency_duration**：30-300秒
- ✅ **nettype_keep_time**：60-3600秒
- ✅ **状态**：必须LINK_WORK（已连接）

---

## 10. 质量检测详细流程

```mermaid
graph TD
    Start([质量分析入口]) --> GetBuffer[获取环形缓冲区数据]
    GetBuffer --> CheckSamples{有效采样数?}
    
    CheckSamples -->|<12个点| NotEnough[样本不足<br/>继续采样]
    CheckSamples -->|=12个点| Calculate[计算duration时长内采样数<br/>duration/5秒]
    
    Calculate --> GetRecent[获取最近N个采样点<br/>N=duration/5]
    GetRecent --> CheckAll{所有点都超阈值?}
    
    CheckAll -->|是| QualityPoor[质量差]
    CheckAll -->|否| QualityGood[质量正常]
    
    QualityPoor --> LogPoor[输出质量差日志<br/>显示超标点数]
    QualityGood --> LogGood[输出质量正常日志]
    
    LogPoor --> ReturnPoor([返回：quality_poor])
    LogGood --> ReturnGood([返回：quality_good])
    NotEnough --> ReturnWait([返回：wait])
    
    style Start fill:#e1f5ff
    style ReturnPoor fill:#ffcccc
    style ReturnGood fill:#ccffcc
    style ReturnWait fill:#ffffcc
    style CheckSamples fill:#fff4e1
    style CheckAll fill:#fff4e1
```

**判定算法**：
```
1. 环形缓冲区容量：12个点（覆盖60秒）
2. 检测窗口：duration秒（默认60秒 = 12个点）
3. 判定条件：窗口内所有采样点都超阈值
4. 采样频率：5秒/次（固定）

示例（duration=60秒）：
- 需要12个连续采样点都超阈值
- 任何一个点低于阈值，判定为质量正常
- 确保质量确实持续变差，避免误判
```

---

## 11. 防抖与冷却机制详细流程

```mermaid
graph TD
    Start([切换后处理]) --> UpdateTime[更新last_switch_time]
    UpdateTime --> NextCycle[进入下一个监控周期]
    
    NextCycle --> Decision[决策逻辑入口]
    Decision --> CalcElapsed[计算时间差<br/>elapsed = current - last_switch]
    CalcElapsed --> CheckDebounce{elapsed < debounce_time?}
    
    CheckDebounce -->|否| AllowDecision[允许决策]
    CheckDebounce -->|是| CheckFailCount{failure_count?}
    
    CheckFailCount -->|0-2次| BasicDebounce[基础防抖60秒]
    CheckFailCount -->|>=3次| DynamicCooldown[动态冷却<br/>60s × failure_count]
    
    BasicDebounce --> CalcRemain1[计算剩余时间<br/>remain = 60 - elapsed]
    DynamicCooldown --> CalcRemain2[计算剩余时间<br/>remain = cooldown - elapsed]
    
    CalcRemain1 --> LogSkip1[输出防抖跳过日志<br/>显示剩余时间]
    CalcRemain2 --> LogSkip2[输出冷却跳过日志<br/>显示失败次数]
    
    LogSkip1 --> Skip([跳过决策])
    LogSkip2 --> Skip
    
    AllowDecision --> DoDecision[执行质量判断]
    DoDecision --> SwitchResult{切换结果?}
    
    SwitchResult -->|成功| ResetCount[failure_count = 0]
    SwitchResult -->|失败| IncrementCount[failure_count++]
    
    ResetCount --> UpdateSwitch1[更新last_switch_time]
    IncrementCount --> UpdateSwitch2[更新last_switch_time]
    
    UpdateSwitch1 --> NextLoop1([进入下一轮])
    UpdateSwitch2 --> NextLoop2([进入下一轮])
    Skip --> NextLoop3([继续监控])
    
    style Start fill:#e1f5ff
    style NextLoop1 fill:#ccffcc
    style NextLoop2 fill:#ffcccc
    style NextLoop3 fill:#ffffcc
    style CheckDebounce fill:#fff4e1
    style CheckFailCount fill:#fff4e1
    style SwitchResult fill:#fff4e1
```

**防抖策略**：
- 🕒 **基础防抖**：60秒（固定）
- 🕒 **动态冷却**：60秒 × 失败次数
- 🕒 **示例冷却时间**：
  - 失败1次：60秒
  - 失败2次：120秒
  - 失败3次：180秒
  - 失败4次：240秒
  - ...以此类推

---

## 12. 时间轴示例场景

### 场景A：5G质量持续差，切换到4G并保持

```mermaid
gantt
    title 场景A：5G→4G切换时间轴
    dateFormat  ss
    axisFormat %S秒
    
    section 5G阶段
    5G正常运行           :done, 00, 60s
    5G质量开始变差       :active, 60, 120s
    质量差持续(未达keep_time) :crit, 60, 600s
    达到keep_time，触发切换 :milestone, 660, 0s
    
    section 切换阶段
    设置4G模式           :active, 660, 5s
    等待4G附网           :active, 665, 15s
    稳定等待10秒         :active, 680, 10s
    4G质量检测60秒       :active, 690, 60s
    
    section 4G阶段
    4G质量合格，保持4G   :done, 750, 300s
```

### 场景B：4G质量差，立即回切5G

```mermaid
gantt
    title 场景B：4G→5G立即回切时间轴
    dateFormat  ss
    axisFormat %S秒
    
    section 4G阶段
    4G正常运行           :done, 00, 60s
    4G质量开始变差       :active, 60, 120s
    质量差持续60秒       :crit, 60, 60s
    达到duration，触发切换 :milestone, 120, 0s
    
    section 切换阶段
    立即设置5G模式       :active, 120, 5s
    无需质量检测         :active, 125, 0s
    
    section 5G阶段
    切换完成，5G运行     :done, 125, 300s
```

### 场景C：4G正常，定期尝试回归5G

```mermaid
gantt
    title 场景C：4G正常定期回切5G时间轴
    dateFormat  ss
    axisFormat %S秒
    
    section 4G阶段
    4G质量正常运行       :done, 00, 600s
    达到keep_time        :milestone, 600, 0s
    
    section 切换阶段
    设置5G模式           :active, 600, 5s
    无需质量检测         :active, 605, 0s
    
    section 5G阶段
    切换完成，5G运行     :done, 605, 300s
```

---

## 13. 参数配置对比表

| 参数 | 快速响应模式 | 默认均衡模式 | 稳定优先模式 |
|------|-------------|-------------|-------------|
| **latency_threshold** | 1000ms | 1000ms | 2000ms |
| **latency_duration** | 30s | 60s | 120s |
| **nettype_keep_time** | 300s (5分钟) | 600s (10分钟) | 1800s (30分钟) |
| **切换灵敏度** | 高（快速切换） | 中等（平衡） | 低（减少切换） |
| **适用场景** | 延迟敏感应用 | 通用场景 | 稳定网络环境 |

---

## 附录：关键数据结构

```c
// 监控上下文结构
typedef struct {
    // 配置参数
    uint32_t latency_threshold;       // 延迟阈值(ms)
    uint32_t latency_duration;        // 持续时间(s)
    char latency_target[64];          // ping目标
    uint32_t nettype_keep_time;       // 保持时间(s)
    uint32_t debounce_time;           // 防抖时间(s，固定60)
    
    // 运行时状态
    struct {
        pthread_t monitor_thread;     // 监控线程ID
        pthread_mutex_t mutex;        // 互斥锁
        int thread_running;           // 线程运行标志
        
        uint32_t latency_buffer[12];  // 环形缓冲区
        uint32_t buffer_index;        // 当前索引
        
        time_t last_switch_time;      // 上次切换时间
        time_t mode_start_time;       // 模式开始时间
        uint32_t switch_count;        // 切换次数
        uint32_t switch_failure_count;// 失败次数
        
        netmode_t current_mode;       // 当前网络模式
    } runtime;
    
    modem_t *modem;                   // 关联的modem对象
} nqm_context_t;
```

---

## 流程图使用说明

1. **在线渲染**：复制Mermaid代码块到以下工具渲染
   - [Mermaid Live Editor](https://mermaid.live/)
   - GitHub/GitLab（原生支持）
   - VS Code + Mermaid插件

2. **导出图片**：使用Mermaid CLI或在线工具导出为PNG/SVG

3. **修改建议**：根据实际代码实现，微调流程细节

---

**文档说明**：
- ✅ 基于设计文档v2.0生成
- ✅ 包含所有关键流程和异常处理
- ✅ 使用Mermaid标准语法
- ✅ 可直接在支持工具中渲染
- ✅ 建议结合设计文档阅读

**生成日期**：2025-12-31  
**作者**：AI Assistant

