
## oracle备份脚本使用说明

### 实现功能

1. 针对特定用户或schema进行备份
2. 针对多个用户或多个schemas进行备份
3. 备份后文件压缩
4. 7天前备份文件自动删除

### 运行条件

1. 创建一个备份目录
2. 将备份脚本放入备份目录中
3. 需要在数据库中创建EXPDP_BK_DIR且指向当前备份目录，例如：
   ```
   假定将备份数据存放于/backup目录下，具体目录根据实际情况进行修改即可。
   create or replace directory EXPDP_BK_DIR as /backup
   ```
### 备份单个用户

方法一：

1.切换到脚本目录
2.执行备份命令`./oracle_backup.sh --username user --password password`

方法二：

在当前目录，创建password.txt，将用户名和密码写入文件，以:分割，例如：
```
echo 'user:password' > password.txt
./oracle_backup.sh --keyfile password.txt
```

### 备份多个用户

将多个用户的用户名和密码写入password.txt，每个用户一行，用户名密码以:分割，例如：
```
echo > password.txt <<EOF
user1:password1
user2:password2
user3:password3
EOF
./oracle_backup.sh --keyfile password.txt
```

### 添加定时任务

```
crontab -l
0 3 * * * cd /backup && ./oracle_backup.sh --keyfile password.txt
```
注意：为了方便处理，所有目录均处于备份目录中，执行时需要先切换到备份目录，不允许使用如下方式备份：
/backup/oracle_backup.sh --keyfile password.txt


## MySQL 数据库备份和恢复脚本

### 安装xtrabackup

注：xtrabackup 2.4针对5.7及之前版本，xtrabackup 8.0针对mysql 8.0版本。

1. yum install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
2. percona-release enable-only tools release
3. yum install percona-xtrabackup-24

[Installing Percona XtraBackup on Red Hat Enterprise Linux and CentOS](https://www.percona.com/doc/percona-xtrabackup/2.4/installation/yum_repo.html)

### 创建备份用户

```shell
#创建备份用户
CREATE USER 'bkpuser'@'%' IDENTIFIED BY 'glxxxxbk@2020'; # bkpuser替换为自己的备份用户

#授权刷新、锁定表、用户查看服务器状态
GRANT SELECT,BACKUP_ADMIN,RELOAD,LOCK TABLES,REPLICATION CLIENT,PROCESS,SUPER ON *.* TO 'bkpuser'@'%'; 

FLUSH PRIVILEGES;

#创建备份目录/data/backup
mkdir -p /data/backup # 备份目录根据需求自己指定
```

### 备份
### v5.7备份

提供了四种备份方式：
 
- 主机内的全量备份
- 主机内的增量备份
- 容器内的全量备份
- 容器内的增量备份

```bash
# 容器内增量备份 
/data/backup/mysql_v5.7_backup.sh --machine docker --function backup --backup_type auto --username root --password xxxx --conf /etc/mysql/mysql.conf.d/my.user.cnf --backup_folder /data/backup --docker_used confluence-mysql >> /data/backup/backup.log 2>&1

# 容器内全量备份
/data/backup/mysql_v5.7_backup.sh --machine docker --function backup --backup_type manual --username root --password xxxx --conf /etc/mysql/mysql.conf.d/my.user.cnf --backup_folder /data/backup --docker_used confluence-mysql

# 主机上全量备份
/data/backup/mysql_v5.7_backup.sh --machine host --function backup --backup_type manual --username root --password xxxx --conf /etc/mysql/mysql.conf.d/my.user.cnf --backup_folder /data/backup >> /data/backup/backup.log 2>&1


# 主机上增量备份
/data/backup/mysql_v5.7_backup.sh --machine host --function backup --backup_type auto --username root --password xxxx --conf /etc/mysql/mysql.conf.d/my.user.cnf --backup_folder /data/backup >> /data/backup/backup.log 2>&1
```
