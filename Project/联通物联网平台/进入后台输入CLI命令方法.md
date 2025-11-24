
进入后台
telnet 127.0.0.1
密码 super
输入 ？ 得到相关提示
```
router>    
  enable      Turn on privileged mode command
  exit        Exit current mode and down to previous mode
  help        Description of the interactive help system
  list        Print command list
  ping        Send icmp echo message
  show        Show running system information
  telnet      Open a telnet connection
  terminal    Set terminal line parameters
  traceroute  Trace route to destination
  who         Display who is on vty
```

输入 configure terminal 
输入 service + tab
输入 service logbackup
输入 backup max 6
输入 wr
Configuration saved to /tmp/hdconfig/cli.conf 成功保存到cli了！