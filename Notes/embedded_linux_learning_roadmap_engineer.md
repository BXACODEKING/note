# 嵌入式 Linux 学习路线图（工程师版）

作者：ChatGPT\
版本：1.0

------------------------------------------------------------------------

# 目录

1.  嵌入式Linux系统整体架构
2.  嵌入式Linux启动流程
3.  学习路线图（工程师成长路径）
4.  阶段一：Linux与C语言基础
5.  阶段二：嵌入式Linux系统结构
6.  阶段三：Bootloader（U-Boot）
7.  阶段四：Linux Kernel 内核
8.  阶段五：设备驱动开发
9.  阶段六：嵌入式存储系统
10. 阶段七：RootFS 与用户空间
11. 阶段八：Build System 构建系统
12. 阶段九：系统服务与网络
13. 阶段十：嵌入式应用开发
14. 调试能力体系
15. 常见嵌入式硬件知识
16. 推荐学习顺序
17. 工程师能力成长路线

------------------------------------------------------------------------

# 1 嵌入式Linux系统整体架构

完整嵌入式Linux系统由以下部分组成：

    硬件平台
      │
    Bootloader
      │
    Linux Kernel
      │
    Device Driver
      │
    Root File System
      │
    System Service
      │
    Application

开发侧还包含：

    Toolchain
    Build System
    Debug Tools
    Development Environment

整体逻辑：

    Application
        │
    System Library (glibc/musl)
        │
    System Call
        │
    Linux Kernel
        │
    Device Driver
        │
    Hardware

------------------------------------------------------------------------

# 2 嵌入式Linux启动流程

嵌入式设备上电后的完整流程：

    Power On
       │
    CPU执行ROM Code
       │
    加载 Bootloader
       │
    Bootloader 初始化硬件
       │
    加载 Linux Kernel
       │
    Kernel 初始化
       │
    挂载 RootFS
       │
    启动 init
       │
    启动系统服务
       │
    运行应用程序

更细化流程：

    ROM Code
     ↓
    Bootloader (U-Boot)
     ↓
    Kernel
     ↓
    RootFS
     ↓
    Init (PID 1)
     ↓
    Daemon
     ↓
    Application

------------------------------------------------------------------------

# 3 学习路线图（工程师成长路径）

嵌入式Linux工程师可以划分为7层能力：

    硬件理解
    Bootloader
    Kernel
    Driver
    RootFS
    System Service
    Application

开发能力：

    Toolchain
    Build System
    Debug能力
    性能分析能力

------------------------------------------------------------------------

# 4 阶段一：Linux与C语言基础

必须掌握：

## Linux命令

核心命令：

    ps
    top
    netstat
    ip
    route
    ss
    lsof
    strace
    tcpdump
    dmesg

文件操作：

    ls
    cp
    mv
    rm
    find
    grep
    awk
    sed

系统管理：

    mount
    df
    free
    uname

Shell脚本：

    bash
    awk
    sed
    cron

## C语言基础

重点掌握：

-   指针
-   结构体
-   内存管理
-   文件IO
-   socket编程
-   多线程

常见系统接口：

    open
    read
    write
    ioctl
    select
    poll
    epoll

------------------------------------------------------------------------

# 5 阶段二：嵌入式Linux系统结构

理解系统组成：

    Bootloader
    Kernel
    Driver
    RootFS
    Application

必须理解：

-   系统启动流程
-   设备树
-   rootfs结构

RootFS结构：

    /
     ├── bin
     ├── sbin
     ├── etc
     ├── dev
     ├── proc
     ├── sys
     ├── lib
     ├── usr

------------------------------------------------------------------------

# 6 阶段三：Bootloader（U-Boot）

Bootloader作用：

1 初始化硬件 2 初始化DDR 3 初始化串口 4 加载Kernel 5 传递启动参数

U-Boot常见命令：

    printenv
    setenv
    saveenv
    bootm
    bootz
    booti
    tftpboot

常见环境变量：

    bootargs
    bootcmd
    ipaddr
    serverip

启动参数示例：

    console=ttyS0,115200 root=/dev/mtdblock3

------------------------------------------------------------------------

# 7 阶段四：Linux Kernel 内核

Linux Kernel负责：

-   进程管理
-   内存管理
-   文件系统
-   网络协议栈
-   驱动框架

内核源码结构：

    arch/
    drivers/
    fs/
    net/
    mm/
    kernel/

必须理解：

-   系统调用
-   调度器
-   内存管理
-   网络协议栈

------------------------------------------------------------------------

# 8 阶段五：设备驱动开发

驱动作用：

    硬件 -> Linux接口

字符设备驱动：

    open
    read
    write
    ioctl

常见设备：

    /dev/ttyS0
    /dev/watchdog
    /dev/i2c-0
    /dev/spidev

总线驱动：

    I2C
    SPI
    UART
    USB
    PCIe

GPIO：

    /sys/class/gpio

网络驱动涉及：

    MAC
    PHY
    MDIO

------------------------------------------------------------------------

# 9 阶段六：嵌入式存储系统

常见存储类型：

    DDR
    NOR Flash
    NAND Flash
    SD
    eMMC

## DDR

DDR是系统运行内存。

特点：

    速度快
    断电丢失
    存储运行程序

Linux运行在DDR中。

## NOR Flash

特点：

    随机访问
    可直接执行代码
    容量小
    价格高

常用于：

    Bootloader

## NAND Flash

特点：

    容量大
    成本低
    有坏块

常用于：

    Kernel
    RootFS
    Data

## SD卡

本质：

    NAND Flash + 控制器

Linux设备：

    /dev/mmcblk0

## eMMC

本质：

    NAND Flash + 控制器 + 固定接口

类似：

    焊在板子上的SD卡

------------------------------------------------------------------------

# 10 阶段七：RootFS 与用户空间

RootFS是用户空间环境。

常见实现：

    BusyBox
    Buildroot
    OpenWrt
    Yocto

包含：

    shell
    system service
    library
    application

------------------------------------------------------------------------

# 11 阶段八：Build System 构建系统

现代嵌入式开发基本依赖构建系统。

常见系统：

## Buildroot

特点：

-   简单
-   适合快速构建

## Yocto

特点：

-   企业级
-   可定制性强

## OpenWrt

特点：

-   网络设备
-   包管理

构建内容：

    toolchain
    kernel
    rootfs
    bootloader
    packages

------------------------------------------------------------------------

# 12 阶段九：系统服务与网络

常见服务：

    ssh
    dnsmasq
    hostapd
    ntp

网络组件：

    netifd
    iptables
    nftables
    ppp
    dhcp

常见网络工具：

    tcpdump
    wireshark
    ss
    netstat

------------------------------------------------------------------------

# 13 阶段十：嵌入式应用开发

典型应用：

    Web管理界面
    MQTT
    TR069
    IoT平台
    AI边缘计算

常见技术：

    CGI
    REST API
    WebSocket
    MQTT

------------------------------------------------------------------------

# 14 调试能力体系

调试是嵌入式工程师核心能力。

## 系统调试

    dmesg
    logread
    journalctl

## 网络调试

    tcpdump
    wireshark
    iptables

## 程序调试

    gdb
    gdbserver
    strace
    ltrace

## 性能调试

    perf
    top
    htop
    vmstat

------------------------------------------------------------------------

# 15 常见嵌入式硬件知识

需要理解：

    CPU架构
    ARM
    MIPS
    RISC-V

常见外设：

    UART
    SPI
    I2C
    GPIO
    USB
    PCIe

常见芯片资源：

    DDR
    Flash
    Timer
    Interrupt
    DMA

------------------------------------------------------------------------

# 16 推荐学习顺序

建议学习路径：

    Linux基础
    C语言
    嵌入式系统结构
    Bootloader
    Kernel
    Driver
    存储系统
    Build System
    系统服务
    应用开发

------------------------------------------------------------------------

# 17 工程师能力成长路线

初级工程师：

    应用开发
    脚本
    系统配置

中级工程师：

    系统服务开发
    网络
    调试
    Buildroot/OpenWrt

高级工程师：

    Kernel
    Driver
    Bootloader
    系统架构

专家级工程师：

    BSP开发
    系统性能优化
    平台架构设计

------------------------------------------------------------------------

# 结语

嵌入式Linux工程师的成长核心是：

    理解系统
    掌握调试
    深入底层

当你能够从：

    Application
    ↓
    RootFS
    ↓
    Kernel
    ↓
    Driver
    ↓
    Hardware

完整定位问题时，你就已经具备高级工程师能力。
