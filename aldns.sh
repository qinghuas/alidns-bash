#!/bin/bash

# AccessKey
AccessKeyId=''
AccessKeySecret=''
# 管理域名
ManagementDomain=''
# API地址
ALiServerAddr='https://alidns.aliyuncs.com'
# DDNS设置
ddns_record_id=''
ddns_record_value=''
# 其他设置
default_ttl='600'
# 致谢 https://xvcat.com/post/1096
BasePath=$(cd $(dirname ${BASH_SOURCE}) ; pwd)
BaseName=$(basename $BASH_SOURCE)
	
check()
{
	if [[ "${AccessKeyId}" = "" ]];then
		echo "缺少AccessKeyId."
		exit
	fi
	if [[ "${AccessKeySecret}" = "" ]];then
		echo "缺少AccessKeySecret."
		exit
	fi
	if [[ ! -f "/usr/bin/jq" ]];then
		echo "缺少 jq 命令."
		exit
	fi
	if [[ ! -f "/usr/bin/column" ]];then
		echo "缺少 column 命令."
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
		echo "主机记录不能为空.";exit
	else
		echo -e "\033[32m 主机记录:$HostRecord \033[0m"
	fi
	#记录值
	read -p "记录值:" RecordValue
	if [[ "${RecordValue}" = "" ]];then
		echo "记录值不能为空.";exit
	else
		echo -e "\033[32m 记录值:$RecordValue \033[0m"
	fi
	#解析记录类型
	read -p "解析记录类型(A/NS/MX/TXT/CNAME/SRV/AAAA/CAA/REDIRECT_URL/FORWARD_URL):" ParsingRecordTypes
	if [[ "${ParsingRecordTypes}" = "" ]];then
		echo -e "\033[32m 解析记录类型:A \033[0m"
		ParsingRecordTypes='A'
	else
		echo -e "\033[32m 解析记录类型:$ParsingRecordTypes \033[0m"
	fi
	#如若是MX记录,询问MX记录优先级
	if [[ "${ParsingRecordTypes}" = "MX" ]];then
		read -p "MX记录优先级:" MxRecordPriority
		if [[ "${MxRecordPriority}" = "" ]];then
			echo "MX记录优先级不能为空.";exit
		else
			echo -e "\033[32m MX记录优先级:$MxRecordPriority \033[0m"
		fi
	fi
	#TTL值
	read -p "TTL值(单位:s):" ttl_value
	if [[ "${ttl_value}" = "" ]];then
		ttl_value="${default_ttl}"
	fi
	echo -e "\033[32m TTL值:${ttl_value} \033[0m"
	
	put_params_public
	put_param "Action" "AddDomainRecord"
	put_param "DomainName" "${ManagementDomain}"
	put_param "RR" "${HostRecord}"
	put_param "Type" "${ParsingRecordTypes}"
	put_param "Value" "${RecordValue}"
	put_param "TTL" "${ttl_value}"
	if [[ "${ParsingRecordTypes}" = "MX" ]];then
		put_param "Priority" "${MxRecordPriority}"
	fi
	
	send_request add.parsing.response.json
	echo "请求已发送.欲查看执行结果,请执行 aldns list 命令,查看或登入控制台查看."
}

record_list()
{
	put_params_public
	put_param "Action" "DescribeDomainRecords"
	put_param "DomainName" "${ManagementDomain}"
	put_param "PageNumber" "1"
	put_param "PageSize" "500"
	
	send_request record.list.response.json
	RecordsNumber=$(cat /root/alidns/record.list.response.json | jq ".TotalCount")
	echo "ID | 主机记录 | 解析线路 | 记录状态 | 记录类型 | 记录值 | 记录ID | TTL" > /root/alidns/record.list.response.txt
	for (( i=0; i < ${RecordsNumber}; i++ ))
	do
		get()
		{
			cat /root/alidns/record.list.response.json | jq ".DomainRecords.Record[${i}].$1" | sed 's/"//g'
		}
		id=$(expr $i + 1)
		RR=$(get RR)
		Line=$(get Line)
		if [[ "$(get Status)" = "ENABLE" ]];then
			Status="\033[32m enable \033[0m"
		else
			Status="\033[31m disable \033[0m"
		fi
		#Locked=$(get Locked)
		Type=$(get Type)
		Value=$(get Value)
		RecordId=$(get RecordId)
		TTL=$(get TTL)
		echo -e "$id | $RR | $Line | $Status | $Type | $Value | $RecordId | $TTL" >> /root/alidns/record.list.response.txt
	done
	column -t -s '|' /root/alidns/record.list.response.txt > /root/alidns/record.list.txt
	cat /root/alidns/record.list.txt
}

set_recording_status()
{
	if [[ "${parameter2}" = "" ]];then
		echo "No required parameters are passed in: RecordId"
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

	send_request set.recording.status.response.json
	echo "请求已发送.欲查看执行结果,请执行 aldns list 命令,查看或登入控制台查看."
}

delete_parse_record()
{
	if [[ "${parameter2}" = "" ]];then
		echo "No required parameters are passed in: RecordId"
		exit
	fi
	
	put_params_public
	put_param "Action" "DeleteDomainRecord"
	put_param "RecordId" "${parameter2}"
	send_request delete.parse.record.response.json
	echo "请求已发送.欲查看执行结果,请执行 aldns list 命令,查看或登入控制台查看."
}

modify_parsing_records()
{
	if [[ "${parameter2}" = "" ]];then
		echo "No required parameters are passed in: RecordId"
		exit
	fi
	
	bash "${BasePath}"/"${BaseName}" getinfo "${parameter2}"
	before_record_rr=$(cat /root/alidns/value | awk -F ':' '{print $1}')
	before_record_ip=$(cat /root/alidns/value | awk -F ':' '{print $2}')
	
	put_params_public
	put_param "Action" "UpdateDomainRecord"
	
	#主机记录
	read -p "新主机记录:" HostRecord
	if [[ "${HostRecord}" = "" ]];then
		HostRecord="${before_record_rr}"
		echo -e "\033[32m 主机记录(未变更):${HostRecord} \033[0m"
	else
		echo -e "\033[32m 主机记录:${HostRecord} \033[0m"
	fi
	#记录值
	read -p "新记录值:" RecordValue
	if [[ "${RecordValue}" = "" ]];then
		RecordValue="${before_record_ip}"
		echo -e "\033[32m 记录值(未变更):${RecordValue} \033[0m"
	else
		echo -e "\033[32m 记录值:${RecordValue} \033[0m"
	fi
	#解析记录类型
	read -p "新解析记录类型(A/NS/MX/TXT/CNAME/SRV/AAAA/CAA/REDIRECT_URL/FORWARD_URL):" ParsingRecordTypes
	if [[ "${ParsingRecordTypes}" = "" ]];then
		echo -e "\033[32m 解析记录类型:A \033[0m"
		ParsingRecordTypes='A'
	else
		echo -e "\033[32m 解析记录类型:$ParsingRecordTypes \033[0m"
	fi
	#如若是MX记录,询问MX记录优先级
	if [[ "${ParsingRecordTypes}" = "MX" ]];then
		read -p "新MX记录优先级:" MxRecordPriority
		if [[ "${MxRecordPriority}" = "" ]];then
			echo "MX记录优先级不能为空.";exit
		else
			echo -e "\033[32m MX记录优先级:$MxRecordPriority \033[0m"
		fi
	fi
	#TTL值
	read -p "TTL值(单位:s):" ttl_value
	if [[ "${ttl_value}" = "" ]];then
		ttl_value="${default_ttl}"
	fi
	echo -e "\033[32m TTL值:${ttl_value} \033[0m"
	
	put_param "RecordId" "${parameter2}"
	put_param "RR" "${HostRecord}"
	put_param "Type" "${ParsingRecordTypes}"
	put_param "Value" "${RecordValue}"
	put_param "TTL" "${ttl_value}"
	if [[ "${ParsingRecordTypes}" = "MX" ]];then
		put_param "Priority" "${MxRecordPriority}"
	fi
	
	send_request modify.parsing.records.response.json
	echo "请求已发送.欲查看执行结果,请执行 aldns list 命令,查看或登入控制台查看."
}

search_parse_record_list()
{
	case "${parameter2}" in
		RR|Type|Value)
			;;
		*)
			echo "No required parameters are passed in: {RR|Type|Value}"
			exit
	esac
	
	if [[ "${parameter3}" = "" ]];then
		echo "No required parameters are passed in: ValueKeyWord"
		exit
	fi
	
	put_params_public
	put_param "Action" "DescribeDomainRecords"
	put_param "DomainName" "${ManagementDomain}"
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
		echo "No matching records were found."
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
			StatusText="\033[32m${Status}\033[0m"
		else
			StatusText="\033[31m${Status}\033[0m"
		fi
		echo -e "$id | $RR | $Line | $StatusText | $Type | $Value | $RecordId | $TTL" >> /root/alidns/search.parse.record.list.response.txt
	done
	column -t -s '|' /root/alidns/search.parse.record.list.response.txt > /root/alidns/search.parse.record.list.txt
	
	if [[ "${parameter4}" = "edit" ]];then
		file_line=$(wc -l /root/alidns/search.parse.record.list.txt | awk '{print $1}')
		if [[ "${file_line}" -gt "2" ]];then
			echo "Multiple results are matched and cannot be modified directly."
			exit
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
	
	get()
	{
		cat /root/alidns/get.analysis.record.information.response.json | jq ".$1" | sed 's/"//g'
	}
	
	record_RR=$(get RR)
	record_Value=$(get Value)
	
	echo "${record_RR}:${record_Value}" > /root/alidns/value
}

ddns_domain_value_update()
{
	if [[ "${ddns_record_id}" = "" ]] || [[ "${ddns_record_value}" = "" ]];then
		echo "You need to set the record id and host record value of the dns record."
		exit
	fi
	
	server_ip=$(curl -s http://members.3322.org/dyndns/getip)
	bash "${BasePath}"/"${BaseName}" getinfo "${parameter2}"
	record_rr=$(cat /root/alidns/value | awk -F ':' '{print $1}')
	record_ip=$(cat /root/alidns/value | awk -F ':' '{print $2}')
	
	if [[ "${server_ip}" != "${record_ip}" ]]&& [[ "${server_ip}" != "" ]] && [[ "${record_ip}" != "" ]] ;then
		put_params_public
		put_param "Action" "UpdateDomainRecord"
		put_param "RecordId" "${ddns_record_id}"
		put_param "Value" "${server_ip}"
		put_param "RR" "${ddns_record_value}"
		put_param "TTL" "${default_ttl}"
		put_param "Type" "A"
		
		send_request ddns.domain.value.update.response.json
		echo "$(date "+%Y-%m-%d %H:%M:%S") [info] ${ddns_record_value} ${record_ip} -> ${server_ip}" | tee -a /root/alidns/ddns.domain.value.update.log
	else
		echo "Since the ip and domain name record values are the same, no update is performed."
	fi
}

view_ddns_log()
{
	cat -n /root/alidns/ddns.domain.value.update.log
}

help_information()
{
	echo "add - 添加解析记录
list - 获取解析列表
del {record id} 删除解析记录
edit {record id} 编辑解析记录
enable {record id} - 启用解析记录
disable {record id} - 停用解析记录
search {RR|Type|Value} {KeyWord} - 使用关键词 KeyWord 查询记录

ddns 执行检测与更新
log 查阅 ddns 更新日志

更多使用指南请参见：https://github.com/qinghuas/alidns-bash"
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
		modify_parsing_records;;
	search)
		search_parse_record_list;;
	getinfo)
		get_analysis_record_information;;
	ddns)
		ddns_domain_value_update;;
	account)
		echo "${ManagementDomain}";;
	log)
		view_ddns_log;;
	help|*)
		help_information;;
esac

#END 2020-11-02
