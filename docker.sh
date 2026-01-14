#!/bin/bash

# =========================================================
# Docker Compose Manager Script v1.7.4
# Author: Shinyuz | Fix: Remove 7-Day Auto Delete
# =========================================================

# --- 颜色定义 ---
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
PLAIN='\033[0m'

# --- 基础变量 ---
PROJECT_CONF_FILE="/etc/dcm_projects.txt"
BACKUP_DIR="/opt/docker-manager/backup"
AUTO_BACKUP_SCRIPT="/usr/local/backup/docker-auto-backup.sh"
CRON_FILE="/etc/cron.d/docker-auto-backup"
SCRIPT_VERSION="v1.7.4"

# --- 检查 Root 权限 ---
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN} 必须使用 root 用户运行此脚本！\n" && exit 1

# --- 工具函数：按任意键返回 ---
any_key_back() {
    echo ""
    read -n 1 -s -r -p "按任意键返回..."
    echo "" 
}

# --- 工具函数：设置快捷键 (dk) ---
set_shortcut() {
    local current_path
    current_path=$(readlink -f "$0")

    if [[ ! -f /usr/bin/dk ]] || [[ "$(readlink -f /usr/bin/dk)" != "$current_path" ]]; then
        ln -sf "$current_path" /usr/bin/dk
        chmod +x "$current_path"
        rm -f /usr/bin/dcm
    fi
}

# --- 核心工具：检测 Docker 状态 ---
get_status() {
    if systemctl is-active docker &> /dev/null; then
        STATUS="${GREEN}running${PLAIN}"
    else
        STATUS="${RED}stopped${PLAIN}"
    fi
    
    if type -P docker &> /dev/null; then
        VER=$(docker --version 2>/dev/null | awk '{print $3}' | sed 's/,//')
    else
        VER="${RED}未安装${PLAIN}"
        STATUS="${RED}未安装${PLAIN}"
    fi
}

# --- 工具函数：扫描已存在的项目 ---
scan_existing_projects() {
    if ! systemctl is-active docker &> /dev/null; then
        return
    fi

    local found_count=0
    mapfile -t detected_paths < <(docker ps --format '{{.Label "com.docker.compose.project.working_dir"}}' | grep -v "^$" | sort -u)

    if [[ ${#detected_paths[@]} -gt 0 ]]; then
        echo -e "${YELLOW}检测到您已安装 Docker，正在扫描运行中的项目...${PLAIN}"
        echo ""
        
        for path in "${detected_paths[@]}"; do
            local name=$(basename "$path")
            if ! grep -q "|${path}$" "$PROJECT_CONF_FILE"; then
                echo "${name}|${path}" >> "$PROJECT_CONF_FILE"
                echo -e "${GREEN}[自动导入]项目:${name}${PLAIN}"
                echo ""
                ((found_count++))
            fi
        done
    fi

    if [[ $found_count -gt 0 ]]; then
        echo -e "${GREEN}成功导入了 ${found_count} 个已存在的项目${PLAIN}"
    fi
}

# --- 初始化环境 (仅启动时运行一次) ---
init_environment() {
    # 1. 检查并安装 Nano
    if ! command -v nano &> /dev/null; then
        echo -e "${YELLOW}正在安装 Nano 编辑器...${PLAIN}"
        echo ""
        if [[ -f /etc/debian_version ]]; then
            apt-get update -y >/dev/null 2>&1 && apt-get install -y nano >/dev/null 2>&1
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y nano >/dev/null 2>&1
        fi
    fi

    # 2. 智能检测 Docker 安装
    if type -P docker &> /dev/null; then
        
        if ! docker compose version &> /dev/null; then
             echo -e "${YELLOW}检测到 Docker 已安装，但缺少 Compose 插件，正在补全...${PLAIN}"
             echo ""
             if [[ -f /etc/debian_version ]]; then
                apt-get update -y >/dev/null 2>&1 && apt-get install -y docker-compose-plugin >/dev/null 2>&1
             fi
        fi

        if [[ ! -s "$PROJECT_CONF_FILE" ]]; then
            mkdir -p "$BACKUP_DIR"
            touch "$PROJECT_CONF_FILE"
            scan_existing_projects
        fi
        
    else
        echo -e "${BLUE}检测到未安装 Docker，准备安装...${PLAIN}"
        echo ""
        if ! command -v wget &> /dev/null; then
            if [[ -f /etc/debian_version ]]; then
                apt-get update -y >/dev/null 2>&1 && apt-get install -y wget >/dev/null 2>&1
            elif [[ -f /etc/redhat-release ]]; then
                yum install -y wget >/dev/null 2>&1
            fi
        fi
        
        echo -e "${YELLOW}正在使用官方脚本安装 Docker...${PLAIN}"
        echo ""
        
        if curl -fsSL https://get.docker.com | bash; then
            echo -e "${GREEN}Docker 安装成功！${PLAIN}"
            systemctl enable docker &> /dev/null
        else
            echo -e "${RED}Docker 安装失败，请检查网络连接。${PLAIN}\n"
            exit 1
        fi
        echo ""
        
        systemctl start docker &> /dev/null
        
        if ! command -v docker-compose &> /dev/null; then
            if ! docker compose version &> /dev/null; then
                 if [[ -f /etc/debian_version ]]; then
                    apt-get install -y docker-compose-plugin >/dev/null 2>&1
                 fi
            fi
        fi
        
        mkdir -p "$BACKUP_DIR"
        touch "$PROJECT_CONF_FILE"
        echo -e "${GREEN}环境初始化完成！${PLAIN}"
    fi

    set_shortcut
}

# --- 功能：添加项目 ---
add_project() {
    echo -e "\n========= 添加项目 =========\n"
    
    read -p "请输入项目别名: " p_name
    echo ""
    
    read -p "请输入 docker-compose.yml 所在绝对路径: " p_path
    echo ""

    if [[ -z "$p_name" || -z "$p_path" ]]; then
        echo -e "${RED}名称或路径不能为空。${PLAIN}"
        any_key_back
        return
    fi

    if [[ ! -d "$p_path" ]]; then
        echo -e "${RED}目录不存在: ${p_path}${PLAIN}"
        any_key_back
        return
    fi

    if [[ ! -f "$p_path/docker-compose.yml" && ! -f "$p_path/docker-compose.yaml" ]]; then
        echo -e "${RED}该目录下未找到 docker-compose.yml 文件！${PLAIN}"
        any_key_back
        return
    fi

    if grep -q "^${p_name}|" "$PROJECT_CONF_FILE"; then
        echo -e "${RED}项目名称已存在。${PLAIN}"
    else
        echo "${p_name}|${p_path}" >> "$PROJECT_CONF_FILE"
        echo -e "${GREEN}项目 [${p_name}] 添加成功！${PLAIN}"
        echo ""
        
        echo -e "${BLUE}正在检查容器状态...${PLAIN}"
        echo ""
        
        if cd "$p_path"; then
            if docker compose ps --services --filter "status=running" | grep -q .; then
                echo -e "${GREEN}检测到容器已在运行，无需再次启动。${PLAIN}"
            else
                echo -e "${BLUE}容器未运行，正在自动启动...${PLAIN}"
                echo ""
                if docker compose up -d; then
                    echo ""
                    echo -e "${GREEN}容器启动成功！${PLAIN}"
                else
                    echo ""
                    echo -e "${RED}容器启动失败，请稍后在管理菜单中检查日志。${PLAIN}"
                fi
            fi
        else
            echo -e "${RED}进入目录失败，无法检查状态。${PLAIN}"
        fi
    fi
    any_key_back
}

# --- 功能：管理项目 ---
manage_project() {
    echo ""
    while true; do
        if [[ ! -s "$PROJECT_CONF_FILE" ]]; then
            echo -e "${RED}项目列表为空，请先添加项目。${PLAIN}"
            any_key_back
            return
        fi

        echo -e "========= 管理项目 =========\n"

        mapfile -t lines < "$PROJECT_CONF_FILE"
        local i=1
        for line in "${lines[@]}"; do
            name=$(echo "$line" | cut -d'|' -f1)
            path=$(echo "$line" | cut -d'|' -f2)
            echo -e " ${i}. ${name} (${YELLOW}${path}${PLAIN})"
            echo ""
            ((i++))
        done
        echo -e " 0. 返回"
        echo ""

        read -p "请选择项目 [0-${#lines[@]}]: " p_idx
        if [[ "$p_idx" == "0" ]]; then
            return
        fi

        if ! [[ "$p_idx" =~ ^[0-9]+$ ]] || [[ "$p_idx" -lt 1 ]] || [[ "$p_idx" -gt ${#lines[@]} ]]; then
            echo ""
            echo -e "${RED}无效的选择。${PLAIN}"
            any_key_back
            continue
        fi

        selected_line="${lines[$((p_idx-1))]}"
        p_name=$(echo "$selected_line" | cut -d'|' -f1)
        p_path=$(echo "$selected_line" | cut -d'|' -f2)

        while true; do
            echo ""
            
            # 获取项目状态
            if cd "$p_path" 2>/dev/null; then
                if docker compose ps --services --filter "status=running" 2>/dev/null | grep -q .; then
                    P_STATUS="${GREEN}running${PLAIN}"
                else
                    P_STATUS="${RED}stopped${PLAIN}"
                fi
            else
                P_STATUS="${RED}path_error${PLAIN}"
            fi

            echo -e "=== 操作项目:[${GREEN}${p_name}${PLAIN}] ==="
            echo ""
            echo -e " 状态: ${P_STATUS}"
            echo ""
            echo -e "========================\n"

            echo -e " 1. 启动容器"
            echo ""
            echo -e " 2. 停止容器"
            echo ""
            echo -e " 3. 重启容器"
            echo ""
            echo -e " 4. 更新容器"
            echo ""
            echo -e " 5. 删除容器"
            echo ""
            echo -e " 6. 编辑名称"
            echo ""
            echo -e " 7. 编辑配置"
            echo ""
            echo -e " 8. 查看日志"
            echo ""
            echo -e " 0. 返回上一级"
            echo ""

            read -p "请选择操作 [0-8]: " op_choice
            echo ""

            cd "$p_path" || { echo -e "${RED}进入目录失败${PLAIN}"; any_key_back; break; }

            case "$op_choice" in
                1)
                    echo -e "${BLUE}正在启动...${PLAIN}"
                    echo ""
                    docker compose up -d
                    echo ""
                    echo -e "${GREEN}执行完成。${PLAIN}"
                    any_key_back
                    ;;
                2)
                    echo -e "${BLUE}正在停止容器...${PLAIN}"
                    echo ""
                    docker compose down
                    echo ""
                    echo -e "${GREEN}已停止。${PLAIN}"
                    any_key_back
                    ;;
                3)
                    echo -e "${BLUE}正在重启...${PLAIN}"
                    echo ""
                    docker compose restart
                    echo ""
                    echo -e "${GREEN}已重启。${PLAIN}"
                    any_key_back
                    ;;
                4)
                    echo -e "${BLUE}正在尝试下载最新镜像...${PLAIN}"
                    echo ""
                    if docker compose pull; then
                         echo ""
                         echo -e "${GREEN}下载成功，正在应用更新...${PLAIN}"
                         echo ""
                         docker compose up -d
                         echo ""
                         echo -e "${GREEN}更新完成。${PLAIN}"
                    else
                         echo ""
                         echo -e "${RED}镜像下载失败 (本地镜像或私有仓库无需更新，请使用'启动容器')${PLAIN}"
                         echo ""
                         echo -e "${YELLOW}已终止更新操作${PLAIN}"
                    fi
                    any_key_back
                    ;;
                5)
                    read -p "确认删除此容器? (y/n): " confirm
                    echo ""
                    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                        echo -e "${BLUE}正在停止容器并清理数据卷...${PLAIN}"
                        echo ""
                        docker compose down --volumes
                        echo ""
                        echo -e "${BLUE}正在删除项目文件...${PLAIN}"
                        echo ""
                        
                        cd ..
                        rm -rf "$p_path"
                        
                        sed -i "${p_idx}d" "$PROJECT_CONF_FILE"
                        
                        echo -e "${GREEN}删除完成。${PLAIN}"
                        any_key_back
                        return 
                    else
                        echo -e "${YELLOW}已取消。${PLAIN}"
                        any_key_back
                    fi
                    ;;
                6)
                    read -p "请输入新的项目名称: " new_name
                    echo ""
                    if [[ -n "$new_name" ]]; then
                        sed -i "${p_idx}s/^[^|]*/${new_name}/" "$PROJECT_CONF_FILE"
                        p_name="$new_name"
                        echo -e "${GREEN}名称修改成功！${PLAIN}"
                        mapfile -t lines < "$PROJECT_CONF_FILE"
                    else
                        echo -e "${YELLOW}未输入名称，取消修改。${PLAIN}"
                    fi
                    any_key_back
                    ;;
                7)
                    nano docker-compose.yml
                    ;;
                8)
                    docker compose logs --tail 100
                    any_key_back
                    ;;
                0)
                    break
                    ;;
                *)
                    echo -e "${RED}无效选项${PLAIN}"
                    sleep 1
                    ;;
            esac
        done
    done
}

# --- 功能：备份项目 ---
backup_center() {
    while true; do
        echo ""
        echo -e "========= 备份项目 =========\n"
        
        echo -e " 1. 手动备份项目"
        echo ""
        echo -e " 2. 定时自动备份设置"
        echo ""
        echo -e " 0. 返回"
        echo ""
        
        read -p "请选择操作 [0-2]: " b_main_choice
        
        if [[ "$b_main_choice" == "0" ]]; then
            return
        fi
        
        case "$b_main_choice" in
            1)
                manual_backup_menu
                ;;
            2)
                auto_backup_settings
                ;;
            *) 
                echo ""
                echo -e "${RED}无效选项${PLAIN}"
                sleep 1 
                ;;
        esac
    done
}

# --- 子功能：手动备份 ---
manual_backup_menu() {
    while true; do
        echo ""
        echo -e "========= 手动备份项目 =========\n"
        
        if [[ ! -s "$PROJECT_CONF_FILE" ]]; then
            echo -e "${RED}项目列表为空。${PLAIN}"
            any_key_back
            return
        fi

        mapfile -t lines < "$PROJECT_CONF_FILE"
        local i=1
        for line in "${lines[@]}"; do
            name=$(echo "$line" | cut -d'|' -f1)
            echo -e " ${i}. ${name}"
            echo ""
            ((i++))
        done
        echo -e " 0. 返回"
        echo ""

        read -p "请选择要备份的项目 [0-${#lines[@]}]: " b_idx
        if [[ "$b_idx" == "0" ]]; then
            return
        fi

        echo ""

        if ! [[ "$b_idx" =~ ^[0-9]+$ ]] || [[ "$b_idx" -lt 1 ]] || [[ "$b_idx" -gt ${#lines[@]} ]]; then
            echo -e "${RED}无效的选择。${PLAIN}"
            any_key_back
            continue
        fi

        selected_line="${lines[$((b_idx-1))]}"
        p_name=$(echo "$selected_line" | cut -d'|' -f1)
        p_path=$(echo "$selected_line" | cut -d'|' -f2)
        
        backup_file="${BACKUP_DIR}/${p_name}_$(date +%Y%m%d_%H%M%S).tar.gz"

        echo -e "${BLUE}正在打包目录: ${p_path}...${PLAIN}"
        echo ""

        parent_dir=$(dirname "$p_path")
        target_name=$(basename "$p_path")
        
        if tar -czf "$backup_file" -C "$parent_dir" "$target_name"; then
            echo -e "${GREEN}备份成功！${PLAIN}"
            echo ""
            echo -e "备份文件: ${YELLOW}${backup_file}${PLAIN}"
        else
            echo -e "${RED}备份失败。${PLAIN}"
        fi
        any_key_back
    done
}

# --- 子功能：自动备份设置 ---
auto_backup_settings() {
    while true; do
        echo ""
        echo -e "========= 定时自动备份设置 =========\n"
        
        # 实时读取 Cron 配置
        if [[ -f "$CRON_FILE" ]]; then
            cron_min=$(awk '{print $1}' "$CRON_FILE")
            cron_hour=$(awk '{print $2}' "$CRON_FILE")
            printf -v formatted_time "%02d:%02d" "$((10#$cron_hour))" "$((10#$cron_min))"
            AUTO_STATUS="${GREEN}已开启(每日${formatted_time})${PLAIN}"
        else
            AUTO_STATUS="${RED}未开启${PLAIN}"
        fi
        
        echo -e " 自动备份状态: ${AUTO_STATUS}"
        echo ""
        echo -e "====================================\n"
        
        echo -e " 1. 开启每日自动备份"
        echo ""
        echo -e " 2. 关闭自动备份"
        echo ""
        echo -e " 0. 返回"
        echo ""
        
        read -p "请选择操作 [0-2]: " ab_choice
        
        if [[ "$ab_choice" == "0" ]]; then
            return
        fi
        
        case "$ab_choice" in
            1)
                echo ""
                read -p "请输入备份小时 (0-23, 回车默认03): " user_hour
                [[ -z "$user_hour" ]] && user_hour="3"
                
                if ! [[ "$user_hour" =~ ^[0-9]+$ ]] || [ "$((10#$user_hour))" -lt 0 ] || [ "$((10#$user_hour))" -gt 23 ]; then
                    echo ""
                    echo -e "${RED}无效的小时输入。${PLAIN}"
                    any_key_back
                    continue
                fi

                echo ""
                read -p "请输入备份分钟 (0-59, 回车默认00): " user_min
                [[ -z "$user_min" ]] && user_min="0"

                if ! [[ "$user_min" =~ ^[0-9]+$ ]] || [ "$((10#$user_min))" -lt 0 ] || [ "$((10#$user_min))" -gt 59 ]; then
                    echo ""
                    echo -e "${RED}无效的分钟输入。${PLAIN}"
                    any_key_back
                    continue
                fi

                echo ""
                echo -e "${BLUE}正在生成自动备份任务...${PLAIN}"
                echo ""
                
                mkdir -p "$(dirname "$AUTO_BACKUP_SCRIPT")"

                # 生成后台备份脚本 (注意：这里已移除了 find -delete 命令)
                cat > "$AUTO_BACKUP_SCRIPT" <<EOF
#!/bin/bash
BACKUP_DIR="${BACKUP_DIR}"
CONF="${PROJECT_CONF_FILE}"
mkdir -p "\$BACKUP_DIR"

# 遍历项目文件
while IFS="|" read -r name path; do
    if [[ -d "\$path" ]]; then
        filename="\${name}_\$(date +%Y%m%d_%H%M%S).tar.gz"
        parent_dir=\$(dirname "\$path")
        target_name=\$(basename "\$path")
        tar -czf "\$BACKUP_DIR/\$filename" -C "\$parent_dir" "\$target_name"
    fi
done < "\$CONF"
EOF
                chmod +x "$AUTO_BACKUP_SCRIPT"
                
                # 写入 Cron 任务
                echo "$((10#$user_min)) $((10#$user_hour)) * * * root $AUTO_BACKUP_SCRIPT" > "$CRON_FILE"
                
                if systemctl is-active cron &> /dev/null; then
                    systemctl restart cron
                elif systemctl is-active crond &> /dev/null; then
                    systemctl restart crond
                fi
                
                printf -v show_time "%02d:%02d" "$((10#$user_hour))" "$((10#$user_min))"
                
                # 修复：移除了“保留7天”的提示文字
                echo -e "${GREEN}设置成功！每天 ${show_time} 将自动备份项目${PLAIN}"
                any_key_back
                ;;
            2)
                echo ""
                if [[ -f "$CRON_FILE" ]]; then
                    rm -f "$CRON_FILE"
                    rm -f "$AUTO_BACKUP_SCRIPT"
                    echo -e "${GREEN}已关闭自动备份。${PLAIN}"
                else
                    echo -e "${YELLOW}自动备份尚未开启，无需关闭。${PLAIN}"
                fi
                any_key_back
                ;;
            *)
                echo ""
                echo -e "${RED}无效选项${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

# --- 子菜单：Docker 服务管理 ---
docker_mgmt_menu() {
    while true; do
        echo ""
        get_status
        echo -e "========= 管理Docker服务 =========\n"
        echo -e " Docker 状态: ${STATUS}\n"
        echo -e "===================================\n"
        echo -e " 1. 启动 Docker\n"
        echo -e " 2. 停止 Docker\n"
        echo -e " 3. 重启 Docker\n"
        echo -e " 4. 卸载 Docker\n"
        echo -e " 5. 查看备份文件\n"
        echo -e " 0. 返回\n"
        read -p "请选择[0-5]: " sub_choice
        
        if [[ "$sub_choice" == "0" ]]; then
            return
        fi
        
        case "$sub_choice" in
            1) 
                systemctl start docker
                echo ""
                echo -e "${GREEN}已启动${PLAIN}"
                any_key_back
                ;;
            2) 
                systemctl stop docker
                echo ""
                echo -e "${RED}已停止${PLAIN}"
                any_key_back
                ;;
            3) 
                systemctl restart docker
                echo ""
                echo -e "${GREEN}已重启${PLAIN}"
                any_key_back
                ;;
            4)
                echo ""
                read -p "警告：这将卸载 Docker 及所有容器数据！确认? (y/n): " confirm
                echo ""
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    echo -e "${BLUE}正在停止服务...${PLAIN}"
                    echo ""
                    systemctl stop docker
                    echo ""
                    
                    echo -e "${BLUE}正在移除软件包...${PLAIN}"
                    echo ""
                    if [[ -f /etc/debian_version ]]; then
                        apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras &> /dev/null
                        apt-get autoremove -y &> /dev/null
                        rm -rf /var/lib/docker /var/lib/containerd
                    elif [[ -f /etc/redhat-release ]]; then
                        yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras &> /dev/null
                        rm -rf /var/lib/docker /var/lib/containerd
                    fi
                    
                    hash -r 
                    
                    echo -e "${GREEN}Docker 卸载完成${PLAIN}"
                    any_key_back
                else
                    echo -e "${YELLOW}已取消。${PLAIN}"
                    any_key_back
                fi
                ;;
            5)
                echo ""
                echo -e "备份目录: ${BACKUP_DIR}"
                echo ""
                ls -lh "$BACKUP_DIR"
                any_key_back
                ;;
            *) echo -e "\n${RED}无效选项${PLAIN}"; sleep 1 ;;
        esac
    done
}

# --- 子菜单：脚本管理 ---
script_mgmt_menu() {
    while true; do
        echo ""
        echo -e "========= 管理脚本 =========\n"
        echo -e " 1. 卸载\n"
        echo -e " 0. 返回\n"
        read -p "请选择[0-1]: " sub_choice
        
        if [[ "$sub_choice" == "0" ]]; then
            return
        fi
        
        case "$sub_choice" in
            1) 
                echo -e "\n========= 卸载管理 =========\n"
                read -p "确认卸载本脚本及配置文件? (Docker容器不会被删除) (y/n): " confirm
                echo ""
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    # 获取当前脚本的真实路径（如果是软链接，则获取源文件路径）
                    local current_script=$(readlink -f "$0")

                    rm -f "$CRON_FILE"
                    rm -f "$AUTO_BACKUP_SCRIPT"
                    rm -f /usr/bin/dk
                    rm -f "$PROJECT_CONF_FILE"
                    
                    echo -e "${GREEN}卸载完成。${PLAIN}"
                    echo ""
                    
                    rm -f "$current_script"
                    exit 0
                else
                    echo -e "${YELLOW}已取消${PLAIN}"
                    any_key_back
                fi
                ;;
            *) echo -e "\n${RED}无效选项${PLAIN}"; sleep 1 ;;
        esac
    done
}

# --- 主菜单 ---
show_menu() {
    get_status
    
    echo ""
    echo -e "${GREEN}========= Docker Compose Manager ${SCRIPT_VERSION} By Shinyuz =========${PLAIN}"
    echo ""
    echo -e " Docker Ver: ${GREEN}${VER}${PLAIN}"
    echo ""
    echo -e " Docker Status: ${GREEN}${STATUS}${PLAIN}"
    echo ""
    echo -e "${GREEN}============================================================${PLAIN}"
    echo ""
    echo -e " 1. 添加项目"
    echo ""
    echo -e " 2. 管理项目"
    echo ""
    echo -e " 3. 备份项目"
    echo ""
    echo -e " 4. 管理Docker服务"
    echo ""
    echo -e " 5. 管理脚本"
    echo ""
    echo -e " 0. 退出"
    echo ""
    read -p "请输入选项 [0-5]: " choice
}

# --- 主逻辑 ---
init_environment

while true; do
    show_menu
    case "$choice" in
        1) add_project ;;
        2) manage_project ;;
        3) backup_center ;;
        4) docker_mgmt_menu ;;
        5) script_mgmt_menu ;;
        0) 
           echo ""
           exit 0 
           ;;
        *) echo -e "\n${RED}无效选项${PLAIN}"; sleep 1 ;;
    esac
done