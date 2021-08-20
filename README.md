# 简介
使用阿里云提供的 api，管理在阿里云购买的域名。支持增、删、查、改等基本操作，以及配合 crontab 实现自建 ddns 的 bash 脚本
# 配置
下载脚本
```
wget https://raw.staticdn.net/qinghuas/alidns-bash/master/aldns.sh
```
使用 ```vim``` 命令或 ```xftp``` 配合 ```Notepad++``` 编辑 ```aldns.sh``` 
* 前往 https://usercenter.console.aliyun.com/ 获取 ```AccessKeyId``` 与 ```AccessKeySecret``` 后填入对应位置
* 在 ```ManagementDomain``` 后填入需要管理的域名。例如 ```github.com```
* API地址 ```ALiServerAddr``` 通常不需要更改
* DDNS设置 ```ddns_record_id``` 和 ```ddns_record_value``` 如若不配置ddns服务请留空

配置运行环境使脚本通过自检
* 未填入 ```AccessKeyId``` 会报错 ```缺少AccessKeyId.``` 并退出
* 未填入 ```AccessKeySecret``` 会报错 ```缺少AccessKeySecret.``` 并退出
* 未安装 ```jq``` 命令会报错 ```缺少 jq 命令.``` 并退出
* 未安装 ```column``` 命令会报错 ```缺少 column 命令.``` 并退出
* 若目录 ```/root/alidns``` 不存在会自动建立，用于存放请求响应文件以及日志

# 用法
* 添加解析。执行该命令后按提示操作
```
bash aldns.sh add
```
* 查看解析列表，同时将输出每条解析记录对应的 ID
```
bash aldns.sh list
```
* 启用某个解析记录。须传入该解析记录 ID。假设 ID 为 ```19436255792427984``` ，则执行
```
bash aldns.sh enable 19436255792427984
```
* 停用某个解析记录。须传入该解析记录 ID。假设 ID 为 ```19436255792427984``` ，则执行
```
bash aldns.sh disable 19436255792427984
```
* 删除某个解析记录。须传入该解析记录 ID。假设 ID 为 ```19436255792427984``` ，则执行
```
bash aldns.sh del 19436255792427984
```
* 编辑某个解析记录。须传入该解析记录 ID。假设 ID 为 ```19436255792427984``` ，则执行如下命令，然后按提示操作。若在设置新的主机记录和记录值时直接回车，将沿用旧的设置
```
bash aldns.sh edit 19436255792427984
```
* 指定查询规则匹配解析记录。大小写敏感。例如，查询所有记录值为 8.8.8.8 的解析记录
```
bash aldns.sh search Value 8.8.8.8
```
* 查询所有解析类型为 A 的解析记录。大小写敏感。可选 ```A/NS/MX/TXT/CNAME/SRV/AAAA/CAA/REDIRECT_URL/FORWARD_URL```
```
bash aldns.sh search Type A
```
* 查询所有主机记录为 ddns 的解析记录
```
bash aldns.sh search RR ddns
```
若确定查询结果仅有 1 条，可以在 主机记录值 后加上参数 edit ，进入该记录的修改流程
```
bash aldns.sh search RR ddns edit
```
* 输出管理域名
```
bash aldns.sh account
```
* 输出帮助信息
```
bash aldns.sh help
```
* 输出 ddns 变更日志
```
bash aldns.sh log
```
# 管理多个域名
将 ```aldns.sh``` 复制一份后编辑 ```aldns2.sh``` 更改 ```ManagementDomain``` 项即可。如若域名在不同账户下，须填入对应账户的 ```AccessKeyId``` 与 ```AccessKeySecret```
```
cp /root/aldns.sh /root/aldns2.sh
```
# 省去执行时所需的bash
执行如下命令后，后续调用可省略。例如 ```aldns list```
```
mv /root/aldns.sh /usr/bin/aldns
chmod 755 /usr/bin/aldns
```
# 配置 DDNS
* 首先添加一条A记录解析，然后获取解析记录ID，将解析记录ID与主机记录分别填入 ```ddns_record_id``` 和 ```ddns_record_value``` 内
* 然后配置 crontab 添加定时任务。例如：每10分钟检查一次，则 ```crontab``` 的写法：
```
*/10 * * * * /bin/bash /root/aldns.sh ddns
```
* ```ip``` 变更 ```log``` 文件位于 ```/root/alidns/ddns.domain.value.update.log```
# 致谢
感谢 @h46incon 完成了阿里云API请求的基础框架与操作的项目 https://github.com/h46incon/AliDDNSBash

感谢 @ReMember 发布的文章 https://xvcat.com/post/1096
