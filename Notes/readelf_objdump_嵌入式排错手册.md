# readelf / objdump 嵌入式 Linux 排错手册

## 1. ELF 基础
ELF（Executable and Linkable Format）是 Linux / Unix 系统使用的二进制文件格式。

常见 ELF 文件：
- 可执行程序
- `.o` 目标文件
- `.so` 动态库
- `.a` 静态库

查看文件是否为 ELF：

```bash
file app
```

---

# 2. readelf 常用命令

## 查看 ELF 头

```bash
readelf -h app
```

关注字段：

- Class (ELF32 / ELF64)
- Machine (CPU 架构)
- Entry point address

示例：

```
Class: ELF32
Machine: MIPS
```

---

## 查看程序段

```bash
readelf -l app
```

重点关注：

```
INTERP
LOAD
DYNAMIC
```

查看动态加载器：

```bash
readelf -l app | grep interpreter
```

示例：

```
/lib/ld-musl-mipsel.so.1
```

---

## 查看依赖动态库

```bash
readelf -d app
```

输出示例：

```
NEEDED Shared library: [libmosquitto.so.1]
NEEDED Shared library: [libpthread.so.0]
```

说明程序依赖这些动态库。

---

## 查看段结构

```bash
readelf -S app
```

常见段：

| 段名 | 作用 |
|-----|------|
| .text | 程序代码 |
| .data | 已初始化变量 |
| .bss | 未初始化变量 |
| .rodata | 常量 |
| .symtab | 符号表 |

---

# 3. objdump 常用命令

## 查看动态符号

```bash
objdump -T app
```

示例：

```
U mosquitto_connect
```

U 表示 Undefined，说明需要外部库提供该符号。

---

## 反汇编程序

```bash
objdump -d app
```

用于查看汇编代码。

---

# 4. 嵌入式程序运行失败排查流程

## Step1：确认 CPU 架构

```bash
readelf -h app
```

检查：

```
Machine
```

常见架构：

- MIPS
- ARM
- AArch64
- x86-64

如果架构不匹配，程序无法运行。

---

## Step2：确认 32/64 位

查看：

```
Class
```

如果系统是 32 位而程序是 64 位，会运行失败。

---

## Step3：检查动态库依赖

```bash
readelf -d app
```

查看 NEEDED 字段。

如果设备没有对应 `.so` 文件，程序无法启动。

---

## Step4：检查动态链接器

```bash
readelf -l app | grep interpreter
```

示例：

```
/lib/ld-musl-mipsel.so.1
```

如果设备没有该 loader，程序会报：

```
not found
```

---

## Step5：检查符号

如果报错：

```
undefined symbol
```

使用：

```bash
objdump -T app
```

查找未解析符号。

---

# 5. 常见错误类型

## 1 架构错误

表现：

```
not found
```

原因：交叉编译工具链错误。

---

## 2 动态库缺失

表现：

```
error while loading shared libraries
```

解决：安装或拷贝缺失库。

---

## 3 loader 不存在

表现：

```
not found
```

实际原因：动态链接器路径错误。

---

## 4 ABI 不兼容

表现：

```
Illegal instruction
```

原因：CPU 指令集不兼容。

---

# 6. 嵌入式排错黄金命令

## 查看架构

```bash
file app
```

## 查看 ELF 头

```bash
readelf -h app
```

## 查看依赖库

```bash
readelf -d app
```

## 查看 loader

```bash
readelf -l app | grep interpreter
```

## 查看符号

```bash
objdump -T app
```

---

# 7. 推荐排查顺序

```
file app
readelf -h app
readelf -d app
readelf -l app | grep interpreter
objdump -T app
```

---

# 8. 实战案例

设备运行程序：

```
./mqtt_app
```

报错：

```
not found
```

排查：

```
readelf -l mqtt_app
```

发现：

```
/lib/ld-linux-armhf.so.3
```

但设备只有：

```
/lib/ld-musl-armhf.so.1
```

结论：

程序使用 glibc 编译，但设备是 musl 系统。

---

# 9. 总结

嵌入式程序运行失败通常来自：

1. CPU 架构错误
2. 32/64 位不匹配
3. 动态库缺失
4. loader 不存在
5. ABI 不兼容

使用 readelf / objdump 可以在不运行程序的情况下定位大多数问题。

