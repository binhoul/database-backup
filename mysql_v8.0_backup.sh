#!/usr/bin/env bash
#author: binhoul
#date: 2021/07/14

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

readonly MAX_RETRIES=30
readonly SLEEP_BETWEEN_RETRIES_SEC=10

readonly DOCKER_IMAGE="nexus.scgsdsj.com/percona/percona-xtrabackup:8.0"

function print_usage {
  echo
  echo "Usage: ${SCRIPT_NAME} [OPTIONS]"
  echo
  echo "This script is used to backup mysql database. For MySQL above 8.0 only."
  echo
  echo "Options:"
  echo
  echo -e "  --machine\t\tThe machine type of running mysql. Required. should be on bare-metal host or in docker."
  echo -e "  --"
  echo -e "  --function\t\tThe function type of data operation. Required. Should be one of backup or restore."
  echo -e "  --backup_type\t\tThe type of data operation. Required. Should be auto or manual."
  echo -e "  --username\t\tThe username of mysql database. Required."
  echo -e "  --password\t\tThe password of mysql database. Required."
  echo -e "  --conf\t\tThe path of configuration file. Required."
  echo -e "  --backup_folder\tThe folder to store backup data. Required."
  echo -e "  --docker_used\t\tContainer name or id running mysql"
  echo
  echo "Example:"
  echo
  echo "  # Backup mysql database by crontab running on virtual machine"
  echo "  ./${SCRIPT_NAME} --machine host --function backup --backup_type auto --username root --password xxxx --conf /etc/my.cnf --backup_folder /data/backup"
  echo
  echo "  # Backup mysql database manually running on virtual machine"
  echo "  ./${SCRIPT_NAME} --machine host --function backup --backup_type manual --username root --password xxxx --conf /etc/my.cnf --backup_folder /data/backup"
  echo 
  echo "  # Backup mysql database by crontab running in docker"
  echo "  ./${SCRIPT_NAME} --machine docker --function backup --backup_type auto --username root --password xxxx --conf /etc/my.cnf --backup_folder /data/backup --docker_used docker-mysql"
  echo 
  echo "  # Backup mysql database manually running in docker"
  echo "  ./${SCRIPT_NAME} --machine docker --function backup --backup_type manual --username root --password xxxx --conf /etc/my.cnf --backup_folder /data/backup --docker_used docker-mysql"
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

function  host_backup_auto {

  cd ${env_backup_folder}

  today=$(get_x_days_ago 0)
  local readonly backup_base="mysql-backup-auto"

  seq_in_week=$(get_today_in_week)


  # 周日全备份
  if [[ "${seq_in_week}" -eq 0 ]]; 
  then
    local readonly today_full="${backup_base}-${today}-${seq_in_week}"
    log_info "[host]开始备份${today_full}"
    xtrabackup \
      --defaults-file="${env_conf}" \
      --backup \
      --user="${env_username}" \
      --password="${env_password}" \
      --target-dir="${today_full}"
    # 压缩
    tar cfz "${today_full}.tar.gz" "${today_full}"

  # 增量备份
  else
    local readonly today_increment="${backup_base}-${today}-${seq_in_week}"
    log_info "[host]开始备份${today_increment}"
    yesterday=$(get_x_days_ago 1)
    yesterday_seq_in_week=$(date +%w -d ${yesterday})
    dependency_folder="${backup_base}-${yesterday}-${yesterday_seq_in_week}"
    if [[ -d "${dependency_folder}" ]];
    then
      xtrabackup \
        --defaults-file="${env_conf}" \
        --backup \
        --user "${env_username}" \
        --password "${env_password}" \
        --target-dir="${today_increment}" \
        --incremental-basedir="${dependency_folder}"
      tar cfz "${today_increment}.tar.gz" "${today_increment}"
    else
      log_warn "[host]增量备份不存在依赖目录${dependency_folder}, 无法备份${today_increment}"
    fi
  fi
  log_info "[host]***备份完成***"
}

function host_backup_full_manual {
  cd ${env_backup_folder}

  today=$(get_x_days_ago 0)
  local readonly backup_base="mysql-backup-manual"
  local readonly today_full="${backup_base}-${today}-full"
  log_info "手动全量备份，开始备份${today_full}"
  xtrabackup \
    --defaults-file="${env_conf}" \
    --backup \
    --user="${env_username}" \
    --password="${env_password}" \
    --target-dir="${today_full}"
  # 压缩
  tar cfz "${today_full}.tar.gz" "${today_full}"
  log_info "[host]***备份完成***"
}

function docker_backup_full_manual {
  cd ${env_backup_folder}

  today=$(get_x_days_ago 0)
  local readonly backup_base="mysql-backup-manual"
  local readonly today_full="${backup_base}-${today}-full"
  log_info "[docker]手动全量备份，开始备份${today_full}"
  docker run \
    --name percona-backup \
    -v ${env_backup_folder}:${env_backup_folder} \
    --rm \
    --network host \
    -t \
    -e TZ=Asia/Shanghai \
    -w ${env_backup_folder} \
    --volumes-from ${env_volume_from} \
    --entrypoint=/usr/bin/xtrabackup \
    "${DOCKER_IMAGE}" \
    --defaults-file="${env_conf}" \
    --backup \
    --user="${env_username}" \
    --password="${env_password}" \
    --target-dir="${today_full}"
  
  # 压缩
  tar cfz "${today_full}.tar.gz" "${today_full}"
  log_info "[docker]***备份完成***"
}

function docker_backup_auto {

  cd ${env_backup_folder}

  today=$(get_x_days_ago 0)
  local readonly backup_base="mysql-backup-auto"

  seq_in_week=$(get_today_in_week)

  # 周日全备份
  if [[ "${seq_in_week}" -eq 0 ]]; 
  then
    local readonly today_full="${backup_base}-${today}-${seq_in_week}"
    log_info "[docker]开始备份${today_full}"
    docker run \
      --name percona-backup \
      -v ${env_backup_folder}:${env_backup_folder} \
      --rm \
      --network host \
      -t \
      -e TZ=Asia/Shanghai \
      -w ${env_backup_folder} \
      --volumes-from ${env_volume_from} \
      --entrypoint=/usr/bin/xtrabackup \
      "${DOCKER_IMAGE}" \
      --defaults-file="${env_conf}" \
      --backup \
      --user="${env_username}" \
      --password="${env_password}" \
      --target-dir="${today_full}"

    # 压缩
    tar cfz "${today_full}.tar.gz" "${today_full}"
  else
    local readonly today_increment="${backup_base}-${today}-${seq_in_week}"
    log_info "[docker]开始备份${today_increment}"
    yesterday=$(get_x_days_ago 1)
    yesterday_seq_in_week=$(date +%w -d ${yesterday})
    dependency_folder="${backup_base}-${yesterday}-${yesterday_seq_in_week}"
    if [[ -d "${dependency_folder}" ]];
    then
      docker run \
        --name percona-backup \
        -v ${env_backup_folder}:${env_backup_folder} \
        --rm \
        --network host \
        -t \
        -e TZ=Asia/Shanghai \
        -w ${env_backup_folder} \
        --volumes-from ${env_volume_from} \
        --entrypoint=/usr/bin/xtrabackup \
        "${DOCKER_IMAGE}" \
        --defaults-file="${env_conf}" \
        --backup \
        --user="${env_username}" \
        --password="${env_password}" \
        --target-dir="${today_increment}" \
        --incremental-basedir="${dependency_folder}"

      # 压缩
      tar cfz "${today_increment}.tar.gz" "${today_increment}"
    else
      log_warn "[docker]增量备份不存在依赖目录${dependency_folder}, 无法备份${today_increment}"
    fi
  fi
  log_info "[docker]***备份完成***"
}

function clean_7_days_folder {
  date_7_days_ago=$(get_x_days_ago 7)
  seq=$(date +%w -d "${date_7_days_ago}")
  local readonly backup_base="mysql-backup-auto"
  folder_7_days_ago="${backup_base}-${date_7_days_ago}-${seq}"
  
  cd ${env_backup_folder}
  test -d "${folder_7_days_ago}" && \
  log_info "删除7天前备份目录-${folder_7_days_ago}" && \
  rm -rf "${folder_7_days_ago}"
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
  declare -xr env_host="127.0.0.1"
  declare -xr env_port=3306


  while [[ $# > 0 ]]; do
    local key="$1"

    case "$key" in
      --machine)
        # host or docker，备份或恢复主机上的mysql or 容器内的数据
        assert_not_empty "$key" "$2"
        local readonly machine="$2"
        shift
        ;;
      --function)
        # backup or restore 备份或恢复
        # backup or restore
        assert_not_empty "$key" "$2"
        local readonly function="$2"
        shift
        ;;
      --backup_type)
        # 手动备份或者根据定时任务自动备份
        # auto or manual
        assert_not_empty "$key" "$2"
        local readonly backup_type="$2"
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
      --conf)
        # 配置文件路径
        assert_not_empty "$key" "$2"
        declare -xr env_conf="$2"
        shift
        ;;
      --backup_folder)
        # 备份路径
        assert_not_empty "$key" "$2"
        declare -xr env_backup_folder="$2"
        shift
        ;;
      --docker_used)
        # 运行mysql的容器名称或ID
        assert_not_empty "$key" "$2"
        declare -xr env_volume_from="$2"
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

  # 检查目录存在
  test -d "${env_backup_folder}" || mkdir -p "${env_backup_folder}"
  # 设定日志目录
  declare -rx env_log_abs_path="${env_backup_folder}/backup.log"
  # 检查命令是否安装
  if [[ "${machine}" == "docker" ]]; then
    assert_is_installed docker
  elif [[ "${machine}" == "host" ]]; then
    assert_is_installed xtrabackup
  fi

  
  # 主机上进行自动备份
  if [[ "$machine" == "host" && "$function" == "backup" && "${backup_type}" == "auto" ]]; then
    host_backup_auto
    clean_7_days_folder

  # 手动全量备份
  elif [[ "$machine" == "host" && "$function" == "backup" && "${backup_type}" == "manual" ]]; then
    host_backup_full_manual
  
  # 容器中进行自动备份
  elif [[ "$machine" == "docker" && "${function}" == "backup" && "${backup_type}" == "auto" ]]; then
    docker_backup_auto
    clean_7_days_folder
  
  # 手动全量备份容器中数据库
  elif [[ "$machine" == "docker" && "${function}" == "backup" && "${backup_type}" == "manual" ]]; then
    docker_backup_full_manual
  fi
}

main "$@"