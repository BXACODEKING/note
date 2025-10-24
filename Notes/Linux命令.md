---
tags:
  - linux
  - command
  - cheat-sheet
title: Linux命令笔记
---

# 🧭 Linux 命令笔记

---

## 📂 文件与目录
`pwd` — 显示当前路径  
`mkdir` — 创建目录  
`rm -rf` — 删除文件或目录  
`cp -r` — 复制文件或目录
``` bash
cp main.c backup/        # 复制文件到 backup 目录
cp -r src/ backup/src/   # 递归复制整个 src 目录
cp -f a.txt b.txt        # 覆盖复制
```
`mv` — 移动或重命名文件  
``` bash
mv a.txt b.txt           # 重命名 a.txt → b.txt
mv test/ backup/         # 移动 test 目录到 backup/
mv -f a.txt /tmp/        # 强制移动
```


---

## ⚙️ 系统信息
`top` — 查看进程与CPU占用  
`htop` — 更友好的进程查看器（若已安装）  
`df -h` — 查看磁盘空间  
`free -h` — 查看内存使用  
`uptime` — 查看系统运行时间  
`uname -a` — 查看系统信息  
`cat /proc/cpuinfo` — 查看CPU信息  
`cat /proc/meminfo` — 查看内存信息  

---

## 🌐 网络相关
`ifconfig` — 查看网络接口信息  
`ip addr` — 查看IP地址  
`ping 8.8.8.8` — 测试网络连通性  
`netstat -anp` — 查看所有连接和端口  
`ss -tunap` — 查看TCP/UDP连接  
`curl http://example.com` — 测试HTTP请求  
`wget URL` — 下载文件  
`traceroute` — 路由跟踪  

---

## 🔒 权限与用户
`chmod 755 file` — 修改权限  
`chown root:root file` — 修改所有者  
`sudo` — 提权执行命令  
`whoami` — 显示当前用户名  
`id` — 显示用户ID与组ID  
`passwd` — 修改密码  

---

## 📜 日志与调试
`dmesg | tail` — 查看内核日志  
`journalctl -xe` — 查看系统日志  
`cat /var/log/messages` — 查看消息日志  
`tail -f /var/log/syslog` — 实时查看日志  

---

## 🧰 常用技巧
`grep "keyword" file` — 搜索关键字  
`ps -ef | grep process` — 查找进程  
`kill -9 pid` — 强制结束进程  
`tar -zxvf file.tar.gz` — 解压文件  
`find / -name "file"` — 查找文件  
`echo $PATH` — 查看环境变量  
`history` — 查看命令历史  

---

## 🧠 示例格式
> 添加新命令时参考此格式：
