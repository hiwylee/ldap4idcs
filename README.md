# OCI IDCS SSO 통합 웹 플랫폼

OCI IDCS(Identity Cloud Service)와 OpenLDAP을 연동한 통합 인증 시스템 및 Single Sign-On(SSO)을 통한 외부 애플리케이션 통합 플랫폼

## 📋 목차

- [프로젝트 개요](#프로젝트-개요)
- [시스템 아키텍처](#시스템-아키텍처)
- [사전 준비사항](#사전-준비사항)
- [설치 및 설정](#설치-및-설정)
- [OCI IDCS 설정](#oci-idcs-설정)
- [OpenLDAP 설정](#openldap-설정)
- [애플리케이션 배포](#애플리케이션-배포)
- [사용법](#사용법)
- [트러블슈팅](#트러블슈팅)

## 🎯 프로젝트 개요

### 주요 기능
- **다중 인증 방식**: OCI IDCS SSO (SAML 2.0, OAuth 2.0) + OpenLDAP 직접 인증
- **Single Sign-On**: 외부 애플리케이션 seamless 연동
- **하이브리드 사용자 관리**: IDCS ↔ LDAP 동기화
- **권한 기반 접근 제어**: 그룹 및 역할 기반 애플리케이션 접근
- **iframe 통합**: SSO 토큰을 통한 외부 앱 자동 로그인

### 기술 스택
- **Frontend**: Next.js 14, TypeScript, Tailwind CSS
- **Backend**: FastAPI (Python), PostgreSQL
- **Identity**: OCI IDCS, OpenLDAP
- **Container**: Docker, Docker Compose
- **Protocol**: SAML 2.0, OAuth 2.0/OpenID Connect

## 🏗️ 시스템 아키텍처

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Next.js Web   │◄──►│   FastAPI       │◄──►│   OCI IDCS      │
│   Frontend      │    │   Backend       │    │   (Primary)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  External Apps  │    │   PostgreSQL    │    │   OpenLDAP      │
│   (iframe)      │    │   Database      │    │   (Secondary)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🔧 사전 준비사항

### 1. 시스템 요구사항
- **OS**: CentOS 7/8, RHEL 7/8, Ubuntu 18.04+
- **RAM**: 최소 4GB, 권장 8GB
- **CPU**: 최소 2 Core, 권장 4 Core
- **Disk**: 최소 20GB 여유 공간
- **Network**: 인터넷 연결 (OCI IDCS 통신용)

### 2. 필수 소프트웨어
- Docker 20.10+
- Docker Compose 1.29+
- Git
- curl, wget

### 3. 네트워크 포트 설정

#### 방화벽 포트 오픈
```bash
# CentOS/RHEL (firewall-cmd)
sudo firewall-cmd --permanent --add-port=80/tcp      # HTTP
sudo firewall-cmd --permanent --add-port=443/tcp     # HTTPS
sudo firewall-cmd --permanent --add-port=3000/tcp    # Next.js Dev
sudo firewall-cmd --permanent --add-port=8000/tcp    # FastAPI
sudo firewall-cmd --permanent --add-port=389/tcp     # LDAP
sudo firewall-cmd --permanent --add-port=636/tcp     # LDAPS
sudo firewall-cmd --permanent --add-port=5432/tcp    # PostgreSQL
sudo firewall-cmd --reload

# Ubuntu (ufw)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3000/tcp
sudo ufw allow 8000/tcp
sudo ufw allow 389/tcp
sudo ufw allow 636/tcp
sudo ufw allow 5432/tcp
sudo ufw enable
```

#### SELinux 설정 (CentOS/RHEL)
```bash
# SELinux 상태 확인
sestatus

# SELinux 설정 (필요시)
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P httpd_can_network_relay 1
```

## 🚀 설치 및 설정

### 1. 프로젝트 클론
```bash
git clone <repository-url>
cd oci-idcs-sso-platform
```

### 2. Docker 설치
```bash
# CentOS/RHEL
sudo yum update -y
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker

# Ubuntu
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Docker Compose 설치 (별도 설치가 필요한 경우)
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 현재 사용자를 docker 그룹에 추가
sudo usermod -aG docker $USER
newgrp docker
```

### 3. 환경 설정 파일 생성
```bash
cp .env.example .env
```

## 🔐 OCI IDCS 설정

### 1. OCI IDCS 테넌트 설정

#### IDCS 콘솔 접속
1. OCI Console → Identity & Security → Identity Cloud Service
2. IDCS URL 확인 및 관리자 계정으로 로그인

#### SAML Application 생성
1. **Applications** → **Add** → **SAML Application**
2. **Application Details**:
   - Name: `SSO Web Platform`
   - Description: `통합 SSO 웹 플랫폼`
3. **SSO Configuration**:
   - Entity ID: `https://your-domain.com/api/auth/saml/metadata`
   - Assertion Consumer URL: `https://your-domain.com/api/auth/saml/acs`
   - NameID Format: `Email Address`
   - Include Signing Certificate: `Yes`
4. **Attribute Configuration**:
   - User Attributes 매핑:
     ```
     firstName → first_name
     lastName → last_name
     emails[0].value → email
     groups → groups
     ```

#### OAuth Application 생성
1. **Applications** → **Add** → **Confidential Application**
2. **Application Details**:
   - Name: `SSO OAuth Client`
   - Description: `OAuth 2.0 클라이언트`
3. **Client Configuration**:
   - Allowed Grant Types: `Authorization Code`, `Refresh Token`
   - Redirect URL: `https://your-domain.com/api/auth/oauth/callback`
   - Post Logout Redirect URL: `https://your-domain.com/login`
   - Client Type: `Confidential`
4. **Token Configuration**:
   - Access Token Expiration: `3600` seconds
   - Refresh Token Expiration: `86400` seconds
   - Include Refresh Token: `Yes`

### 2. IDCS 설정 정보 수집
```bash
# .env 파일에 추가할 정보들
IDCS_TENANT_URL=https://idcs-xxxxxxxxxxxx.identity.oraclecloud.com
IDCS_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
IDCS_CLIENT_SECRET=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
IDCS_SCOPE=openid profile email groups

# SAML 설정
SAML_ENTITY_ID=https://your-domain.com/api/auth/saml/metadata
SAML_ACS_URL=https://your-domain.com/api/auth/saml/acs
SAML_SLO_URL=https://your-domain.com/api/auth/saml/sls
```

## 📚 OpenLDAP 설정

### 1. LDAP 디렉토리 구조 설계
```
dc=company,dc=com
├── ou=users
│   ├── uid=john.doe
│   ├── uid=jane.smith
│   └── ...
├── ou=groups
│   ├── cn=admins
│   ├── cn=users
│   ├── cn=developers
│   └── ...
└── ou=applications
    ├── cn=app1
    ├── cn=app2
    └── ...
```

### 2. LDAP 초기 데이터 준비
프로젝트에서 `ldap/init.ldif` 파일을 통해 초기 데이터를 설정합니다.

### 3. IDCS ↔ LDAP 동기화 설정
```bash
# 동기화 스크립트 실행 권한 설정
chmod +x scripts/sync-idcs-ldap.py

# 크론탭 설정 (매시간 동기화)
crontab -e
# 다음 라인 추가:
# 0 * * * * /usr/bin/python3 /path/to/scripts/sync-idcs-ldap.py
```

## 🚢 애플리케이션 배포

### 1. 환경 변수 설정
```bash
# .env 파일 편집
nano .env
```

`.env` 파일 예시:
```bash
# Database
DATABASE_URL=postgresql://sso_user:sso_password@postgres:5432/sso_db

# JWT
JWT_SECRET_KEY=your-super-secret-jwt-key-change-this-in-production
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=480

# OCI IDCS
IDCS_TENANT_URL=https://idcs-xxxxxxxxxxxx.identity.oraclecloud.com
IDCS_CLIENT_ID=your-idcs-client-id
IDCS_CLIENT_SECRET=your-idcs-client-secret
IDCS_SCOPE=openid profile email groups

# SAML
SAML_ENTITY_ID=https://your-domain.com/api/auth/saml/metadata
SAML_ACS_URL=https://your-domain.com/api/auth/saml/acs
SAML_SLO_URL=https://your-domain.com/api/auth/saml/sls
SAML_X509_CERT=your-saml-certificate
SAML_PRIVATE_KEY=your-saml-private-key

# LDAP
LDAP_SERVER=ldap://openldap:389
LDAP_BIND_DN=cn=admin,dc=company,dc=com
LDAP_BIND_PASSWORD=admin_password
LDAP_BASE_DN=dc=company,dc=com
LDAP_USER_DN=ou=users,dc=company,dc=com
LDAP_GROUP_DN=ou=groups,dc=company,dc=com

# Application
APP_HOST=0.0.0.0
APP_PORT=8000
FRONTEND_URL=http://localhost:3000
BACKEND_URL=http://localhost:8000

# SSL/TLS (Production)
SSL_CERT_PATH=/etc/ssl/certs/server.crt
SSL_KEY_PATH=/etc/ssl/private/server.key
```

### 2. Docker Compose 배포
```bash
# 개발 환경
docker-compose -f docker-compose.dev.yml up -d

# 프로덕션 환경
docker-compose -f docker-compose.prod.yml up -d

# 로그 확인
docker-compose logs -f

# 컨테이너 상태 확인
docker-compose ps
```

### 3. 초기 데이터베이스 설정
```bash
# 데이터베이스 마이그레이션
docker-compose exec backend python -m alembic upgrade head

# 초기 사용자 생성 (선택사항)
docker-compose exec backend python scripts/create_admin_user.py
```

### 4. SSL/TLS 인증서 설정 (프로덕션)
```bash
# Let's Encrypt 인증서 발급
sudo certbot certonly --standalone -d your-domain.com

# 인증서 파일 복사
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem ./ssl/server.crt
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem ./ssl/server.key

# 권한 설정
sudo chown -R $USER:$USER ./ssl/
chmod 600 ./ssl/server.key
```

## 📖 사용법

### 1. 웹 애플리케이션 접속
- **개발 환경**: http://localhost:3000
- **프로덕션**: https://your-domain.com

### 2. 로그인 방법
1. **IDCS SSO 로그인** (권장):
   - "IDCS로 로그인" 버튼 클릭
   - IDCS 로그인 페이지로 리다이렉트
   - 인증 후 자동으로 대시보드 이동

2. **LDAP 직접 로그인**:
   - "직접 로그인" 폼 사용
   - LDAP 사용자명/비밀번호 입력

### 3. 외부 애플리케이션 연동
1. 대시보드에서 연동된 애플리케이션 목록 확인
2. 애플리케이션 클릭 시 iframe으로 로드
3. SSO 토큰이 자동 전달되어 별도 로그인 불필요

### 4. 관리자 기능
- 사용자 관리: `/admin/users`
- 애플리케이션 관리: `/admin/applications`
- 그룹 관리: `/admin/groups`
- 동기화 상태: `/admin/sync-status`

## 🛠️ 트러블슈팅

### 일반적인 문제들

#### 1. IDCS 연결 실패
```bash
# IDCS 연결 테스트
curl -X GET "${IDCS_TENANT_URL}/.well-known/openid_configuration"

# 네트워크 연결 확인
ping idcs-xxxxxxxxxxxx.identity.oraclecloud.com
```

#### 2. LDAP 연결 실패
```bash
# LDAP 서버 상태 확인
docker-compose logs openldap

# LDAP 연결 테스트
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=company,dc=com" -W -b "dc=company,dc=com"
```

#### 3. 데이터베이스 연결 실패
```bash
# PostgreSQL 상태 확인
docker-compose logs postgres

# 데이터베이스 연결 테스트
docker-compose exec postgres psql -U sso_user -d sso_db -c "SELECT 1;"
```

#### 4. SSL/TLS 인증서 문제
```bash
# 인증서 유효성 확인
openssl x509 -in ./ssl/server.crt -text -noout

# 인증서 만료일 확인
openssl x509 -in ./ssl/server.crt -noout -dates
```

### 로그 파일 위치
- **애플리케이션 로그**: `./logs/app.log`
- **IDCS 연동 로그**: `./logs/idcs.log`
- **LDAP 동기화 로그**: `./logs/ldap-sync.log`
- **컨테이너 로그**: `docker-compose logs [service-name]`

### 성능 모니터링
```bash
# 컨테이너 리소스 사용량
docker stats

# 애플리케이션 헬스 체크
curl http://localhost:8000/health

# 데이터베이스 연결 수 확인
docker-compose exec postgres psql -U sso_user -d sso_db -c "SELECT count(*) FROM pg_stat_activity;"
```

## 📝 추가 정보

### API 문서
- **FastAPI Docs**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

### 개발자 가이드
- [Backend 개발 가이드](./backend/README.md)
- [Frontend 개발 가이드](./frontend/README.md)
- [API 참조](./docs/api-reference.md)

### 보안 가이드
- [보안 설정 가이드](./docs/security-guide.md)
- [인증서 관리](./docs/certificate-management.md)

### 운영 가이드
- [배포 가이드](./docs/deployment-guide.md)
- [모니터링 설정](./docs/monitoring-guide.md)
- [백업 및 복구](./docs/backup-recovery.md)

## 📞 지원

문제가 발생하거나 추가 지원이 필요한 경우:
1. 이슈 트래커에 문제 등록
2. 로그 파일과 함께 상세한 오류 내용 제공
3. 환경 정보 (OS, Docker 버전 등) 포함

---

**주의**: 프로덕션 환경에서는 반드시 보안 설정을 강화하고, 정기적인 백업과 모니터링을 수행하시기 바랍니다.