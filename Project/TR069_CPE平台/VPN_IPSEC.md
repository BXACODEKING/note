
swanctl --list-sas

ipsec statusall

ip -s xfrm state

在 /proc/net/xfrm_stat 中查看：IKE SA 父SA相关信息

root@OpenSDT:/proc# cat /proc/net/xfrm_stat 
XfrmInError             	0  # 总接收错误数（所有接收错误的总和）
XfrmInBufferError       	0  # 缓冲区错误（内存不足）
XfrmInHdrError          	0  # IPsec头部错误（格式/校验和错误）
XfrmInNoStates          	307  # 没有对应的SA状态 ← 您有307个错误！
XfrmInStateProtoError   	0   # 协议不匹配（如收到ESP但配置是AH）
XfrmInStateModeError    	0  # 模式不匹配（tunnel vs transport）
XfrmInStateSeqError     	0  # 序列号错误（重放攻击检测）
XfrmInStateExpired      	0   # SA已过期
XfrmInStateMismatch     	0  # SA不匹配（选择器错误）
XfrmInStateInvalid      	0  # SA无效
XfrmInTmplMismatch      	0   # 模板不匹配
XfrmInNoPols            	0  # 没有策略（数据包未匹配任何策略）
XfrmInPolBlock          	0   # 策略阻止
XfrmInPolError          	0  # 策略错误
XfrmOutError            	0   # 总发送错误
XfrmOutBundleGenError   	0   # 捆绑生成错误
XfrmOutBundleCheckError 	0  # 捆绑检查错误
XfrmOutNoStates         	0  # 没有出站SA
XfrmOutStateProtoError  	0  # 出站协议错误
XfrmOutStateModeError   	0  # 出站模式错误
XfrmOutStateSeqError    	0  # 出站序列号错误
XfrmOutStateExpired     	0   # 出站SA过期
XfrmOutPolBlock         	0  # 出站策略阻止
XfrmOutPolDead          	0   # 出站策略失效
XfrmOutPolError         	0  # 出站策略错误
XfrmFwdHdrError         	0  # 转发头部错误
XfrmOutStateInvalid     	0  # 出站状态无效
XfrmAcquireError        	0  # 获取错误
