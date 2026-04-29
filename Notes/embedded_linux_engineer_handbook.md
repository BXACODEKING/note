# 嵌入式 Linux 知识手册（工程师完整版）

版本：2.0\
用途：长期学习与工程参考

------------------------------------------------------------------------

# 目录

1.  嵌入式 Linux 全景架构
2.  硬件基础
3.  存储体系（DDR / NOR / NAND / eMMC / SD）
4.  嵌入式 Linux 启动流程（完整）
5.  Bootloader（U‑Boot）
6.  Device Tree 设备树
7.  Linux Kernel 内核架构
8.  Linux Kernel 十大子系统
9.  设备驱动模型
10. MTD / UBI / UBIFS 存储体系
11. Root FileSystem
12. Build System（Buildroot / Yocto / OpenWrt）
13. 嵌入式网络体系
14. 系统服务架构
15. 调试与排错方法论
16. 性能优化
17. 企业级嵌入式开发流程
18. 工程师成长路线

------------------------------------------------------------------------

# 1 嵌入式 Linux 全景架构

完整嵌入式 Linux 系统：

    Hardware
       │
    BootROM
       │
    Bootloader
       │
    Linux Kernel
       │
    Device Drivers
       │
    Root FileSystem
       │
    System Services
       │
    Applications

运行关系：

    Application
        │
    System Library
        │
    System Call
        │
    Kernel
        │
    Driver
        │
    Hardware

------------------------------------------------------------------------

# 2 硬件基础

嵌入式系统通常由以下部分组成：

    CPU
    DDR
    Flash
    Peripheral

常见 CPU 架构：

    ARM
    MIPS
    RISC‑V
    x86

SoC 内部通常包含：

    UART
    SPI
    I2C
    GPIO
    USB
    PCIe
    Ethernet MAC
    Timer
    DMA
    Interrupt Controller

------------------------------------------------------------------------

# 3 存储体系

## 3.1 DDR

DDR 是系统运行内存。

特点：

-   高速
-   断电丢失
-   存储运行程序

Linux 运行在 DDR 中。

启动时：

    Flash → DDR → CPU执行

------------------------------------------------------------------------

## 3.2 NOR Flash

特点：

-   随机访问
-   可以直接执行代码
-   容量小
-   成本高

用途：

    Bootloader

------------------------------------------------------------------------

## 3.3 NAND Flash

特点：

-   容量大
-   成本低
-   坏块多
-   需要 ECC

用途：

    Kernel
    RootFS
    Data

------------------------------------------------------------------------

## 3.4 SD卡

结构：

    NAND Flash + Controller

Linux设备：

    /dev/mmcblk0

------------------------------------------------------------------------

## 3.5 eMMC

本质：

    NAND Flash + Controller + 标准接口

特点：

-   稳定
-   速度快
-   内置坏块管理

------------------------------------------------------------------------

# 4 嵌入式 Linux 启动流程

完整流程：

    Power On
     │
    BootROM
     │
    Bootloader
     │
    Kernel
     │
    RootFS
     │
    Init
     │
    Services
     │
    Application

------------------------------------------------------------------------

# 5 Bootloader（U‑Boot）

主要功能：

1 初始化硬件\
2 初始化DDR\
3 加载Kernel\
4 传递启动参数

常见命令：

    printenv
    setenv
    saveenv
    bootm
    bootz
    tftpboot

------------------------------------------------------------------------

# 6 Device Tree

Device Tree 用于描述硬件资源。

    CPU
    Memory
    GPIO
    UART
    SPI
    I2C
    Ethernet

作用：

    让内核知道硬件结构

------------------------------------------------------------------------

# 7 Linux Kernel 内核架构

核心职责：

    进程管理
    内存管理
    文件系统
    网络协议栈
    驱动管理

源码目录：

    arch
    drivers
    net
    fs
    mm
    kernel

------------------------------------------------------------------------

# 8 Linux Kernel 十大子系统

    Process Scheduler
    Memory Management
    Virtual File System
    Network Stack
    Driver Framework
    IPC
    Security
    Power Management
    Interrupt
    Timer

------------------------------------------------------------------------

# 9 设备驱动模型

Linux 驱动结构：

    Device
    Driver
    Bus

常见总线：

    Platform
    I2C
    SPI
    PCI
    USB

------------------------------------------------------------------------

# 10 MTD / UBI / UBIFS

Flash 软件栈：

    NAND
     │
    MTD
     │
    UBI
     │
    UBIFS

作用：

MTD：设备抽象层\
UBI：坏块管理\
UBIFS：文件系统

------------------------------------------------------------------------

# 11 RootFS

结构：

    /
     ├ bin
     ├ sbin
     ├ etc
     ├ dev
     ├ proc
     ├ sys
     ├ lib

------------------------------------------------------------------------

# 12 Build System

主流构建系统：

    Buildroot
    Yocto
    OpenWrt

构建内容：

    Toolchain
    Kernel
    RootFS
    Bootloader
    Packages

------------------------------------------------------------------------

# 13 嵌入式网络

网络层结构：

    Application
    Socket
    TCP/IP
    Driver
    Hardware

------------------------------------------------------------------------

# 14 系统服务

    ssh
    dnsmasq
    hostapd
    mqtt
    tr069

------------------------------------------------------------------------

# 15 调试体系

    dmesg
    tcpdump
    strace
    gdb
    perf

------------------------------------------------------------------------

# 16 性能优化

关注：

    CPU
    Memory
    IO
    Network

------------------------------------------------------------------------

# 17 企业开发流程

    需求
    架构
    BSP
    驱动
    系统集成
    测试
    发布
    OTA

------------------------------------------------------------------------

# 18 工程师成长路线

初级：

    应用
    脚本
    系统配置

中级：

    网络
    系统服务
    Buildroot/OpenWrt

高级：

    Kernel
    Driver
    Bootloader

专家：

    BSP
    架构设计
    系统优化

------------------------------------------------------------------------

# 总结

嵌入式 Linux 的核心能力：

    理解系统
    掌握调试
    深入底层

当你可以从：

    Application
    ↓
    RootFS
    ↓
    Kernel
    ↓
    Driver
    ↓
    Hardware

完整定位问题时，就具备高级工程师能力。
