#!/usr/bin/env bash
#author: binhoul
#date: 2022/06/21

set -euo pipefail

export ORACLE_HOME=/u01/app/oracle/product/11.2.0/db_1
export ORACLE_SID=orcl
export NLS_LANG='SIMPLIFIED CHINESE_CHINA.ZHS16GBK'

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

function print_usage {
  echo
  echo "Usage: ${SCRIPT_NAME} [OPTIONS]"
  echo
  echo "This script is used to backup oracle database."
  echo
  echo "Options:"
  echo
  echo -e "  --keyfile\t\tThe file path which store oracle username and password."
  echo -e "  --username\t\tThe username of mysql database. Required."
  echo -e "  --password\t\tThe password of mysql database. Required."
  echo
  echo "Example:"
  echo
  echo "  # Backup oracle ts user"
  echo "  ./${SCRIPT_NAME} --username ts --password tspassword"
}

function log {
  local readonly level="$1"
  local readonly message="$2"
  local readonly timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "${timestamp} [${level}] [$SCRIPT_NAME] ${message}"
}

function log_info {
  local readonly message="$1"
  log "INFO" "${message}"
}

function log_warn {
  local readonly message="$1"
  log "WARN" "${message}"
}

function log_error {
  local readonly message="$1"
  log "ERROR" "${message}"
}

function assert_not_empty {
  local readonly arg_name="$1"
  local readonly arg_value="$2"

  if [[ -z "${arg_value}" ]]; then
    log_error "The value for '${arg_name}' cannot be empty"
    print_usage
    exit 1
  fi
}

function assert_is_installed {
  local readonly name="$1"

  if [[ ! $(command -v ${name}) ]]; then
    log_error "The binary '${name}' is required by this script but is not installed or in the system's PATH."
    exit 1
  fi
}

function assert_file_exist {
    local readonly filename="$1"

    if [[ ! -f ${filename} ]]; then
        log_error "The file '${filename}' is used by this script but does not exist."
        exit 1
    fi
}

function get_user_list {
    local readonly keyfile="$1"
    assert_file_exist $keyfile
    user_list=$(cat ${keyfile})
    echo $user_list
}

function backup_one_user_of_schema {
    local readonly oracle_user="$1"
    local readonly oracle_password="$2"
    filename_this="ora-bak-${oracle_user}-$(date +%y%m%d)"
    log_info "Start backup oracle data for user ${oracle_user}"
    ${ORACLE_HOME}/bin/expdp ${oracle_user}/\"${oracle_password}\" \
        PARALLEL=4  \
        cluster=no \
        COMPRESSION=ALL \
        DUMPFILE="${filename_this}.dmp" \
        DIRECTORY=EXPDP_BK_DIR \
        logfile="${filename_this}.log" \
        SCHEMAS="${oracle_user}"
    log_info "Backup oracle data for user ${oracle_user} finished"
}

function create_tar_file {
    log_info "Start creating tar file for files: $(ls ora-bak*{.log,.dmp})"
    tar cvfz ora-bak-$(date +%y%m%d).tar.gz ora-bak-*{.log,.dmp}
    rm -f ora-bak-*{.log,.dmp}
    log_info "Tar file created"
}

function clean_7_days_files {
  date_7_days_ago=$(get_x_days_ago 7)
  seq=$(date +%w -d "${date_7_days_ago}")
  file_7_days_ago="ora-bak-${date_7_days_ago}.tar.gz"
  
  test -f "${folder_7_days_ago}" && \
  log_info "删除7天前备份-${file_7_days_ago}" && \
  rm -rf "${file_7_days_ago}"
}

function get_x_days_ago {
  datestr="$1"
  todate=$(date -d "${datestr} days ago" +%Y%m%d)
  echo -n $todate
}

function get_today_in_week {
  seq=$(date +%w)
  echo -n "${seq}"
}

function main {

  while [[ $# > 0 ]]; do
    local key="$1"

    case "$key" in
      --keyfile)
        # 指定存放oracle用户名和密码的文件
        assert_not_empty "$key" "$2"
        declare -xr env_keyfile="$2"
        shift
        ;;
      --username)
        # 用户名
        assert_not_empty "$key" "$2"
        declare -xr env_username="$2"
        shift
        ;;
      --password)
        # 密码
        assert_not_empty "$key" "$2"
        declare -xr env_password="$2"
        shift
        ;;
      *)
        log_error "Unrecognized argument: $key"
        print_usage
        exit 1
        ;;
    esac

    shift
  done

  logfile=alllog-ora-bak-$(date +%y%m%d).log

  if [[ -z "${env_keyfile:-}" ]]
  then
    backup_one_user_of_schema "${env_username}" "${env_password}" >> "${logfile}" 2>&1

  elif [[ -z "${env_username:-}" ]]
  then
    user_list=$(get_user_list $env_keyfile)
    for user in "${user_list}"
    do
      username=$(echo $user | cut -d ":" -f1)
      password=$(echo $user | cut -d ":" -f2)
      backup_one_user_of_schema "${username}" "${password}" >> "${logfile}" 2>&1
    done
  fi

  create_tar_file >> "${logfile}" 2>&1
  clean_7_days_files >> "${logfile}" 2>&1

}

main "$@"
