#!/bin/bash

# AccessKey
AccessKeyId=''
AccessKeySecret=''
# 管理域名
Domain=''
# API地址
ALiServerAddr='https://alidns.aliyuncs.com'
# DDNS设置
DdnsRecordId=''
# 其他设置
DefaultTTL='600'
# 致谢 https://xvcat.com/post/1096
BasePath=$(cd $(dirname ${BASH_SOURCE}) ; pwd)
BaseName=$(basename $BASH_SOURCE)

red='\033[31m'
green='\033[32m'
end='\033[0m'

check()
{
	if [[ "${AccessKeyId}" = "" ]];then
		echo "缺少 AccessKeyId."
		exit
	fi
	if [[ "${AccessKeySecret}" = "" ]];then
		echo "缺少 AccessKeySecret."
		exit
	fi
	if [[ ! -f "/usr/bin/jq" ]];then
		echo "缺少 jq 命令."
		exit
	fi
	if [[ ! -d "/root/alidns" ]];then
		mkdir /root/alidns
	fi
}

put_param()
{
	eval g_pkey_${g_pn}=$1
	eval g_pval_$1=$2
	g_pn=$((g_pn + 1))
}

reset_func_ret()
{
	_func_ret=""
}

rawurl_encode()
{
	reset_func_ret

	local string="${1}"
	local strlen=${#string}
	local encoded=""
	local pos c o

	pos=0
	while [ ${pos} -lt ${strlen} ]
	do
		c=${string:$pos:1}
		case "$c" in
			[-_.~a-zA-Z0-9] ) o="${c}" ;;
			* )               o=$(printf "%%%02X" "'$c")
		esac
		encoded="${encoded}${o}"
		pos=$(($pos + 1))
	done
	_func_ret="${encoded}" 
}

calc_signature()
{
	reset_func_ret

	local sorted_key=$(
		i=0
		while [ $i -lt ${g_pn} ]
		do
			eval key="\$g_pkey_$i"
			echo "${key}"
			i=$((++i))
		done | LC_COLLATE=C sort
	)

	local query_str=""

	for key in ${sorted_key}
	do
		eval val="\$g_pval_${key}"

		rawurl_encode "${key}"
		key_enc=${_func_ret}
		rawurl_encode "${val}"
		val_enc=${_func_ret}

		query_str="${query_str}${key_enc}=${val_enc}&"
	done

	query_str=${query_str%'&'}

	# encode
	rawurl_encode "${query_str}"
	local encoded_str=${_func_ret}
	local str_to_signed="GET&%2F&"${encoded_str}

	local key_sign="${AccessKeySecret}&"
	_func_ret=$(/bin/echo -n ${str_to_signed} | openssl dgst -binary -sha1 -hmac ${key_sign} | openssl enc -base64)
}

pack_params()
{
	reset_func_ret
	local ret=""
	local key key_enc val val_enc

	local i=0
	while [ $i -lt ${g_pn} ]
	do
		eval key="\$g_pkey_${i}"
		eval val="\$g_pval_${key}"
		rawurl_encode "${key}"
		key_enc=${_func_ret}
		rawurl_encode "${val}"
		val_enc=${_func_ret}

		ret="${ret}${key_enc}=${val_enc}&"
		i=$((++i))
	done

	#delete last "&"
	_func_ret=${ret%"&"}
}

send_request()
{
	# put signature
	calc_signature
	local signature=${_func_ret}
	put_param "Signature" "${signature}"

	# pack all params
	pack_params
	local packed_params=${_func_ret}

	local req_url="${ALiServerAddr}/?${packed_params}"
	local req_url=$(echo $req_url | sed 's#?=&#?#g')

	#echo $req_url
	curl -s "${req_url}" > /root/alidns/$1
}

put_params_public()
{
	put_param "key" "value"
	put_param "Format" "JSON"
	put_param "Version" "2015-01-09"
	put_param "AccessKeyId" "${AccessKeyId}"
	put_param "SignatureMethod" "HMAC-SHA1"
	put_param "SignatureVersion" "1.0"
	put_param "Timestamp" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
	put_param "SignatureNonce" "$(openssl rand -hex 16)"
}

add_parsing()
{
	#主机记录
	read -p "主机记录:" HostRecord
	if [[ "${HostRecord}" = "" ]];then
		echo -e "${red} 主机记录不能为空. ${end}"
		exit
	else
		echo -e "${green} 主机记录:$HostRecord ${end}"
	fi
	#记录值
	read -p "记录值:" RecordValue
	if [[ "${RecordValue}" = "" ]];then
		echo -e "${red} 记录值不能为空. ${end}"
		exit
	else
		echo -e "${green} 记录值:$RecordValue ${end}"
	fi
	#解析记录类型
	read -p "解析记录类型(A/NS/MX/TXT/CNAME/SRV/AAAA/CAA/REDIRECT_URL/FORWARD_URL):" ParsingRecordTypes
	if [[ "${ParsingRecordTypes}" = "" ]];then
		echo -e "${green} 使用默认解析记录类型:A ${end}"
		ParsingRecordTypes='A'
	else
		echo -e "${green} 解析记录类型:$ParsingRecordTypes ${end}"
	fi
	#如若是MX记录,询问MX记录优先级
	if [[ "${ParsingRecordTypes}" = "MX" ]];then
		read -p "MX记录优先级:" MxRecordPriority
		if [[ "${MxRecordPriority}" = "" ]];then
			echo -e "${red} MX记录优先级不能为空. ${end}"
			exit
		else
			echo -e "${green} MX记录优先级:$MxRecordPriority ${end}"
		fi
	fi
	#TTL值
	read -p "TTL值:" ttl_value
	if [[ "${ttl_value}" = "" ]];then
		ttl_value="${DefaultTTL}"
	fi
	echo -e "${green} TTL值:${ttl_value} ${end}"
	
	put_params_public
	put_param "Action" "AddDomainRecord"
	put_param "DomainName" "${Domain}"
	put_param "RR" "${HostRecord}"
	put_param "Type" "${ParsingRecordTypes}"
	put_param "Value" "${RecordValue}"
	put_param "TTL" "${ttl_value}"
	if [[ "${ParsingRecordTypes}" = "MX" ]];then
		put_param "Priority" "${MxRecordPriority}"
	fi
	
	echo "请求发送中..."
	send_request add.parsing.response.json

	ResponseFile='/root/alidns/add.parsing.response.json'
	Message=$(jq .Message $ResponseFile | sed 's#"##g')
	if [[ "$Message" != "null" ]];then
		echo -e "${red} 添加失败,以下信息供参考: ${end}"
		echo "RequestId -> $(jq .RequestId $ResponseFile | sed 's#"##g')"
		echo "HostId    -> $(jq .HostId $ResponseFile | sed 's#"##g')"
		echo "Code      -> $(jq .Code $ResponseFile | sed 's#"##g')"
		echo "Message   -> $(jq .Message $ResponseFile | sed 's#"##g')"
		echo "Recommend -> $(jq .Recommend $ResponseFile | sed 's#"##g')"
	else
		echo -e "${green} 添加成功. ${end}"
		echo "RecordId -> $(jq .RecordId $ResponseFile | sed 's#"##g')"
	fi
}

record_list()
{
	put_params_public
	put_param "Action" "DescribeDomainRecords"
	put_param "DomainName" "${Domain}"
	put_param "PageNumber" "1"
	put_param "PageSize" "500"
	
	echo -e "${green} 正在加载中... ${end}"
	send_request record.list.response.json
	RecordsNumber=$(cat /root/alidns/record.list.response.json | jq ".TotalCount")
	echo "ID | 主机记录 | 状态 | 类型 | 记录值 | 记录ID | TTL" > /root/alidns/record.list.response.txt
	for (( i=0; i < ${RecordsNumber}; i++ ))
	do
		get()
		{
			cat /root/alidns/record.list.response.json | jq ".DomainRecords.Record[${i}].$1" | sed 's/"//g'
		}
		id=$(expr $i + 1)
		RR=$(get RR)
		if [[ "$(get Status)" = "ENABLE" ]];then
			Status="${green} enable ${end}"
		else
			Status="${red} disable ${end}"
		fi
		#Locked=$(get Locked)
		Type=$(get Type)
		Value=$(get Value)
		RecordId=$(get RecordId)
		TTL=$(get TTL)
		echo -e "$id | $RR | $Status | $Type | $Value | $RecordId | $TTL" >> /root/alidns/record.list.response.txt
	done
	column -t -s '|' /root/alidns/record.list.response.txt > /root/alidns/record.list.txt
	
	clear
	cat /root/alidns/record.list.txt
}

set_recording_status()
{
	if [[ "${parameter2}" = "" ]];then
		echo -e "${red} 需要传入记录ID. ${end}"
		exit
	fi
	
	put_params_public
	put_param "Action" "SetDomainRecordStatus"
	put_param "RecordId" "${parameter2}"
	if [[ "${parameter1}" = "enable" ]];then
		put_param "Status" "Enable"
	else
		put_param "Status" "Disable"
	fi

	echo "请求发送中..."
	send_request set.recording.status.response.json
	ResponseFile='/root/alidns/set.recording.status.response.json'
	RecordId=$(jq .RecordId $ResponseFile | sed 's#"##g')

	if [[ "$RecordId" = "null" ]];then
		echo -e "${red} 操作失败. ${end}"
	else	
		echo -e "${green} 操作成功. ${end}"
	fi
}

delete_parse_record()
{
	if [[ "${parameter2}" = "" ]];then
		echo -e "${red} 需要传入记录ID. ${end}"
		exit
	fi

	bash "${BasePath}"/"${BaseName}" getinfo "${parameter2}"
	ResponseFile='/root/alidns/get.analysis.record.information.response.json'
	if [[ "$(cat ${ResponseFile} | jq .RR)" = "null" ]];then
		echo -e "${red} 传入的记录ID无效. ${end}"
		exit
	fi
	
	put_params_public
	put_param "Action" "DeleteDomainRecord"
	put_param "RecordId" "${parameter2}"
	
	echo "请求发送中..."
	send_request delete.parse.record.response.json
	echo -e "${green} 请求已发送.${end}"
}

edit_parsing_records()
{
	if [[ "${parameter2}" = "" ]];then
		echo -e "${red} 需要传入记录ID. ${end}"
		exit
	fi
	
	bash "${BasePath}"/"${BaseName}" getinfo "${parameter2}"
	ResponseFile='/root/alidns/get.analysis.record.information.response.json'
	before_record_rr=$(jq .RR ${ResponseFile} | sed 's#"##g')
	before_record_type=$(jq .Type ${ResponseFile} | sed 's#"##g')
	before_record_value=$(jq .Value ${ResponseFile} | sed 's#"##g')
	
	if [[ "$(cat ${ResponseFile} | jq .RR)" = "null" ]];then
		echo -e "${red} 传入的记录ID无效. ${end}"
		exit
	fi

	#主机记录
	read -p "新主机记录:" HostRecord
	if [[ "${HostRecord}" = "" ]];then
		HostRecord="${before_record_rr}"
		echo -e "${green} 主机记录(未变更):${HostRecord} ${end}"
	else
		echo -e "${green} 主机记录:${HostRecord} ${end}"
	fi
	#记录值
	read -p "新记录值:" RecordValue
	if [[ "${RecordValue}" = "" ]];then
		RecordValue="${before_record_value}"
		echo -e "${green} 记录值(未变更):${RecordValue} ${end}"
	else
		echo -e "${green} 记录值:${RecordValue} ${end}"
	fi
	#解析记录类型
	read -p "新解析记录类型(A/NS/MX/TXT/CNAME/SRV/AAAA/CAA/REDIRECT_URL/FORWARD_URL):" ParsingRecordTypes
	if [[ "${ParsingRecordTypes}" = "" ]];then
		ParsingRecordTypes="${before_record_type}"
		echo -e "${green} 解析记录类型(未变更):${ParsingRecordTypes} ${end}"
	else
		echo -e "${green} 解析记录类型:${ParsingRecordTypes} ${end}"
	fi
	#如若是MX记录,询问MX记录优先级
	if [[ "${ParsingRecordTypes}" = "MX" ]];then
		read -p "新MX记录优先级:" MxRecordPriority
		if [[ "${MxRecordPriority}" = "" ]];then
			echo -e "${red} MX记录优先级不能为空. ${end}"
			exit
		else
			echo -e "${green} MX记录优先级:${MxRecordPriority} ${end}"
		fi
	fi
	#TTL值
	read -p "TTL值:" ttl_value
	if [[ "${ttl_value}" = "" ]];then
		ttl_value="${DefaultTTL}"
	fi
	echo -e "${green} TTL值:${ttl_value} ${end}"
	
	put_params_public
	put_param "Action" "UpdateDomainRecord"
	put_param "RecordId" "${parameter2}"
	put_param "RR" "${HostRecord}"
	put_param "Type" "${ParsingRecordTypes}"
	put_param "Value" "${RecordValue}"
	put_param "TTL" "${ttl_value}"
	if [[ "${ParsingRecordTypes}" = "MX" ]];then
		put_param "Priority" "${MxRecordPriority}"
	fi
	
	echo "请求发送中..."
	send_request modify.parsing.records.response.json
	
	ResponseFile='/root/alidns/modify.parsing.records.response.json'
	Message=$(jq .Message $ResponseFile | sed 's#"##g')
	if [[ "$Message" != "null" ]];then
		echo -e "${red} 修改失败,以下信息供参考: ${end}"
		echo "RequestId -> $(jq .RequestId $ResponseFile | sed 's#"##g')"
		echo "HostId    -> $(jq .HostId $ResponseFile | sed 's#"##g')"
		echo "Code      -> $(jq .Code $ResponseFile | sed 's#"##g')"
		echo "Message   -> $(jq .Message $ResponseFile | sed 's#"##g')"
		echo "Recommend -> $(jq .Recommend $ResponseFile | sed 's#"##g')"
	else
		echo -e "${green} 修改成功. ${end}"
	fi
}

modify_parsing_records()
{
	if [[ "${parameter2}" = "" ]];then
		echo -e "${red} 需要传入主机记录. ${end}"
		exit
	fi

	echo "加载解析信息中..."
	RecordId=$(bash "${BasePath}"/"${BaseName}" search RR ${parameter2} | sed -n 2p | awk '{print $7}')
	bash "${BasePath}"/"${BaseName}" edit $RecordId
}

search_parse_record_list()
{
	case "${parameter2}" in
		RR|Type|Value)
			;;
		*)
			echo -e "${red} 不是有效的搜索类别: {RR|Type|Value} ${end}"
			exit
	esac
	
	if [[ "${parameter3}" = "" ]];then
		echo -e "${red} 请传入搜索关键词. ${end}"
		exit
	fi
	
	put_params_public
	put_param "Action" "DescribeDomainRecords"
	put_param "DomainName" "${Domain}"
	put_param "PageNumber" "1"
	put_param "PageSize" "500"

	if [[ "${parameter2}" = "RR" ]];then
		put_param "RRKeyWord" "${parameter3}"
	elif [[ "${parameter2}" = "Type" ]];then
		put_param "TypeKeyWord" "${parameter3}"
	elif [[ "${parameter2}" = "Value" ]];then
		put_param "ValueKeyWord" "${parameter3}"
	fi

	send_request search.parse.record.list.response.json
	RecordsNumber=$(cat /root/alidns/search.parse.record.list.response.json | jq ".TotalCount")
	if [[ "${RecordsNumber}" = "0" ]];then
		echo -e "${red} 没有匹配的结果. ${end}"
		exit
	fi
	
	echo "ID | 主机记录 | 解析线路 | 记录状态 | 记录类型 | 记录值 | 记录ID | TTL" > /root/alidns/search.parse.record.list.response.txt
	for (( i=0; i < ${RecordsNumber}; i++ ))
	do
		get()
		{
			cat /root/alidns/search.parse.record.list.response.json | jq ".DomainRecords.Record[${i}].$1" | sed 's/"//g'
		}

		id=$(expr $i + 1)
		RR=$(get RR)
		Line=$(get Line)
		Status=$(get Status | tr A-Z a-z)
		#Locked=$(get Locked)
		Type=$(get Type)
		Value=$(get Value)
		RecordId=$(get RecordId)
		TTL=$(get TTL)

		if [[ "$Status" = "enable" ]];then
			StatusText="${green}${Status}${end}"
		else
			StatusText="${red}${Status}${end}"
		fi

		echo -e "$id | $RR | $Line | $StatusText | $Type | $Value | $RecordId | $TTL" >> /root/alidns/search.parse.record.list.response.txt
	done
	column -t -s '|' /root/alidns/search.parse.record.list.response.txt > /root/alidns/search.parse.record.list.txt

	if [[ "${parameter4}" = "edit" ]];then
		file_line=$(wc -l /root/alidns/search.parse.record.list.txt | awk '{print $1}')
		if [[ "${file_line}" -gt "2" ]];then
			cat /root/alidns/search.parse.record.list.txt
			echo
			read -p "多个匹配结果,请指定记录ID:" RecordId
			bash "${BasePath}"/"${BaseName}" edit "${RecordId}"
		fi
		RecordId=$(sed -n '2p' /root/alidns/search.parse.record.list.txt | awk '{print $7}')
		bash "${BasePath}"/"${BaseName}" edit "${RecordId}"
	else
		cat /root/alidns/search.parse.record.list.txt
	fi
}

get_analysis_record_information()
{
	put_params_public
	put_param "Action" "DescribeDomainRecordInfo"
	put_param "RecordId" "$parameter2"
	send_request get.analysis.record.information.response.json
}

get_server_ip()
{
	server_ip=$(curl -s --max-time 5 http://members.3322.org/dyndns/getip)
	if [[ "$?" != "0" ]];then
		server_ip=$(curl -s --max-time 5 http://ip.sb)
		if [[ "$?" != "0" ]];then
			echo -e "$(date "+%Y-%m-%d %H:%M:%S") [error] 获取服务器 ip 失败." | tee -a /root/alidns/ddns.domain.value.update.log
			exit
		fi
	fi
}

ddns_domain_value_update()
{
	if [[ "${DdnsRecordId}" = "" ]];then
		echo -e "${red} 请先配置 ddns 记录 id. ${end}"
		exit
	fi
	
	get_server_ip
	bash "${BasePath}"/"${BaseName}" getinfo "${DdnsRecordId}"
	ResponseFile='/root/alidns/get.analysis.record.information.response.json'
	record_rr=$(jq .RR ${ResponseFile} | sed 's#"##g')
	record_ip=$(jq .Value ${ResponseFile} | sed 's#"##g')
	
	if [[ "${server_ip}" != "${record_ip}" ]];then
		put_params_public
		put_param "Action" "UpdateDomainRecord"
		put_param "RecordId" "${DdnsRecordId}"
		put_param "Value" "${server_ip}"
		put_param "RR" "${record_rr}"
		put_param "TTL" "${DefaultTTL}"
		put_param "Type" "A"
		
		send_request ddns.domain.value.update.response.json
		ResponseFile='/root/alidns/ddns.domain.value.update.response.json'
		Message=$(jq .Message $ResponseFile | sed 's#"##g')
		if [[ "$Message" != "null" ]];then
			echo "$(date "+%Y-%m-%d %H:%M:%S") [error] ${Message}" | tee -a /root/alidns/ddns.domain.value.update.log
		else
			echo "$(date "+%Y-%m-%d %H:%M:%S") [info] ${record_rr} ${record_ip} -> ${server_ip}" | tee -a /root/alidns/ddns.domain.value.update.log
		fi
	else
		echo -e "${green} 此主机IP未变更,无需更新. ${end}"
	fi
}

view_ddns_log()
{
	cat -n /root/alidns/ddns.domain.value.update.log
}

view_edit_log()
{
	view_num='15'
	
	put_params_public
	put_param "Action" "DescribeRecordLogs"
	put_param "DomainName" "${Domain}"
	put_param "PageSize" "${view_num}"
	put_param "Lang" "zh"

	send_request operation.log.response.json
	#echo "ID | 时间 | 类型 | 内容" > /root/alidns/operation.log.response.txt
	for (( i=$(expr ${view_num} - 1); i >= 0 ; i-- ))
	do
		get()
		{
			cat /root/alidns/operation.log.response.json | jq ".RecordLogs.RecordLog[${i}].$1" | sed 's/"//g'
		}
		Action=$(get Action)
		ActionTime=$(get ActionTime | sed 's/T/ /g' | sed 's/Z//g')
		Message=$(get Message)

		echo "序号：$(expr ${i} + 1)"
		echo "类型：${Action}"
		echo "时间：${ActionTime}"
		echo "内容：${Message}"
		echo "--------------------------"
	done
}

setting_parameters()
{
	file_path="${BasePath}/${BaseName}"
	case "$parameter2" in
		AccessKeyId)
			sed -i "4c AccessKeyId=\'${parameter3}\'" $file_path
			echo "Set successfully : AccessKeyId -> ${parameter3}";;
		AccessKeySecret)
			sed -i "5c AccessKeySecret=\'${parameter3}\'" $file_path
			echo "Set successfully : AccessKeySecret -> ${parameter3}";;
		Domain)
			sed -i "7c Domain=\'${parameter3}\'" $file_path
			echo "Set successfully : Domain -> ${parameter3}";;
		DdnsRecordId)
			sed -i "11c DdnsRecordId=\'${parameter3}\'" $file_path
			echo "Set successfully : DdnsRecordId -> ${parameter3}";;
		DefaultTTL)
			sed -i "13c DefaultTTL=\'${parameter3}\'" $file_path
			echo "Set successfully : DefaultTTL -> ${parameter3}";;
	esac
}

help_information()
{
	echo -e "[命令] - [参数] - [操作]
account - 无 - 查看管理域名
add - 无 - 添加解析记录
ddns - 无 - 执行ddns更新
ddnslog - 无 - 查看ddns日志
del - 记录ID - 删除解析记录
disable - 记录ID - 停用解析记录
edit - 记录ID - 编辑解析记录
enable - 记录ID - 启用解析记录
list - 无 - 获取解析列表
log - 无 - 查看编辑日志
modify - 主机记录 - 快捷修改记录
search - {RR|Type|Value} {KeyWord} - 使用关键词 KeyWord 查询记录
set - {AccessKeyId|AccessKeySecret|Domain} - 设置必要参数
set - {DdnsRecordId|DefaultTTL} - 设置可选参数" | column -t -s '-'
}

clear
check
parameter1=$1
parameter2=$2
parameter3=$3
parameter4=$4

case "$parameter1" in
	add)
		add_parsing;;
	list)
		record_list;;
	enable|disable)
		set_recording_status;;
	del)
		delete_parse_record;;
	edit)
		edit_parsing_records;;
	modify)
		modify_parsing_records;;
	search)
		search_parse_record_list;;
	getinfo)
		get_analysis_record_information;;
	ddns)
		ddns_domain_value_update;;
	account)
		echo "${Domain}";;
	ddnslog)
		view_ddns_log;;
	log)
		view_edit_log;;
	set)
		setting_parameters;;
	help|*)
		help_information;;
esac

#END 2021-11-12
