#!/bin/bash

# =================================================================
# OCI IDCS SSO Platform Setup Script
# =================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Logging
LOG_FILE="/tmp/sso-platform-setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root for security reasons."
        log_info "Please run as a regular user with sudo privileges."
        exit 1
    fi
}

check_os() {
    log_info "Checking operating system..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        log_info "Detected OS: $OS $VER"
    else
        log_error "Cannot detect operating system"
        exit 1
    fi
    
    case $OS in
        "CentOS Linux"|"Red Hat Enterprise Linux"|"Rocky Linux"|"AlmaLinux")
            PACKAGE_MANAGER="yum"
            FIREWALL_CMD="firewall-cmd"
            ;;
        "Ubuntu"|"Debian GNU/Linux")
            PACKAGE_MANAGER="apt"
            FIREWALL_CMD="ufw"
            ;;
        *)
            log_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
    
    log_success "Operating system check completed"
}

install_dependencies() {
    log_info "Installing system dependencies..."
    
    case $PACKAGE_MANAGER in
        "yum")
            sudo yum update -y
            sudo yum install -y \
                curl \
                wget \
                git \
                unzip \
                vim \
                htop \
                net-tools \
                firewalld \
                python3 \
                python3-pip \
                openssl \
                ca-certificates \
                gnupg \
                lsb-release
            ;;
        "apt")
            sudo apt update
            sudo apt install -y \
                curl \
                wget \
                git \
                unzip \
                vim \
                htop \
                net-tools \
                ufw \
                python3 \
                python3-pip \
                openssl \
                ca-certificates \
                gnupg \
                lsb-release \
                apt-transport-https
            ;;
    esac
    
    log_success "System dependencies installed"
}

install_docker() {
    log_info "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        log_warning "Docker is already installed"
        docker --version
        return 0
    fi
    
    case $PACKAGE_MANAGER in
        "yum")
            # Remove old versions
            sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
            
            # Add Docker repository
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            
            # Install Docker
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        "apt")
            # Remove old versions
            sudo apt remove -y docker docker-engine docker.io containerd runc
            
            # Add Docker repository
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker
            sudo apt update
            sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
    esac
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    log_success "Docker installed successfully"
    log_warning "Please log out and log back in for Docker group membership to take effect"
}

install_docker_compose() {
    log_info "Installing Docker Compose..."
    
    # Check if docker-compose is already available
    if docker compose version &> /dev/null; then
        log_warning "Docker Compose (plugin) is already available"
        docker compose version
        return 0
    fi
    
    # Install standalone docker-compose if plugin is not available
    if ! command -v docker-compose &> /dev/null; then
        log_info "Installing standalone docker-compose..."
        COMPOSE_VERSION="v2.20.0"
        sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
    
    log_success "Docker Compose installed successfully"
}

configure_firewall() {
    log_info "Configuring firewall..."
    
    case $FIREWALL_CMD in
        "firewall-cmd")
            # Enable and start firewalld
            sudo systemctl enable firewalld
            sudo systemctl start firewalld
            
            # Open required ports
            sudo firewall-cmd --permanent --add-port=80/tcp      # HTTP
            sudo firewall-cmd --permanent --add-port=443/tcp     # HTTPS
            sudo firewall-cmd --permanent --add-port=3000/tcp    # Next.js Dev
            sudo firewall-cmd --permanent --add-port=8000/tcp    # FastAPI
            sudo firewall-cmd --permanent --add-port=389/tcp     # LDAP
            sudo firewall-cmd --permanent --add-port=636/tcp     # LDAPS
            sudo firewall-cmd --permanent --add-port=5432/tcp    # PostgreSQL
            sudo firewall-cmd --permanent --add-port=6379/tcp    # Redis
            sudo firewall-cmd --permanent --add-port=8080/tcp    # LDAP Admin
            sudo firewall-cmd --permanent --add-port=9090/tcp    # Prometheus
            sudo firewall-cmd --permanent --add-port=3001/tcp    # Grafana
            
            # Reload firewall
            sudo firewall-cmd --reload
            
            # List open ports
            log_info "Open ports:"
            sudo firewall-cmd --list-ports
            ;;
        "ufw")
            # Enable UFW
            sudo ufw --force enable
            
            # Open required ports
            sudo ufw allow 80/tcp      # HTTP
            sudo ufw allow 443/tcp     # HTTPS
            sudo ufw allow 3000/tcp    # Next.js Dev
            sudo ufw allow 8000/tcp    # FastAPI
            sudo ufw allow 389/tcp     # LDAP
            sudo ufw allow 636/tcp     # LDAPS
            sudo ufw allow 5432/tcp    # PostgreSQL
            sudo ufw allow 6379/tcp    # Redis
            sudo ufw allow 8080/tcp    # LDAP Admin
            sudo ufw allow 9090/tcp    # Prometheus
            sudo ufw allow 3001/tcp    # Grafana
            
            # Show status
            log_info "UFW status:"
            sudo ufw status numbered
            ;;
    esac
    
    log_success "Firewall configured successfully"
}

configure_selinux() {
    if command -v sestatus &> /dev/null; then
        log_info "Configuring SELinux..."
        
        # Check SELinux status
        SELINUX_STATUS=$(sestatus | grep "SELinux status" | awk '{print $3}')
        
        if [ "$SELINUX_STATUS" = "enabled" ]; then
            log_info "SELinux is enabled, configuring..."
            
            # Set SELinux booleans for HTTP connections
            sudo setsebool -P httpd_can_network_connect 1
            sudo setsebool -P httpd_can_network_relay 1
            
            # Allow containers to access network
            sudo setsebool -P container_manage_cgroup 1
            
            log_success "SELinux configured for container operations"
        else
            log_info "SELinux is disabled or not installed"
        fi
    else
        log_info "SELinux not found (not a RHEL-based system)"
    fi
}

create_directories() {
    log_info "Creating project directories..."
    
    cd "$PROJECT_ROOT"
    
    # Create required directories
    mkdir -p logs
    mkdir -p ssl
    mkdir -p secrets
    mkdir -p data/postgres
    mkdir -p data/ldap
    mkdir -p data/redis
    mkdir -p backup
    mkdir -p monitoring
    
    # Set appropriate permissions
    chmod 755 logs ssl backup monitoring
    chmod 700 secrets
    chmod 750 data/postgres data/ldap data/redis
    
    log_success "Project directories created"
}

generate_secrets() {
    log_info "Generating secrets..."
    
    cd "$PROJECT_ROOT/secrets"
    
    # Generate random passwords
    echo "$(openssl rand -base64 32)" > postgres_password.txt
    echo "$(openssl rand -base64 32)" > redis_password.txt
    echo "$(openssl rand -base64 24)" > ldap_admin_password.txt
    echo "$(openssl rand -base64 24)" > ldap_config_password.txt
    echo "$(openssl rand -base64 48)" > jwt_secret.txt
    echo "$(openssl rand -base64 32)" > grafana_password.txt
    
    # Generate SAML private key and certificate
    if [ ! -f saml_private_key.pem ]; then
        log_info "Generating SAML certificate..."
        openssl req -x509 -newkey rsa:2048 -keyout saml_private_key.pem -out saml_certificate.pem -days 365 -nodes -subj "/C=KR/ST=Seoul/L=Seoul/O=Company/OU=IT/CN=sso.company.com"
    fi
    
    # Set secure permissions
    chmod 600 *.txt *.pem
    
    # Create placeholder for IDCS client secret
    if [ ! -f idcs_client_secret.txt ]; then
        echo "REPLACE_WITH_ACTUAL_IDCS_CLIENT_SECRET" > idcs_client_secret.txt
        chmod 600 idcs_client_secret.txt
        log_warning "Please update idcs_client_secret.txt with your actual IDCS client secret"
    fi
    
    log_success "Secrets generated successfully"
}

setup_ssl_certificates() {
    log_info "Setting up SSL certificates..."
    
    cd "$PROJECT_ROOT/ssl"
    
    # Generate self-signed certificate for development
    if [ ! -f server.crt ]; then
        log_info "Generating self-signed SSL certificate for development..."
        openssl req -x509 -newkey rsa:2048 -keyout server.key -out server.crt -days 365 -nodes -subj "/C=KR/ST=Seoul/L=Seoul/O=Company/OU=IT/CN=localhost"
        
        # Generate CA certificate
        openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/C=KR/ST=Seoul/L=Seoul/O=Company/OU=IT/CN=Company CA"
        
        # Generate LDAP certificate
        openssl req -x509 -newkey rsa:2048 -keyout ldap.key -out ldap.crt -days 365 -nodes -subj "/C=KR/ST=Seoul/L=Seoul/O=Company/OU=IT/CN=ldap.company.com"
        
        chmod 600 *.key
        chmod 644 *.crt
        
        log_warning "Self-signed certificates generated for development."
        log_warning "For production, replace with certificates from a trusted CA."
    else
        log_info "SSL certificates already exist"
    fi
    
    log_success "SSL certificates setup completed"
}

create_env_file() {
    log_info "Creating environment configuration..."
    
    cd "$PROJECT_ROOT"
    
    if [ ! -f .env ]; then
        cp .env.example .env
        
        # Update .env with generated secrets
        if [ -f secrets/postgres_password.txt ]; then
            POSTGRES_PASSWORD=$(cat secrets/postgres_password.txt)
            sed -i "s/sso_password/$POSTGRES_PASSWORD/g" .env
        fi
        
        if [ -f secrets/jwt_secret.txt ]; then
            JWT_SECRET=$(cat secrets/jwt_secret.txt)
            sed -i "s/your-super-secret-jwt-key-change-this-in-production-minimum-32-characters/$JWT_SECRET/g" .env
        fi
        
        if [ -f secrets/ldap_admin_password.txt ]; then
            LDAP_PASSWORD=$(cat secrets/ldap_admin_password.txt)
            sed -i "s/admin_password/$LDAP_PASSWORD/g" .env
        fi
        
        log_success "Environment file created from template"
        log_warning "Please review and update .env file with your specific configuration"
    else
        log_info "Environment file already exists"
    fi
}

create_monitoring_config() {
    log_info "Creating monitoring configuration..."
    
    mkdir -p "$PROJECT_ROOT/monitoring"
    
    # Create Prometheus configuration
    cat > "$PROJECT_ROOT/monitoring/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'sso-backend'
    static_configs:
      - targets: ['backend:9000']
    metrics_path: '/metrics'

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx:80']
EOF

    # Create Loki configuration
    cat > "$PROJECT_ROOT/monitoring/loki.yml" << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb:
    directory: /loki/index

  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
EOF

    # Create Promtail configuration
    cat > "$PROJECT_ROOT/monitoring/promtail.yml" << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: containers
    static_configs:
      - targets:
          - localhost
        labels:
          job: containerlogs
          __path__: /var/lib/docker/containers/*/*log

  - job_name: application-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: applogs
          __path__: /var/log/app/*.log
EOF

    log_success "Monitoring configuration created"
}

create_nginx_config() {
    log_info "Creating Nginx configuration..."
    
    mkdir -p "$PROJECT_ROOT/nginx"
    
    # Development configuration
    cat > "$PROJECT_ROOT/nginx/dev.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream frontend {
        server frontend:3000;
    }

    upstream backend {
        server backend:8000;
    }

    server {
        listen 80;
        server_name localhost;

        location / {
            proxy_pass http://frontend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /api/ {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /health {
            proxy_pass http://backend/health;
            access_log off;
        }
    }
}
EOF

    # Production configuration
    cat > "$PROJECT_ROOT/nginx/prod.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/conf.d/rate-limit.conf;

    upstream frontend {
        server frontend:3000;
    }

    upstream backend {
        server backend:8000;
    }

    # Redirect HTTP to HTTPS
    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name _;

        ssl_certificate /etc/nginx/ssl/server.crt;
        ssl_certificate_key /etc/nginx/ssl/server.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;

        add_header Strict-Transport-Security "max-age=63072000" always;
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";

        location / {
            proxy_pass http://frontend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /api/ {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /health {
            proxy_pass http://backend/health;
            access_log off;
        }
    }
}
EOF

    # Rate limiting configuration
    cat > "$PROJECT_ROOT/nginx/rate-limit.conf" << 'EOF'
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;

limit_req zone=api burst=20 nodelay;
limit_req zone=login burst=5 nodelay;
EOF

    log_success "Nginx configuration created"
}

install_project_dependencies() {
    log_info "Installing project dependencies..."
    
    cd "$PROJECT_ROOT"
    
    # Install Python dependencies for backend
    if [ -f backend/requirements.txt ]; then
        log_info "Installing Python dependencies..."
        python3 -m pip install --user -r backend/requirements.txt
    fi
    
    # Install Node.js dependencies for frontend
    if [ -f frontend/package.json ]; then
        log_info "Installing Node.js dependencies..."
        if command -v npm &> /dev/null; then
            cd frontend
            npm install
            cd ..
        else
            log_warning "npm not found. Please install Node.js and npm manually."
        fi
    fi
    
    log_success "Project dependencies installation completed"
}

setup_database() {
    log_info "Setting up database initialization..."
    
    mkdir -p "$PROJECT_ROOT/database"
    
    # Create database initialization script
    cat > "$PROJECT_ROOT/database/init.sql" << 'EOF'
-- Database initialization for OCI IDCS SSO Platform

-- Create database if not exists
-- Note: This will be executed automatically by PostgreSQL container

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS sso_platform;

-- Set default schema
SET search_path TO sso_platform, public;

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    display_name VARCHAR(255),
    source VARCHAR(50) NOT NULL CHECK (source IN ('idcs', 'saml', 'ldap')),
    is_active BOOLEAN DEFAULT true,
    last_login TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Groups table
CREATE TABLE IF NOT EXISTS groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_name VARCHAR(255) UNIQUE NOT NULL,
    display_name VARCHAR(255),
    description TEXT,
    source VARCHAR(50) NOT NULL CHECK (source IN ('idcs', 'ldap', 'local')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User groups relationship
CREATE TABLE IF NOT EXISTS user_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, group_id)
);

-- Applications table
CREATE TABLE IF NOT EXISTS applications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    app_id VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    url VARCHAR(1000) NOT NULL,
    icon_url VARCHAR(1000),
    sso_enabled BOOLEAN DEFAULT true,
    sso_type VARCHAR(50) CHECK (sso_type IN ('saml', 'oauth', 'custom')),
    is_active BOOLEAN DEFAULT true,
    settings JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Application access permissions
CREATE TABLE IF NOT EXISTS application_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    application_id UUID REFERENCES applications(id) ON DELETE CASCADE,
    group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
    permission_level VARCHAR(50) DEFAULT 'read',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(application_id, group_id)
);

-- Sessions table
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id VARCHAR(255) UNIQUE NOT NULL,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    session_data JSONB,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Audit logs
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(100),
    resource_id VARCHAR(255),
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- IDCS sync status
CREATE TABLE IF NOT EXISTS sync_status (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sync_type VARCHAR(50) NOT NULL,
    last_sync TIMESTAMP WITH TIME ZONE,
    status VARCHAR(50) NOT NULL,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_user_id ON users(user_id);
CREATE INDEX IF NOT EXISTS idx_users_source ON users(source);
CREATE INDEX IF NOT EXISTS idx_users_last_login ON users(last_login);

CREATE INDEX IF NOT EXISTS idx_groups_name ON groups(group_name);
CREATE INDEX IF NOT EXISTS idx_groups_source ON groups(source);

CREATE INDEX IF NOT EXISTS idx_user_groups_user_id ON user_groups(user_id);
CREATE INDEX IF NOT EXISTS idx_user_groups_group_id ON user_groups(group_id);

CREATE INDEX IF NOT EXISTS idx_applications_app_id ON applications(app_id);
CREATE INDEX IF NOT EXISTS idx_applications_active ON applications(is_active);

CREATE INDEX IF NOT EXISTS idx_sessions_session_id ON sessions(session_id);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_groups_updated_at BEFORE UPDATE ON groups FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_applications_updated_at BEFORE UPDATE ON applications FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_sync_status_updated_at BEFORE UPDATE ON sync_status FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insert default data
INSERT INTO groups (group_name, display_name, description, source) VALUES
    ('admins', 'Administrators', 'System administrators with full access', 'local'),
    ('users', 'Users', 'Regular users with basic access', 'local'),
    ('developers', 'Developers', 'Developers with development environment access', 'local'),
    ('managers', 'Managers', 'Managers with management access', 'local'),
    ('support', 'Support', 'Support staff with support access', 'local')
ON CONFLICT (group_name) DO NOTHING;

-- Insert sample applications
INSERT INTO applications (app_id, name, description, url, sso_enabled, sso_type) VALUES
    ('app1', 'Application 1', 'First integrated application', 'https://app1.example.com', true, 'saml'),
    ('app2', 'Application 2', 'Second integrated application', 'https://app2.example.com', true, 'oauth'),
    ('dev-env', 'Development Environment', 'Development environment access', 'https://dev.company.com', true, 'oauth'),
    ('support-portal', 'Support Portal', 'Customer support portal', 'https://support.company.com', true, 'saml')
ON CONFLICT (app_id) DO NOTHING;

-- Grant permissions
DO $
DECLARE
    admin_group_id UUID;
    user_group_id UUID;
    dev_group_id UUID;
    app_rec RECORD;
BEGIN
    -- Get group IDs
    SELECT id INTO admin_group_id FROM groups WHERE group_name = 'admins';
    SELECT id INTO user_group_id FROM groups WHERE group_name = 'users';
    SELECT id INTO dev_group_id FROM groups WHERE group_name = 'developers';
    
    -- Grant permissions to applications
    FOR app_rec IN SELECT id FROM applications LOOP
        -- Admins get access to all apps
        INSERT INTO application_permissions (application_id, group_id, permission_level)
        VALUES (app_rec.id, admin_group_id, 'admin')
        ON CONFLICT DO NOTHING;
        
        -- Users get read access to most apps
        INSERT INTO application_permissions (application_id, group_id, permission_level)
        VALUES (app_rec.id, user_group_id, 'read')
        ON CONFLICT DO NOTHING;
    END LOOP;
    
    -- Developers get access to dev environment
    INSERT INTO application_permissions (application_id, group_id, permission_level)
    SELECT id, dev_group_id, 'write'
    FROM applications 
    WHERE app_id = 'dev-env'
    ON CONFLICT DO NOTHING;
END $;

-- Create cleanup function for expired sessions
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS INTEGER AS $
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM sessions WHERE expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$ LANGUAGE plpgsql;

-- Insert initial sync status
INSERT INTO sync_status (sync_type, status, details) VALUES
    ('idcs_users', 'pending', '{"message": "Initial sync pending"}'),
    ('idcs_groups', 'pending', '{"message": "Initial sync pending"}'),
    ('ldap_users', 'pending', '{"message": "Initial sync pending"}'),
    ('ldap_groups', 'pending', '{"message": "Initial sync pending"}')
ON CONFLICT DO NOTHING;
EOF

    log_success "Database initialization script created"
}

create_backup_scripts() {
    log_info "Creating backup scripts..."
    
    mkdir -p "$PROJECT_ROOT/scripts/backup"
    
    # Database backup script
    cat > "$PROJECT_ROOT/scripts/backup/backup-database.sh" << 'EOF'
#!/bin/bash
# Database backup script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BACKUP_DIR="$PROJECT_ROOT/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR/database"

# Backup PostgreSQL
echo "Backing up PostgreSQL database..."
docker-compose exec -T postgres pg_dump -U sso_user sso_db | gzip > "$BACKUP_DIR/database/postgres_$TIMESTAMP.sql.gz"

# Backup LDAP
echo "Backing up LDAP directory..."
docker-compose exec -T openldap slapcat | gzip > "$BACKUP_DIR/database/ldap_$TIMESTAMP.ldif.gz"

# Cleanup old backups (keep last 7 days)
find "$BACKUP_DIR/database" -name "*.gz" -mtime +7 -delete

echo "Backup completed: $TIMESTAMP"
EOF

    chmod +x "$PROJECT_ROOT/scripts/backup/backup-database.sh"
    
    # Configuration backup script
    cat > "$PROJECT_ROOT/scripts/backup/backup-config.sh" << 'EOF'
#!/bin/bash
# Configuration backup script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BACKUP_DIR="$PROJECT_ROOT/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR/config"

# Backup configuration files
tar -czf "$BACKUP_DIR/config/config_$TIMESTAMP.tar.gz" \
    -C "$PROJECT_ROOT" \
    .env \
    docker-compose.*.yml \
    nginx/ \
    monitoring/ \
    ssl/ \
    --exclude=ssl/*.key

echo "Configuration backup completed: $TIMESTAMP"
EOF

    chmod +x "$PROJECT_ROOT/scripts/backup/backup-config.sh"
    
    log_success "Backup scripts created"
}

create_maintenance_scripts() {
    log_info "Creating maintenance scripts..."
    
    mkdir -p "$PROJECT_ROOT/scripts/maintenance"
    
    # System status script
    cat > "$PROJECT_ROOT/scripts/maintenance/system-status.sh" << 'EOF'
#!/bin/bash
# System status check script

echo "=== OCI IDCS SSO Platform Status ==="
echo "Timestamp: $(date)"
echo

# Docker status
echo "=== Docker Containers ==="
docker-compose ps
echo

# Service health checks
echo "=== Service Health ==="
curl -s http://localhost:8000/health | jq '.' 2>/dev/null || echo "Backend health check failed"
echo

# Database connections
echo "=== Database Status ==="
docker-compose exec -T postgres psql -U sso_user -d sso_db -c "SELECT count(*) as active_connections FROM pg_stat_activity;" 2>/dev/null || echo "Database check failed"
echo

# LDAP status
echo "=== LDAP Status ==="
docker-compose exec -T openldap ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=company,dc=com" -w admin_password -b "dc=company,dc=com" -s base "(objectclass=*)" 2>/dev/null && echo "LDAP is accessible" || echo "LDAP check failed"
echo

# Disk usage
echo "=== Disk Usage ==="
df -h
echo

# Memory usage
echo "=== Memory Usage ==="
free -h
echo

# Container logs (last 10 lines)
echo "=== Recent Container Logs ==="
docker-compose logs --tail=10
EOF

    chmod +x "$PROJECT_ROOT/scripts/maintenance/system-status.sh"
    
    # Cleanup script
    cat > "$PROJECT_ROOT/scripts/maintenance/cleanup.sh" << 'EOF'
#!/bin/bash
# Cleanup script for maintenance

echo "Starting cleanup process..."

# Clean Docker images and containers
echo "Cleaning Docker resources..."
docker system prune -f
docker volume prune -f

# Clean application logs
echo "Rotating application logs..."
find logs/ -name "*.log" -size +100M -exec gzip {} \;
find logs/ -name "*.log.gz" -mtime +30 -delete

# Clean expired sessions from database
echo "Cleaning expired sessions..."
docker-compose exec -T postgres psql -U sso_user -d sso_db -c "SELECT cleanup_expired_sessions();" 2>/dev/null

echo "Cleanup completed"
EOF

    chmod +x "$PROJECT_ROOT/scripts/maintenance/cleanup.sh"
    
    log_success "Maintenance scripts created"
}

print_next_steps() {
    log_success "Setup completed successfully!"
    echo
    echo "=========================================="
    echo "           NEXT STEPS"
    echo "=========================================="
    echo
    echo "1. Review and update configuration:"
    echo "   - Edit .env file with your specific settings"
    echo "   - Update secrets/idcs_client_secret.txt with actual IDCS client secret"
    echo "   - Configure OCI IDCS application settings"
    echo
    echo "2. Start the development environment:"
    echo "   cd $PROJECT_ROOT"
    echo "   docker-compose -f docker-compose.dev.yml up -d"
    echo
    echo "3. Access the applications:"
    echo "   - Frontend: http://localhost:3000"
    echo "   - Backend API: http://localhost:8000"
    echo "   - API Documentation: http://localhost:8000/docs"
    echo "   - LDAP Admin: http://localhost:8080"
    echo "   - Prometheus: http://localhost:9090"
    echo "   - Grafana: http://localhost:3001"
    echo
    echo "4. Default credentials:"
    echo "   - LDAP Admin: cn=admin,dc=company,dc=com / $(cat secrets/ldap_admin_password.txt 2>/dev/null || echo 'check secrets/ldap_admin_password.txt')"
    echo "   - Grafana Admin: admin / $(cat secrets/grafana_password.txt 2>/dev/null || echo 'check secrets/grafana_password.txt')"
    echo
    echo "5. Testing:"
    echo "   - Run system status: ./scripts/maintenance/system-status.sh"
    echo "   - Run health checks: curl http://localhost:8000/health"
    echo
    echo "6. Production deployment:"
    echo "   - Update SSL certificates in ssl/ directory"
    echo "   - Configure firewall for production"
    echo "   - Use docker-compose.prod.yml for production"
    echo
    echo "For support and documentation, please refer to README.md"
    echo "=========================================="
}

# Main execution
main() {
    log_info "Starting OCI IDCS SSO Platform setup..."
    log_info "Log file: $LOG_FILE"
    
    check_root
    check_os
    install_dependencies
    install_docker
    install_docker_compose
    configure_firewall
    configure_selinux
    create_directories
    generate_secrets
    setup_ssl_certificates
    create_env_file
    create_monitoring_config
    create_nginx_config
    setup_database
    create_backup_scripts
    create_maintenance_scripts
    
    print_next_steps
}

# Run main function
main "$@"