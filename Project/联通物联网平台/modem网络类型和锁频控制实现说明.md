# Modem网络类型和锁频控制实现说明

## 概述

本文档详细介绍了系统中如何实现从前端到后端对modem网络类型（nettype）和锁频（frequency locking）等操作的完整流程。

---

## 一、系统架构概览

```
前端（Web页面）
    ↓ HTTP请求
CGI处理层（module_net_modem.c）
    ↓ 参数解析和处理
CLI命令生成
    ↓ store_to_cli()
配置文件写入（/tmp/hdconfig/cli.conf）
    ↓
底层驱动执行
```

---

## 二、核心数据结构

### 2.1 Modem参数结构体

系统通过以下关键参数控制modem的网络配置：

```c
struct modem_paremeter_struct {
    char *module_description;           // 模块描述
    char module_rule_name[128];         // 规则名称
    char *net_mode_description;         // 网络模式描述 "network-mode"
    char net_mode_pare[32];             // 网络类型参数（如：auto, 5G, 4G, 3G等）
    
    char *freq_band_description;        // 频段描述 "freq_band"
    char freq_band_pare[32];            // 频段参数
    
    char *freq_arfcn_description;       // 频点描述 "freq_arfcn"
    char freq_arfcn_pare[32];           // 频点参数（ARFCN值）
    
    char *freq_pcid_description;        // PCID描述 "freq_pcid"
    char freq_pcid_pare[32];            // 物理小区ID参数
    
    char *freq_scs_description;         // SCS描述 "freq_scs"
    char freq_scs_pare[32];             // 子载波间隔参数（5G专用）
    
    char *SA_network_support_description; // SA网络支持描述
    char SA_network_support[32];        // SA模式支持（on/off）
    
    char *hsr_support_description;      // HSR支持描述
    char hsr_support_pare[32];          // HSR支持参数
    
    // ... 其他参数（APN、用户名、密码等）
};
```

### 2.2 锁频相关参数说明

| 参数名称 | CLI命令 | 说明 | 适用场景 |
|---------|---------|------|---------|
| nettype | network-mode | 网络类型（auto/5G/4G/3G/2G） | 所有网络 |
| netband | freq_band | 频段锁定 | 主要用于5G |
| netfreq | freq_arfcn | 频点锁定（ARFCN） | 5G SA模式 |
| netpci | freq_pcid | 物理小区ID | 5G SA模式 |
| netscs | freq_scs | 子载波间隔 | 5G SA模式 |
| sa_support | sa-network-support | SA网络支持开关 | 5G网络 |

---

## 三、前端实现

### 3.1 前端页面结构

虽然未提供完整的HTML模板文件，但根据代码分析，前端页面包含以下主要元素：

1. **网络类型选择框** (nettype)
   - 选项：auto、5G、4G、3G、2G等
   - 对应CGI参数：`nettype`

2. **5G锁频配置区域**（仅在选择5G时显示）
   - 频段输入框 (netband)
   - SA模式开关 (sa_support)
   - PCID输入框 (netpci) - SA模式时可用
   - 频点输入框 (netfreq) - SA模式时可用
   - SCS输入框 (netscs) - SA模式时可用

3. **其他Modem配置**
   - APN、用户名、密码等

### 3.2 前端JavaScript逻辑

根据 `www/js/cn.js` 和 `www/js/en.js` 文件，前端有以下多语言定义：

```javascript
// 中文
share.nettype = "网络类型";
share.netband = "网络频段";

// 英文  
share.nettype = "Network Type";
share.netband = "Network Band";
```

### 3.3 前端表单提交

前端通过AJAX方式提交表单数据到CGI接口：

```
URL: /cgi-bin/net_modem.cgi
Method: POST
参数:
  - actionType: "Modify" 或 "Add"
  - rule_name: 规则名称（如 "sim1.1"）
  - type: "1"（modem）或 "2"（modem2）
  - nettype: 网络类型值
  - netband: 频段值
  - netpci: PCID值
  - netfreq: 频点值
  - netscs: SCS值
  - sa_support: "on" 或 "off"
  - ... 其他参数
```

---

## 四、后端CGI处理流程

### 4.1 主处理函数

文件：`src/module_net_modem.c`

主入口函数：`HEAD_FUNC(net_modem)` (第1444行)

```c
HEAD_FUNC(net_modem)
{
    COMMON_PROCESS_HEAD
    char *actionType = get_action_value();
    
    if (!strcmp(actionType, "Refresh")) {
        // 刷新数据列表
        get_modem_data(&data_list);
    }
    else if (!strcmp(actionType, "Modify")) {
        // 修改配置
        if (strstr(rule_name, "basic_param")) {
            add_basic_param_rule();  // 处理基本参数修改
        } else {
            store_modem_params(&modem_params, modem_num);  // 处理普通规则修改
        }
    }
    else if (!strcmp(actionType, "Add")) {
        // 添加新规则
        get_modem_rule_data(jsonbuf);
    }
    // ... 其他操作
}
```

### 4.2 参数获取和解析

在 `store_modem_params()` 函数中（第139行）：

```c
static int store_modem_params(struct modem_paremeter_struct *param_cmd, int modem_num)
{
    // 从CGI请求中获取锁频相关参数
    char *nettype_c = cgi_query_var("nettype");      // 网络类型
    char *netband_c = cgi_query_var("netband");      // 频段
    char *netpci_c = cgi_query_var("netpci");        // PCID
    char *netscs_c = cgi_query_var("netscs");        // SCS
    char *netfreq_c = cgi_query_var("netfreq");      // 频点
    char *sa_support_c = cgi_query_var("sa_support"); // SA支持
    
    // 定义临时存储变量
    char nettype[32] = {0};
    char netband[32] = {0};
    char netpci[32] = {0};
    char netscs[32] = {0};
    char netfreq[32] = {0};
    char sa_support[32] = {0};
    char hsr_support[32] = {0};
    
    // 复制参数值
    if(nettype_c)
        strncpy(nettype, nettype_c, sizeof(nettype));
    if(netband_c)
        strncpy(netband, netband_c, sizeof(netband));
    // ... 其他参数复制
    
    // 获取SIM卡基本配置数据（继承sim1.1或sim2.1的配置）
    get_sim_basic_data(modem_num, netscs, netfreq, netpci, nettype, netband, sa_support, hsr_support);
}
```

### 4.3 配置继承机制

`get_sim_basic_data()` 函数（第70行）实现了配置继承机制：

```c
static int get_sim_basic_data(int modem_num, char *netscs, char *netfreq, 
                               char *netpci, char *nettype, char *netband, 
                               char *sa_support, char *hsr_support)
{
    char *rule_name = cgi_query_var("rule_name");
    char *reference_name = "sim1.1";  // 默认参考sim1.1
    
    // 如果是sim2卡的规则，参考sim2.1
    if(strstr(rule_name, "sim2."))
        reference_name = "sim2.1";
    
    // 查询配置数据库
    while (G3_ERROR != cli_config_get(&modem_params, sizeof(struct modem_paremeter_struct), SAME_PARE_OFF))
    {
        if (!strcmp(modem_params.module_rule_name, reference_name))
        {
            // 仅当不是基本规则时，才继承配置
            if((strcmp(rule_name,"sim1.1")!=0) && (strcmp(rule_name,"sim2.1")!=0))
            {
                // 继承网络类型、频段、频点等参数
                if (strlen(modem_params.net_mode_pare))
                    strncpy(nettype, modem_params.net_mode_pare, 32);
                if (strlen(modem_params.freq_band_pare))
                    strncpy(netband, modem_params.freq_band_pare, 32);
                // ... 继承其他参数
            }
            break;
        }
    }
}
```

**配置继承逻辑**：
- 每个SIM卡的基本配置存储在 `sim1.1` 和 `sim2.1` 规则中
- 其他规则（如 sim1.2, sim1.3等）会自动继承对应基本规则的锁频配置
- 这样可以统一管理同一SIM卡下所有规则的网络类型和锁频参数

---

## 五、CLI命令生成逻辑

### 5.1 锁频参数处理

在 `store_modem_params()` 函数中（第284-333行）：

```c
// 1. 处理SA网络支持
char tmp[128] = {0};
if(strlen(sa_support) > 0)
    snprintf(netband_cmd, sizeof(netband_cmd), "sa-network-support %s", sa_support);

// 2. 处理HSR支持
if(strlen(hsr_support) > 0) {
    snprintf(tmp, sizeof(tmp), "\nhsr-support %s", hsr_support);
    strcat(netband_cmd, tmp);
}

// 3. 判断网络类型是否为5G
if(strstr(nettype, "5G"))
{
    // 添加频段命令
    memset(tmp, 0, sizeof(tmp));
    snprintf(tmp, sizeof(tmp), "\nfreq_band %s", netband);
    strcat(netband_cmd, tmp);
    
    // 仅在SA模式开启时，才处理PCID、频点、SCS
    if(!strcmp(sa_support, "on"))
    {
        // PCID配置
        if(strlen(netpci) > 0)
            sprintf(netpci_cmd, "freq_pcid %s", netpci);
        else
            sprintf(netpci_cmd, "no freq_pcid");
        
        // 频点配置（ARFCN）
        if(strlen(netfreq) > 0)
            sprintf(netfreq_cmd, "freq_arfcn %s", netfreq);
        else
            sprintf(netfreq_cmd, "no freq_arfcn");
        
        // SCS配置
        if(strlen(netscs) > 0)
            sprintf(netscs_cmd, "freq_scs %s", netscs);
        else
            sprintf(netscs_cmd, "no freq_scs");
    }
    else  // SA模式关闭，清除所有锁频参数
    {
        sprintf(netpci_cmd, "no freq_pcid");
        sprintf(netscs_cmd, "no freq_scs");
        sprintf(netfreq_cmd, "no freq_arfcn");
    }
}
else  // 非5G网络，清除所有5G锁频参数
{
    sprintf(netband_cmd, "no freq_band");
    sprintf(netpci_cmd, "no freq_pcid");
    sprintf(netscs_cmd, "no freq_scs");
    sprintf(netfreq_cmd, "no freq_arfcn");
}
```

**处理规则总结**：

1. **5G + SA开启**：可配置频段、PCID、频点、SCS
2. **5G + SA关闭**：仅配置频段，清除PCID/频点/SCS
3. **非5G网络**：清除所有5G锁频参数

### 5.2 CLI命令结构定义

```c
cli_cmd_t cli_parameters[] = {
    {param_cmd->module_description, "rule_name", CRLF_CONN},     // interface modem sim1.x
    {param_cmd->access_point_name_description, "apn", CRLF_CONN}, // access-point-name
    // ... 其他参数
    {param_cmd->net_mode_description, "nettype", CRLF_CONN},     // network-mode
    {netband_cmd, NULL, CRLF_CONN},          // sa-network-support + freq_band
    {netscs_cmd, NULL, CRLF_CONN},           // freq_scs
    {netpci_cmd, NULL, CRLF_CONN},           // freq_pcid
    {netfreq_cmd, NULL, CRLF_CONN},          // freq_arfcn
    // ... 其他参数
};

// 生成CLI命令字符串
char cmd_buf[1536];
cmd_len = create_cli_command(cli_parameters, 
                              (sizeof(cli_parameters) / sizeof(cli_cmd_t)), 
                              cmd_buf, sizeof(cmd_buf));

// 写入配置
return store_to_cli(cmd_buf, cmd_len);
```

### 5.3 基本参数修改流程

针对 `sim1.1` 和 `sim2.1` 基本规则的修改，使用 `add_basic_param_rule()` 函数（第1374行）：

```c
static int add_basic_param_rule()
{
    char cmd_buf[2048] = {0};
    char sim_buf[8][64] = {0};
    
    // 获取CGI参数
    char *netscs = cgi_query_var("netscs");
    char *netfreq = cgi_query_var("netfreq");
    char *netpci = cgi_query_var("netpci");
    char *nettype = cgi_query_var("nettype");
    char *netband = cgi_query_var("netband");
    char *sa_support = cgi_query_var("sa_support");
    char *hsr_support = cgi_query_var("hsr_support");
    
    // SIM2参数
    char *sim2_netscs = cgi_query_var("sim2_netscs");
    char *sim2_netfreq = cgi_query_var("sim2_netfreq");
    // ... 其他sim2参数
    
    char *current_sim = cgi_query_var("current_sim");
    
    // 根据当前SIM卡选择，配置对应的所有规则
    if(current_sim && !strcmp(current_sim, "1"))
    {
        // 获取modem下所有sim配置
        int len = check_modem_sim("modem", sim_buf);
        for(int i = 0; i < len; i++)
        {
            // 为每个sim规则生成配置命令
            save_basic_to_sim(sim_buf[i], cmd_buf, netscs, netfreq, 
                             netpci, nettype, netband, sa_support);
            // 添加HSR支持
            if (hsr_support && strlen(hsr_support)) {
                char tmp_buf[128] = {0};
                sprintf(tmp_buf, "hsr-support %s\n", hsr_support);
                strcat(cmd_buf, tmp_buf);
            }
        }
    }
    else  // SIM2配置
    {
        if (!strcmp(get_modem_lice(), "3"))  // 双卡设备
        {
            int len = check_modem_sim("modem2", sim_buf);
            for(int i = 0; i < len; i++)
            {
                save_basic_to_sim(sim_buf[i], cmd_buf, sim2_netscs, sim2_netfreq,
                                 sim2_netpci, sim2_nettype, sim2_netband, sim2_sa_support);
            }
        }
    }
    
    // 写入配置
    return add_modem_rule(cmd_buf);
}
```

### 5.4 单个SIM规则配置生成

`save_basic_to_sim()` 函数（第1259行）生成单个SIM规则的CLI命令：

```c
static void save_basic_to_sim(char *sim_name, char *cmd_buf, char *netscs, 
                               char *netfreq, char *netpci, char *nettype,
                               char *netband, char *sa_support)
{
    char tmp_buf[128] = {0};
    
    // 1. 添加interface命令（如 "interface modem sim1.1"）
    snprintf(tmp_buf, sizeof(tmp_buf), "%s\n", sim_name);
    strcat(cmd_buf, tmp_buf);
    
    // 2. SCS配置
    if (netscs && strlen(netscs))
        sprintf(tmp_buf, "freq_scs %s\n", netscs);
    else
        sprintf(tmp_buf, "no freq_scs\n");
    strcat(cmd_buf, tmp_buf);
    
    // 3. 频点配置（ARFCN）
    if (netfreq && strlen(netfreq))
        sprintf(tmp_buf, "freq_arfcn %s\n", netfreq);
    else
        sprintf(tmp_buf, "no freq_arfcn\n");
    strcat(cmd_buf, tmp_buf);
    
    // 4. PCID配置
    if (netpci && strlen(netpci))
        sprintf(tmp_buf, "freq_pcid %s\n", netpci);
    else
        sprintf(tmp_buf, "no freq_pcid\n");
    strcat(cmd_buf, tmp_buf);
    
    // 5. 网络类型配置
    if (nettype && strlen(nettype))
        sprintf(tmp_buf, "network-mode %s\n", nettype);
    strcat(cmd_buf, tmp_buf);
    
    // 6. 频段配置
    if (netband && strlen(netband))
        sprintf(tmp_buf, "freq_band %s\n", netband);
    else
        sprintf(tmp_buf, "no freq_band\n");
    strcat(cmd_buf, tmp_buf);
    
    // 7. SA网络支持
    if (sa_support && strlen(sa_support))
        sprintf(tmp_buf, "sa-network-support %s\n", sa_support);
    strcat(cmd_buf, tmp_buf);
    
    // 8. MTU配置
    char *modem_mtu = cgi_query_var("modem_mtu");
    if (modem_mtu && strlen(modem_mtu))
        sprintf(tmp_buf, "modem_mtu %s\n", modem_mtu);
    else
        sprintf(tmp_buf, "modem_mtu 1500\n");
    strcat(cmd_buf, tmp_buf);
}
```

---

## 六、配置持久化

### 6.1 CLI命令写入

所有生成的CLI命令通过 `store_to_cli()` 函数写入配置文件：

```c
static int add_modem_rule(char *cmd_buf)
{
    if (NULL == cmd_buf)
        return -1;
    
    // 添加写文件命令
    strcat(cmd_buf, "\nwrite file\n");
    
    msg(M_INFO, "==add cmd_buf(%s)", cmd_buf);
    
    // 调用底层API写入配置
    return store_to_cli(cmd_buf, strlen(cmd_buf));
}
```

### 6.2 生成的CLI命令示例

**场景1：5G SA模式锁频**

```
interface modem sim1.1
network-mode 5G
sa-network-support on
freq_band n78
freq_arfcn 632628
freq_pcid 123
freq_scs 30
modem_mtu 1500
write file
```

**场景2：4G网络（清除5G锁频参数）**

```
interface modem sim1.1
network-mode 4G
sa-network-support off
no freq_band
no freq_arfcn
no freq_pcid
no freq_scs
modem_mtu 1500
write file
```

**场景3：自动模式**

```
interface modem sim1.1
network-mode auto
sa-network-support on
no freq_band
no freq_arfcn
no freq_pcid
no freq_scs
modem_mtu 1500
write file
```

---

## 七、配置读取和显示

### 7.1 数据获取流程

`get_modem_data()` 函数（第877行）从配置文件读取数据并返回给前端：

```c
static int get_modem_data(char **data_list)
{
    struct modem_paremeter_struct basic_params;   // sim1.1基本参数
    struct modem_paremeter_struct basic2_params;  // sim2.1基本参数
    struct modem_paremeter_struct modem_params;   // 其他规则参数
    
    // 初始化
    init_modem_description(&basic_params);
    init_modem_description(&basic2_params);
    
    // 获取sim1.1基本配置
    basic_params.module_description = MODEM_BASIC_RULE;  // "interface modem sim1.1"
    if (G3_ERROR != cli_config_get(&basic_params, sizeof(...), SAME_PARE_OFF))
    {
        msg(M_INFO, "sim1.1 : %s,%s,%s,%s,%s,%s",
            basic_params.net_mode_pare,      // 网络类型
            basic_params.freq_band_pare,     // 频段
            basic_params.freq_pcid_pare,     // PCID
            basic_params.freq_arfcn_pare,    // 频点
            basic_params.freq_scs_pare,      // SCS
            basic_params.SA_network_support); // SA支持
    }
    
    // 获取sim2.1基本配置（双卡设备）
    basic2_params.module_description = MODEM2_BASIC_RULE; // "interface modem2 sim2.1"
    if (G3_ERROR != cli_config_get(&basic2_params, sizeof(...), SAME_PARE_OFF))
    {
        msg(M_INFO, "sim2.1 : %s,%s,%s,%s,%s,%s", ...);
    }
    
    // 遍历所有modem规则
    while (G3_ERROR != cli_config_get(&modem_params, sizeof(...), SAME_PARE_OFF))
    {
        if (!strcmp(modem_params.simcard_pare, "1"))  // SIM1卡规则
        {
            // 格式化输出JSON数据
            sprintf(tmp, ",[\"%s\",\"%s\",...,\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"]",
                    modem_params.module_rule_name,
                    modem_params.access_point_name_pare,
                    // ... 其他参数
                    basic_params.net_mode_pare,      // 继承sim1.1的网络类型
                    basic_params.freq_band_pare,     // 继承sim1.1的频段
                    basic_params.freq_pcid_pare,     // 继承sim1.1的PCID
                    basic_params.freq_arfcn_pare,    // 继承sim1.1的频点
                    basic_params.freq_scs_pare,      // 继承sim1.1的SCS
                    basic_params.SA_network_support); // 继承sim1.1的SA支持
            
            strcat(*data_list, tmp);
        }
    }
    
    return count;
}
```

### 7.2 单条规则数据获取

`get_modem_rule_data()` 函数（第688行）获取单条规则的详细配置：

```c
static int get_modem_rule_data(char jsonbuf[])
{
    struct modem_paremeter_struct modem_params;
    char *nettype = "auto";
    char *netband = "auto";
    char *netpci = "";
    char *netscs = "15";
    char *netfreq = "";
    
    char *rule_name = cgi_query_var("rule_name");
    
    // 查询配置
    while (G3_ERROR != cli_config_get(&modem_params, sizeof(...), SAME_PARE_OFF))
    {
        if (!strcmp(modem_params.module_rule_name, rule_name))
        {
            if (strlen(modem_params.net_mode_pare))
                nettype = modem_params.net_mode_pare;
            if (strlen(modem_params.freq_band_pare))
                netband = modem_params.freq_band_pare;
            if (strlen(modem_params.freq_arfcn_pare))
                netfreq = modem_params.freq_arfcn_pare;
            if (strlen(modem_params.freq_pcid_pare))
                netpci = modem_params.freq_pcid_pare;
            if (strlen(modem_params.freq_scs_pare))
                netscs = modem_params.freq_scs_pare;
            
            break;
        }
    }
    
    // 生成JSON返回
    sprintf(jsonbuf, "{\"status\":\"%d\",\"rule_name\":\"%s\","
                     "\"nettype\":\"%s\",\"netband\":\"%s\","
                     "\"sa_support\":\"%s\",\"netpci\":\"%s\","
                     "\"netfreq\":\"%s\",\"netscs\":\"%s\",...}",
            rule_status, modem_params.module_rule_name,
            nettype, netband,
            modem_params.SA_network_support[0] ? modem_params.SA_network_support : "off",
            netpci, netfreq, netscs, ...);
    
    return rule_status;
}
```

---

## 八、网络类型转换

在状态显示模块 `module_status_main.c` 中，提供了网络类型的友好显示转换：

```c
static void _change_modem_nettype(struct modem_data_s *data)
{
    if (strlen(data->nettype))
    {
        if (!strncmp(data->nettype, "cdma", 4))
            strcpy(data->nettype, "CDMA (2G)");
        else if(!strncmp(data->nettype, "gsm", 3))
            strcpy(data->nettype, "GSM (2G)");
        else if(!strncmp(data->nettype, "gprs", 4))
            strcpy(data->nettype, "GPRS (2G)");
        else if(!strncmp(data->nettype, "edge", 4))
            strcpy(data->nettype, "EDGE (2G)");
        else if(!strncmp(data->nettype, "evdo", 4))
            strcpy(data->nettype, "EVDO (3G)");
        else if(!strncmp(data->nettype, "wcdma", 5))
            strcpy(data->nettype, "WCDMA (3G)");
        else if(!strncmp(data->nettype, "td-scdma", 8))
            strcpy(data->nettype, "TD-SCDMA (3G)");
        else if(strstr(data->nettype, "lte"))
            strcpy(data->nettype, "LTE (4G)");
    }
}
```

---

## 九、完整操作流程示例

### 9.1 用户配置5G SA模式锁频

**前端操作**：
1. 用户在Web页面选择网络类型为 "5G"
2. 开启SA网络支持
3. 输入频段：n78
4. 输入PCID：123
5. 输入频点：632628
6. 输入SCS：30
7. 点击"保存"按钮

**前端发送请求**：
```
POST /cgi-bin/net_modem.cgi
{
  actionType: "Modify",
  rule_name: "sim1.1",
  type: "1",
  nettype: "5G",
  netband: "n78",
  sa_support: "on",
  netpci: "123",
  netfreq: "632628",
  netscs: "30"
}
```

**CGI处理流程**：
```
1. net_modem_init() 接收请求
   ↓
2. 判断 actionType == "Modify"
   ↓
3. 判断 rule_name == "basic_param" 或 包含 "sim1.1/sim2.1"
   ↓
4. 调用 add_basic_param_rule()
   ↓
5. 获取CGI参数：nettype, netband, netpci, netfreq, netscs, sa_support
   ↓
6. 查询当前所有SIM1相关的配置规则
   ↓
7. 对每个规则调用 save_basic_to_sim() 生成CLI命令
   ↓
8. 生成的CLI命令：
   interface modem sim1.1
   freq_scs 30
   freq_arfcn 632628
   freq_pcid 123
   network-mode 5G
   freq_band n78
   sa-network-support on
   modem_mtu 1500
   ↓
9. 调用 add_modem_rule() 添加 "write file" 命令
   ↓
10. 调用 store_to_cli() 写入配置文件
    ↓
11. 返回 JSON: {"result":"OK"}
```

**后续影响**：
- 该SIM1卡下所有规则（sim1.2, sim1.3...）都会继承这些锁频参数
- 底层驱动读取配置文件后应用到modem硬件
- Modem将只工作在5G SA模式，锁定在n78频段的指定小区

### 9.2 切换到自动模式

**前端操作**：
1. 选择网络类型为 "auto"
2. 点击保存

**生成的CLI命令**：
```
interface modem sim1.1
no freq_scs
no freq_arfcn
no freq_pcid
network-mode auto
no freq_band
sa-network-support on
modem_mtu 1500
write file
```

**结果**：
- 清除所有锁频参数
- Modem自动选择最优网络

---

## 十、关键技术点总结

### 10.1 配置继承机制
- 每个SIM卡有一个基本配置规则（sim1.1, sim2.1）
- 其他规则自动继承基本规则的网络类型和锁频配置
- 统一修改基本规则，所有子规则自动生效

### 10.2 5G锁频限制
- 只有网络类型包含"5G"时才能配置频段锁定
- PCID、频点、SCS只有在SA模式开启时才有效
- PCID和频点必须同时配置或同时为空

### 10.3 双卡支持
- 通过 `get_modem_lice()` 检测设备支持的卡槽数量
- Modem和Modem2分别管理两个SIM卡
- 双卡配置互不影响

### 10.4 命令格式规范
- 所有CLI命令以换行符分隔
- 使用 "no" 前缀清除参数
- 最后必须添加 "write file" 保存配置

### 10.5 错误处理
- 参数为空时自动使用默认值
- 不兼容的参数组合自动清除
- 配置写入失败时返回错误JSON

---

## 十一、文件清单

| 文件路径 | 说明 |
|---------|------|
| `src/module_net_modem.c` | Modem配置处理核心文件 |
| `include/html_lib.h` | 数据结构定义 |
| `www/js/cn.js` | 中文界面文本 |
| `www/js/en.js` | 英文界面文本 |
| `src/module_status_main.c` | 状态显示和网络类型转换 |
| `/tmp/hdconfig/cli.conf` | CLI配置文件（运行时） |

---

## 十二、附录：关键函数调用链

```
前端提交 → net_modem_init()
              ↓
         判断actionType
              ↓
    ┌─────────┴─────────┐
    │                   │
Modify               Add/Refresh
    ↓                   ↓
基本规则?          get_modem_data()
    ↓                   ↓
add_basic_param_rule()  get_modem_rule_data()
    ↓                   ↓
check_modem_sim()   cli_config_get()
    ↓                   ↓
save_basic_to_sim() 格式化JSON输出
    ↓
add_modem_rule()
    ↓
store_to_cli()
    ↓
配置文件写入
```

---

## 总结

本系统通过CGI架构实现了从前端到后端的完整modem网络控制流程：

1. **前端**：提供用户界面，收集网络类型、锁频参数等配置
2. **CGI层**：解析HTTP请求，验证参数，生成CLI命令
3. **配置层**：将CLI命令写入配置文件
4. **驱动层**：读取配置文件并应用到硬件

整个系统支持灵活的5G锁频配置，包括SA/NSA模式切换、频段选择、PCID/频点/SCS精确锁定等功能，同时通过配置继承机制简化了多规则管理。
