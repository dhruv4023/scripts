#!/bin/bash

set -e

echo "🚀 Starting setup..."

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track installed items
declare -A INSTALLED

# ==================== INSTALLER FUNCTIONS ====================

install_nvm() {
    if ! command -v nvm &> /dev/null
    then
        echo -e "${BLUE}📦 Installing NVM...${NC}"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        echo -e "${GREEN}✅ NVM installed${NC}"
        INSTALLED["nvm"]=1
    else
        echo -e "${GREEN}✅ NVM already installed${NC}"
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        INSTALLED["nvm"]=1
    fi
}

install_node() {
    if ! command -v nvm &> /dev/null; then
        echo -e "${YELLOW}⚠️  NVM is required for Node.js. Installing NVM first...${NC}"
        install_nvm
    fi

    if ! command -v node &> /dev/null
    then
        echo -e "${BLUE}⬇️  Installing latest Node.js...${NC}"
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        nvm install node
        nvm alias default node
        echo -e "${GREEN}✅ Node installed${NC}"
    else
        echo -e "${GREEN}✅ Node already installed${NC}"
    fi
    
    echo -e "${BLUE}🔍 Node version: $(node -v)${NC}"
    echo -e "${BLUE}🔍 NPM version: $(npm -v)${NC}"
    INSTALLED["node"]=1
}

install_java() {
    if ! command -v java &> /dev/null || ! java -version 2>&1 | grep -q 'version "21'; then
        echo -e "${BLUE}📦 Installing Java (OpenJDK 21)...${NC}"
        sudo apt update
        sudo apt install openjdk-21-jdk -y
        echo -e "${GREEN}✅ Java installed${NC}"
    else
        echo -e "${GREEN}✅ Java already installed${NC}"
    fi
    
    echo -e "${BLUE}🔍 Java version:${NC}"
    java -version
    INSTALLED["java"]=1
}

install_java17() {
    if ! command -v java &> /dev/null || ! java -version 2>&1 | grep -q 'version "17'; then
        echo -e "${BLUE}📦 Installing Java 17...${NC}"
        sudo apt update
        sudo apt install openjdk-17-jdk -y
        echo -e "${GREEN}✅ Java 17 installed${NC}"
    else
        echo -e "${GREEN}✅ Java 17 already installed${NC}"
    fi
    
    echo -e "${BLUE}🔍 Java version:${NC}"
    java -version
    INSTALLED["java17"]=1
}

install_maven() {
    if ! command -v mvn &> /dev/null
    then
        echo -e "${BLUE}📦 Installing Maven...${NC}"
        sudo apt update
        sudo apt install maven -y
        echo -e "${GREEN}✅ Maven installed${NC}"
    else
        echo -e "${GREEN}✅ Maven already installed${NC}"
    fi
    
    echo -e "${BLUE}🔍 Maven version:${NC}"
    mvn -version
    INSTALLED["maven"]=1
}

install_mysql() {
    if ! command -v mysql &> /dev/null
    then
        echo -e "${BLUE}📦 Installing MySQL...${NC}"
        sudo apt update
        sudo apt install mysql-server mysql-client -y
        echo -e "${GREEN}✅ MySQL installed${NC}"
    else
        echo -e "${GREEN}✅ MySQL already installed${NC}"
    fi
    
    echo -e "${BLUE}🔍 MySQL version:${NC}"
    mysql --version
    INSTALLED["mysql"]=1
}

install_postgres() {
    if ! command -v psql &> /dev/null
    then
        echo -e "${BLUE}📦 Installing PostgreSQL...${NC}"
        sudo apt update
        sudo apt install postgresql postgresql-contrib -y
        echo -e "${GREEN}✅ PostgreSQL installed${NC}"
    else
        echo -e "${GREEN}✅ PostgreSQL already installed${NC}"
    fi
    
    echo -e "${BLUE}🔍 PostgreSQL version:${NC}"
    psql --version
    INSTALLED["postgres"]=1
}

install_oci_cli() {
    if ! command -v oci &> /dev/null
    then
        echo -e "${BLUE}📦 Installing OCI CLI...${NC}"
        sudo apt update
        sudo apt install python3-pip -y
        pip3 install oci-cli
        echo -e "${GREEN}✅ OCI CLI installed${NC}"
    else
        echo -e "${GREEN}✅ OCI CLI already installed${NC}"
    fi
    
    echo -e "${BLUE}🔍 OCI CLI version:${NC}"
    oci --version
    INSTALLED["oci"]=1
}

install_docker() {
    if ! command -v docker &> /dev/null
    then
        echo -e "${BLUE}📦 Installing Docker...${NC}"
        sudo apt update
        sudo apt install docker.io docker-compose -y
        echo -e "${GREEN}✅ Docker installed${NC}"
    else
        echo -e "${GREEN}✅ Docker already installed${NC}"
    fi
    
    echo -e "${BLUE}🔍 Docker version:${NC}"
    docker --version
    INSTALLED["docker"]=1
}

# ==================== MENU SYSTEM ====================

show_menu() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Select what to install              ║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} 1) NVM (Node Version Manager)"
    echo -e "${BLUE}║${NC} 2) Node.js"
    echo -e "${BLUE}║${NC} 3) Java (OpenJDK 21)"
    echo -e "${BLUE}║${NC} 4) Java 17"
    echo -e "${BLUE}║${NC} 5) MySQL"
    echo -e "${BLUE}║${NC} 6) PostgreSQL"
    echo -e "${BLUE}║${NC} 7) OCI CLI"
    echo -e "${BLUE}║${NC} 8) Docker"
    echo -e "${BLUE}║${NC} 9) Maven"
    echo -e "${BLUE}║${NC} 10) All"
    echo -e "${BLUE}║${NC} 0) Exit"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# ==================== MAIN LOGIC ====================

select_installers() {
    local all_choices=()
    local selected_options=""

    while true; do
        show_menu
        echo -n -e "${YELLOW}Enter your choice (e.g., 1 2 3 or 10 for all): ${NC}"
        read -r selected_options

        # Check if user wants to exit
        if [[ "$selected_options" == "0" ]]; then
            echo -e "${YELLOW}Exiting setup...${NC}"
            exit 0
        fi

        # Process input
        if [[ "$selected_options" == "10" ]]; then
            all_choices=(1 2 3 4 5 6 7 8 9)
            break
        else
            # Split input by spaces and validate
            all_choices=($selected_options)
            local valid=true
            for choice in "${all_choices[@]}"; do
                if ! [[ "$choice" =~ ^[1-9]$ ]]; then
                    echo -e "${YELLOW}⚠️  Invalid choice: $choice${NC}"
                    valid=false
                    break
                fi
            done
            
            if $valid && [ ${#all_choices[@]} -gt 0 ]; then
                break
            else
                echo -e "${YELLOW}⚠️  Invalid input. Please enter numbers 1-9 separated by spaces or 10 for all.${NC}"
                sleep 1
            fi
        fi
    done

    # Install selected options
    echo ""
    echo -e "${GREEN}🔧 Installing selected packages...${NC}"
    echo ""

    for choice in "${all_choices[@]}"; do
        case $choice in
            1) install_nvm ;;
            2) install_node ;;
            3) install_java ;;
            4) install_java17 ;;
            5) install_mysql ;;
            6) install_postgres ;;
            7) install_oci_cli ;;
            8) install_docker ;;
            9) install_maven ;;
        esac
        echo ""
    done

    # Summary
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}✅ Setup Complete!${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════╣${NC}"
    if [ ${#INSTALLED[@]} -gt 0 ]; then
        echo -e "${GREEN}Installed components:${NC}"
        for component in "${!INSTALLED[@]}"; do
            echo -e "  ${GREEN}✓${NC} $component"
        done
    fi
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
}

# Run the selection menu
select_installers