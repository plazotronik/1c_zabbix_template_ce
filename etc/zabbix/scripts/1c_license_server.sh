#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (сервер лицензирования)
#
# (c) 2019-2020, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

source ${0%/*}/1c_common_module.sh 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

function licenses_summary {

    RING_TOOL=$(check_ring_license) || exit 1
    
    ( execute_tasks license_info $(get_license_list ${RING_TOOL}) ) | \
        awk 'BEGIN { files=0; users=0 } 
            { files+=1; users+=$1 } 
            END { print files":"users }'

}

function license_info {
    ${RING_TOOL} license info --send-statistics false --name ${1} | \
        grep -Pe '(Описание|Description).*на \d+ .*' | perl -pe 's/.*на (\d+) .*/\1/;'
}

function get_license_counts {
    CLSTR_LIST=${1##*:}
    for CURR_CLSTR in ${CLSTR_LIST//;/ }; do
        timeout -s HUP ${RAS_PARAMS[timeout]} rac session list --licenses --cluster=${CURR_CLSTR%,*} \
            ${RAS_PARAMS[auth]} ${1%%:*}:${RAS_PARAMS[port]} 2>/dev/null | \
            grep -Pe "(user-name|rmngr-address|app-id)" | \
            perl -pe 's/ //g; s/\n/|/; s/rmngr-address:(\"(.*)\"|)\||/\2/; s/app-id://; s/user-name:/\n/;' | \
            awk -F"|" -v hostname=${HOSTNAME,,} -v cluster=${CURR_CLSTR#*,} 'BEGIN { sc=0; hc=0; cc=0; wc=0 } \
                { if ($1 != "") { sc+=1; uc[$1]; if ( index(tolower($3), hostname) > 0 ) { hc+=1 } \
                if ($2 == "WebClient") { wc+=1 } if ($3 == "") { cc+=1 } } } \
                END {print cluster":"hc":"length(uc)":"sc":"cc":"wc }'
    done
}

function used_license {

    ( execute_tasks get_license_counts $( pop_clusters_list ) ) | \
        awk -F: 'BEGIN {ul=0; as=0; cl=0; uu=0; wc=0} \
            { print $0; ul+=$2; uu+=$3; as+=$4; cl+=$5; wc+=$6; } \
            END { print "summary:"ul":"uu":"as":"cl":"wc }'

}

function get_clusters_list {

    [[ ! -f ${CLSTR_CACHE} ]] && error "Не найден файл списка кластеров!"

    cut -f2 -d: ${CLSTR_CACHE} | perl -pe 's/;[^\n]/\n/; s/;//' | \
        awk 'BEGIN {FS=","; print "{\"data\":[" } \
            {print "{\"{#CLSTR_UUID}\":\""$1"\",\"{#CLSTR_NAME}\":\""$2"\"}," } \
            END { print "]}" }' | \
        perl -pe 's/\n//;' | perl -pe 's/(.*),]}/\1]}\n/'

}

case ${1} in
    info) licenses_summary ;;
    used) shift; make_ras_params ${@}; used_license ;;
    clusters) get_clusters_list ;;
    *) error "${ERROR_UNKNOWN_MODE}" ;;
esac