## 🔹 一、前端页面修改（www/html/basic_netcheck_list_module.ht）

### ✳️ 新增功能
- 增加 **包大小下拉框**，提供预设选项：`64 / 128 / 256 / 512 / 1024` 字节与 **自定义选项**。  
- 增加 **输入框**，用于显示或手动输入包大小（默认值：`64` 字节）。  

### 🧩 新增函数
- **`update_ping_size()`**：处理下拉框变化，自动填充或清空输入框。  

### 🔧 修改函数
- **`to_ping()`**：  
  - 增加包大小参数验证（范围：`0–65507` 字节）。  
  - 将包大小参数传递至后端模块。  

---

## 🔹 二、后端逻辑优化（src/module_basic_netcheck.c）

### 🧠 修改函数
- **`get_ping_result()`**：  
  - 接收前端传递的 `packet_size` 参数。  
  - 默认包大小为 **64字节**。  
  - 对输入值进行 **合法性验证**，超出范围时回退默认值。  
  - `ping` 命令中新增 `-s` 参数以指定包大小。  

---

## 🔹 三、多语言支持扩展

### 🌏 英文（www/js/en.js）
```js
share.packet_size = "Packet Size";
```

### 🇨🇳 中文（www/js/cn.js）
```js
share.packet_size = "包大小";
```

---

## 🔹 四、确认提示多语言支持

### 🇨🇳 中文（www/js/cn.js）
```js
errmsg.err228 = "确定要启用";
errmsg.err229 = "确定要禁用";
errmsg.err230 = "吗？";
```

### 🌏 英文（www/js/en.js）
```js
errmsg.err228 = "Are you sure you want to enable ";
errmsg.err229 = "Are you sure you want to disable ";
errmsg.err230 = "?";
```

---

## 🔹 五、前端交互优化（www/html1/net_modem_list_module.ht）

### ✳️ 新增函数
**位置：第 326–340 行**
```js
function confirm_modem_switch(html_obj, rule_name, type) {
    var checked_val = $(html_obj).prev("input").attr("checked");
    var action_msg = "";

    if (checked_val == "checked") {
        action_msg = errmsg.err229 + " " + rule_name + " " + errmsg.err230;
    } else {
        action_msg = errmsg.err228 + " " + rule_name + " " + errmsg.err230;
    }

    if (confirm(action_msg)) {
        $(html_obj).self_list_shutdown(html_obj, { rule_name: rule_name, type: type });
    }

    return false;
}
```

### 🔄 修改事件绑定（第 743 行）
- 原代码：  
  ```js
  onclick='$(this).self_list_shutdown(this,{rule_name:"...", ...})'
  ```
- 修改后：  
  ```js
  onclick='confirm_modem_switch(this,"...", "...")'
  ```
