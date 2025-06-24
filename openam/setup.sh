# Oracle IAM Docker 환경 설치 스크립트 (간소화 버전)
# ============================================================

set -e

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
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

# 헤더 출력
print_header() {
    echo ""
    echo "=============================================="
    echo "  Oracle IAM Docker Environment Setup"
    echo "  (OpenLDAP 기본 이미지 + OpenAM 커스텀)"
    echo "=============================================="
    echo ""
}

# 시스템 요구사항 확인
check_requirements() {
    log_info "시스템 요구사항 확인 중..."
    
    # Docker 확인
    if ! command -v docker &> /dev/null; then
        log_error "Docker가 설치되지 않았습니다."
        echo "Docker 설치: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Docker Compose 확인
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose가 설치되지 않았습니다."
        echo "Docker Compose 설치: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    # 메모리 확인
    total_mem=$(free -m | awk 'NR==2{printf "%.0f", $2/1024}')
    if [ "$total_mem" -lt 8 ]; then
        log_warning "시스템 메모리가 ${total_mem}GB입니다. 최소 8GB 권장."
    else
        log_success "시스템 메모리: ${total_mem}GB"
    fi
    
    # 포트 사용 확인
    ports=(389 636 8080 8081)
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            log_warning "포트 $port가 이미 사용 중입니다."
        fi
    done
    
    log_success "시스템 요구사항 확인 완료"
}

# 디렉토리 구조 생성
create_directories() {
    log_info "디렉토리 구조 생성 중..."
    
    # LDAP 커스텀 설정 디렉토리
    mkdir -p ldap-custom
    
    # 스크립트 디렉토리
    mkdir -p scripts
    
    log_success "디렉토리 구조 생성 완료"
}

# OpenAM Dockerfile 생성 (OpenLDAP은 기본 이미지 사용)
create_openam_dockerfile() {
    log_info "OpenAM Dockerfile 생성 중..."
    
    cat > Dockerfile.openam << 'EOF'
# OpenAM Dockerfile - 최적화된 버전
FROM openidentityplatform/openam:14.7.2

# 메타데이터
LABEL maintainer="Oracle IAM Team"
LABEL description="Oracle OpenAM Identity Provider for SAML SSO"
LABEL version="14.7.2-oracle"

# 환경 변수 설정
ENV JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom -Djava.net.preferIPv4Stack=true"
ENV CATALINA_OPTS="-Xms4g -Xmx16g -XX:MetaspaceSize=512m -XX:MaxMetaspaceSize=1g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+UseStringDeduplication -XX:+OptimizeStringConcat -server -Djava.awt.headless=true"
ENV OPENAM_ROOT_PASSWORD="Oracle_12345"

# 시스템 패키지 업데이트 및 필수 도구 설치
USER root
RUN apt-get update && \
    apt-get install -y \
        curl \
        wget \
        telnet \
        net-tools \
        ldap-utils \
        xmlstarlet \
        jq \
        vim \
        dnsutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# OpenAM 커스터마이징
RUN mkdir -p /usr/openam/custom \
             /usr/openam/scripts \
             /usr/openam/backup

# 헬스체크 스크립트 생성
RUN cat > /usr/openam/scripts/healthcheck.sh << 'EOFHC'
#!/bin/bash
curl -f http://localhost:8080/openam/isAlive.jsp || exit 1
curl -f http://localhost:8080/openam/json/serverinfo/* || exit 1
EOFHC

RUN chmod +x /usr/openam/scripts/healthcheck.sh

# SAML metadata export 스크립트 생성
RUN cat > /usr/openam/scripts/export-metadata.sh << 'EOFME'
#!/bin/bash
ENTITY_ID=${1:-"http://localhost:8080/openam"}
REALM=${2:-"/"}
OUTPUT_FILE=${3:-"/tmp/saml-metadata.xml"}

curl -s "http://localhost:8080/openam/saml2/jsp/exportmetadata.jsp?entityid=$ENTITY_ID&realm=$REALM" > "$OUTPUT_FILE"

if [ -s "$OUTPUT_FILE" ]; then
    echo "Metadata exported to: $OUTPUT_FILE"
    xmllint --format "$OUTPUT_FILE"
else
    echo "Failed to export metadata"
    exit 1
fi
EOFME

RUN chmod +x /usr/openam/scripts/export-metadata.sh

# 포트 노출
EXPOSE 8080 8443

# 볼륨 설정
VOLUME ["/usr/openam/config", "/usr/openam/custom", "/usr/openam/backup"]

# 헬스체크 설정
HEALTHCHECK --interval=30s --timeout=10s --retries=10 --start-period=120s \
    CMD ["/usr/openam/scripts/healthcheck.sh"]

# Tomcat 사용자로 전환
USER tomcat

# 시작 명령어
CMD ["catalina.sh", "run"]
EOF
    
    log_success "OpenAM Dockerfile 생성 완료"
}

# 환경 변수 파일 생성
create_env_file() {
    log_info "환경 변수 파일 생성 중..."
    
    cat > .env << 'EOF'
# Oracle IAM Docker Environment Variables
COMPOSE_PROJECT_NAME=oracle-iam
COMPOSE_FILE=docker-compose.yml

# 통일된 패스워드
UNIFIED_PASSWORD=Oracle_12345

# 시스템 설정
SYSTEM_TIMEZONE=Asia/Seoul
EOF
    
    log_success "환경 변수 파일 생성 완료"
}

# 초기 LDIF 파일 생성 (OpenLDAP 기본 이미지용)
create_ldif_files() {
    log_info "초기 LDIF 파일 생성 중..."
    
    cat > ldap-custom/01-oracle-structure.ldif << 'EOF'
# Oracle Corporation 조직 구조
dn: ou=people,dc=oracle,dc=com
objectClass: organizationalUnit
ou: people
description: Oracle Corporation Users

dn: ou=groups,dc=oracle,dc=com
objectClass: organizationalUnit
ou: groups
description: Oracle Corporation Groups

dn: ou=services,dc=oracle,dc=com
objectClass: organizationalUnit
ou: services
description: Oracle Corporation Services
EOF

    cat > ldap-custom/02-oracle-users.ldif << 'EOF'
# 관리자 사용자
dn: uid=admin,ou=people,dc=oracle,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: admin
sn: Administrator
givenName: System
cn: System Administrator
displayName: System Administrator
uidNumber: 1001
gidNumber: 1001
userPassword: Oracle_12345
gecos: System Administrator
loginShell: /bin/bash
homeDirectory: /home/admin
mail: admin@oracle.com
telephoneNumber: +1-555-0001

# 테스트 사용자 1
dn: uid=testuser1,ou=people,dc=oracle,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: testuser1
sn: User
givenName: Test
cn: Test User One
displayName: Test User One
uidNumber: 1002
gidNumber: 1002
userPassword: Oracle_12345
gecos: Test User One
loginShell: /bin/bash
homeDirectory: /home/testuser1
mail: testuser1@oracle.com
telephoneNumber: +1-555-0002

# 테스트 사용자 2
dn: uid=testuser2,ou=people,dc=oracle,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: testuser2
sn: User
givenName: Test
cn: Test User Two
displayName: Test User Two
uidNumber: 1003
gidNumber: 1003
userPassword: Oracle_12345
gecos: Test User Two
loginShell: /bin/bash
homeDirectory: /home/testuser2
mail: testuser2@oracle.com
telephoneNumber: +1-555-0003
EOF

    cat > ldap-custom/03-oracle-groups.ldif << 'EOF'
# 관리자 그룹
dn: cn=admins,ou=groups,dc=oracle,dc=com
objectClass: groupOfNames
objectClass: posixGroup
cn: admins
gidNumber: 2001
description: System Administrators
member: uid=admin,ou=people,dc=oracle,dc=com

# 사용자 그룹
dn: cn=users,ou=groups,dc=oracle,dc=com
objectClass: groupOfNames
objectClass: posixGroup
cn: users
gidNumber: 2002
description: Standard Users
member: uid=testuser1,ou=people,dc=oracle,dc=com
member: uid=testuser2,ou=people,dc=oracle,dc=com
member: uid=admin,ou=people,dc=oracle,dc=com
EOF
    
    log_success "초기 LDIF 파일 생성 완료"
}

# 테스트 스크립트 생성
create_test_scripts() {
    log_info "테스트 스크립트 생성 중..."
    
    # 시스템 검증 스크립트
    cat > scripts/system-verification.sh << 'EOF'
#!/bin/bash

echo "=== Oracle IAM Docker 환경 종합 검증 ==="

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
        return 0
    else
        echo -e "${RED}✗ $2${NC}"
        return 1
    fi
}

TOTAL_TESTS=0
PASSED_TESTS=0

# 1. Docker 컨테이너 상태 확인
echo "1. Docker 컨테이너 상태 확인"
echo "================================"

for container in openldap-server openam-server phpldapadmin; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if docker ps --format "table {{.Names}}" | grep -q "$container"; then
        test_result 0 "$container 실행중"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        test_result 1 "$container 실행중"
    fi
done

# 2. 포트 접근성 테스트
echo ""
echo "2. 포트 접근성 테스트"
echo "====================="

for port in "389:OpenLDAP" "8080:OpenAM" "8081:phpLDAPadmin"; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    port_num=$(echo $port | cut -d: -f1)
    service=$(echo $port | cut -d: -f2)
    
    if nc -z localhost $port_num 2>/dev/null; then
        test_result 0 "$service 포트 $port_num 접근 가능"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        test_result 1 "$service 포트 $port_num 접근 가능"
    fi
done

# 3. LDAP 기능 테스트
echo ""
echo "3. LDAP 기능 테스트"
echo "====================="

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if docker-compose exec -T openldap ldapsearch -x -H ldap://localhost -b "dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 >/dev/null 2>&1; then
    test_result 0 "LDAP 관리자 인증"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    test_result 1 "LDAP 관리자 인증"
fi

# 4. OpenAM 기능 테스트
echo ""
echo "4. OpenAM 기능 테스트"
echo "==================="

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -s -f http://localhost:8080/openam/isAlive.jsp | grep -q "Server is ALIVE"; then
    test_result 0 "OpenAM 서버 상태"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    test_result 1 "OpenAM 서버 상태"
fi

echo ""
echo "=== 검증 결과 요약 ==="
echo "총 테스트: $TOTAL_TESTS"
echo "통과: $PASSED_TESTS"
echo "실패: $((TOTAL_TESTS - PASSED_TESTS))"

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}모든 테스트 통과!${NC}"
    exit 0
else
    echo -e "${RED}일부 테스트 실패.${NC}"
    exit 1
fi
EOF

    # SAML metadata export 스크립트
    cat > scripts/metadata-export.sh << 'EOF'
#!/bin/bash

echo "=== SAML Metadata Export ==="

# 출력 디렉토리 생성
mkdir -p metadata-exports
cd metadata-exports

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
mkdir -p "$TIMESTAMP"
cd "$TIMESTAMP"

echo "Export 디렉토리: metadata-exports/$TIMESTAMP"

# 표준 Metadata export
echo "1. 표준 Metadata export..."
curl -s -o standard-metadata.xml "http://localhost:8080/openam/saml2/jsp/exportmetadata.jsp?entityid=http://localhost:8080/openam&realm=/"

if [ -s "standard-metadata.xml" ]; then
    echo "✓ 표준 Metadata export 성공"
    if xmllint --noout standard-metadata.xml 2>/dev/null; then
        echo "✓ XML 형식 유효"
    else
        echo "✗ XML 형식 오류"
    fi
else
    echo "✗ 표준 Metadata export 실패"
fi

echo ""
echo "=== Export 완료 ==="
echo "위치: $(pwd)"
ls -la

cd ../..
EOF

    # 사용자 로그인 테스트 스크립트
    cat > scripts/user-login-test.sh << 'EOF'
#!/bin/bash

echo#!/bin/bash

# Oracle IAM Docker 환경 설치 스크립트
# ===================================

set -e

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
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

# 헤더 출력
print_header() {
    echo ""
    echo "=============================================="
    echo "  Oracle IAM Docker Environment Setup"
    echo "=============================================="
    echo ""
}

# 시스템 요구사항 확인
check_requirements() {
    log_info "시스템 요구사항 확인 중..."
    
    # Docker 확인
    if ! command -v docker &> /dev/null; then
        log_error "Docker가 설치되지 않았습니다."
        echo "Docker 설치: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Docker Compose 확인
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose가 설치되지 않았습니다."
        echo "Docker Compose 설치: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    # 메모리 확인
    total_mem=$(free -m | awk 'NR==2{printf "%.0f", $2/1024}')
    if [ "$total_mem" -lt 8 ]; then
        log_warning "시스템 메모리가 ${total_mem}GB입니다. 최소 8GB 권장."
    else
        log_success "시스템 메모리: ${total_mem}GB"
    fi
    
    # 디스크 공간 확인
    available_space=$(df . | awk 'NR==2 {print int($4/1024/1024)}')
    if [ "$available_space" -lt 10 ]; then
        log_warning "사용 가능한 디스크 공간이 ${available_space}GB입니다. 최소 10GB 권장."
    else
        log_success "사용 가능한 디스크 공간: ${available_space}GB"
    fi
    
    # 포트 사용 확인
    ports=(389 636 8080 8081 9000)
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            log_warning "포트 $port가 이미 사용 중입니다."
        fi
    done
    
    log_success "시스템 요구사항 확인 완료"
}

# 디렉토리 구조 생성
create_directories() {
    log_info "디렉토리 구조 생성 중..."
    
    # 데이터 디렉토리
    mkdir -p data/{ldap-data,ldap-config,openam-data}
    
    # 로그 디렉토리
    mkdir -p logs/{openam,nginx}
    
    # 백업 디렉토리
    mkdir -p backup/{ldap,openam}
    
    # 커스텀 설정 디렉토리
    mkdir -p {ldap-custom,openam-custom}
    
    # Nginx 설정 디렉토리
    mkdir -p nginx/conf.d
    
    # 스크립트 디렉토리
    mkdir -p scripts
    
    log_success "디렉토리 구조 생성 완료"
}

# Docker 파일 생성
create_docker_files() {
    log_info "Docker 파일 생성 중..."
    
    # Dockerfile.openldap 생성
    cat > Dockerfile.openldap << 'EOF'
# OpenLDAP Dockerfile - 최적화된 버전
FROM osixia/openldap:1.5.0

# 메타데이터
LABEL maintainer="Oracle IAM Team"
LABEL description="Oracle OpenLDAP Directory Server"
LABEL version="1.5.0-oracle"

# 환경 변수 설정
ENV LDAP_LOG_LEVEL="256" \
    LDAP_ORGANISATION="Oracle Corporation" \
    LDAP_DOMAIN="oracle.com" \
    LDAP_BASE_DN="dc=oracle,dc=com" \
    LDAP_ADMIN_PASSWORD="Oracle_12345" \
    LDAP_CONFIG_PASSWORD="Oracle_12345" \
    LDAP_READONLY_USER="false" \
    LDAP_RFC2307BIS_SCHEMA="false" \
    LDAP_BACKEND="mdb" \
    LDAP_TLS="true" \
    LDAP_TLS_ENFORCE="false" \
    LDAP_TLS_VERIFY_CLIENT="never" \
    LDAP_REPLICATION="false" \
    KEEP_EXISTING_CONFIG="false" \
    LDAP_REMOVE_CONFIG_AFTER_SETUP="true"

# 추가 패키지 설치
USER root
RUN apt-get update && \
    apt-get install -y \
        curl \
        wget \
        net-tools \
        htop \
        vim \
        jq \
        dnsutils \
        telnet && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# LDAP 스크립트 디렉토리 생성
RUN mkdir -p /opt/ldap-scripts /opt/ldap-backup

# 헬스체크 스크립트
RUN cat > /opt/ldap-scripts/healthcheck.sh << 'EOFHC'
#!/bin/bash
ldapsearch -x -H ldap://localhost -b "dc=oracle,dc=com" \
    -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 \
    "(objectClass=*)" dn >/dev/null 2>&1
EOFHC

RUN chmod +x /opt/ldap-scripts/healthcheck.sh

# 포트 노출
EXPOSE 389 636

# 볼륨 설정
VOLUME ["/var/lib/ldap", "/etc/ldap/slapd.d", "/container/service/slapd/assets/certs", "/opt/ldap-backup"]

# 헬스체크 설정
HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=60s \
    CMD ["/opt/ldap-scripts/healthcheck.sh"]

# OpenLDAP 사용자로 전환
USER openldap
EOF

    # Dockerfile.openam 생성
    cat > Dockerfile.openam << 'EOF'
# OpenAM Dockerfile - 최적화된 버전
FROM openidentityplatform/openam:14.7.2

# 메타데이터
LABEL maintainer="Oracle IAM Team"
LABEL description="Oracle OpenAM Identity Provider for SAML SSO"
LABEL version="14.7.2-oracle"

# 환경 변수 설정
ENV JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom -Djava.net.preferIPv4Stack=true"
ENV CATALINA_OPTS="-Xms4g -Xmx16g -XX:MetaspaceSize=512m -XX:MaxMetaspaceSize=1g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+UseStringDeduplication -XX:+OptimizeStringConcat -server -Djava.awt.headless=true"
ENV OPENAM_ROOT_PASSWORD="Oracle_12345"

# 시스템 패키지 업데이트 및 필수 도구 설치
USER root
RUN apt-get update && \
    apt-get install -y \
        curl \
        wget \
        telnet \
        net-tools \
        ldap-utils \
        xmlstarlet \
        jq \
        vim \
        dnsutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# OpenAM 커스터마이징
RUN mkdir -p /usr/openam/custom \
             /usr/openam/scripts \
             /usr/openam/backup

# 헬스체크 스크립트 생성
RUN cat > /usr/openam/scripts/healthcheck.sh << 'EOFHC'
#!/bin/bash
curl -f http://localhost:8080/openam/isAlive.jsp || exit 1
curl -f http://localhost:8080/openam/json/serverinfo/* || exit 1
EOFHC

RUN chmod +x /usr/openam/scripts/healthcheck.sh

# 포트 노출
EXPOSE 8080 8443

# 볼륨 설정
VOLUME ["/usr/openam/config", "/usr/openam/custom", "/usr/openam/backup"]

# 헬스체크 설정
HEALTHCHECK --interval=30s --timeout=10s --retries=10 --start-period=120s \
    CMD ["/usr/openam/scripts/healthcheck.sh"]

# Tomcat 사용자로 전환
USER tomcat

# 시작 명령어
CMD ["catalina.sh", "run"]
EOF
    
    log_success "Docker 파일 생성 완료"
}

# 환경 변수 파일 생성
create_env_file() {
    log_info "환경 변수 파일 생성 중..."
    
    cat > .env << 'EOF'
# Oracle IAM Docker Environment Variables
COMPOSE_PROJECT_NAME=oracle-iam
COMPOSE_FILE=docker-compose.yml

# 통일된 패스워드
UNIFIED_PASSWORD=Oracle_12345

# 시스템 설정
SYSTEM_TIMEZONE=Asia/Seoul
EOF
    
    log_success "환경 변수 파일 생성 완료"
}

# 초기 LDIF 파일 생성
create_ldif_files() {
    log_info "초기 LDIF 파일 생성 중..."
    
    cat > ldap-custom/01-oracle-structure.ldif << 'EOF'
# Oracle Corporation 조직 구조
dn: ou=people,dc=oracle,dc=com
objectClass: organizationalUnit
ou: people
description: Oracle Corporation Users

dn: ou=groups,dc=oracle,dc=com
objectClass: organizationalUnit
ou: groups
description: Oracle Corporation Groups

dn: ou=services,dc=oracle,dc=com
objectClass: organizationalUnit
ou: services
description: Oracle Corporation Services
EOF

    cat > ldap-custom/02-oracle-users.ldif << 'EOF'
# 관리자 사용자
dn: uid=admin,ou=people,dc=oracle,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: admin
sn: Administrator
givenName: System
cn: System Administrator
displayName: System Administrator
uidNumber: 1001
gidNumber: 1001
userPassword: Oracle_12345
gecos: System Administrator
loginShell: /bin/bash
homeDirectory: /home/admin
mail: admin@oracle.com
telephoneNumber: +1-555-0002

# 테스트 사용자 2
dn: uid=testuser2,ou=people,dc=oracle,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: testuser2
sn: User
givenName: Test
cn: Test User Two
displayName: Test User Two
uidNumber: 1003
gidNumber: 1003
userPassword: Oracle_12345
gecos: Test User Two
loginShell: /bin/bash
homeDirectory: /home/testuser2
mail: testuser2@oracle.com
telephoneNumber: +1-555-0003
EOF

    cat > ldap-custom/03-oracle-groups.ldif << 'EOF'
# 관리자 그룹
dn: cn=admins,ou=groups,dc=oracle,dc=com
objectClass: groupOfNames
objectClass: posixGroup
cn: admins
gidNumber: 2001
description: System Administrators
member: uid=admin,ou=people,dc=oracle,dc=com

# 사용자 그룹
dn: cn=users,ou=groups,dc=oracle,dc=com
objectClass: groupOfNames
objectClass: posixGroup
cn: users
gidNumber: 2002
description: Standard Users
member: uid=testuser1,ou=people,dc=oracle,dc=com
member: uid=testuser2,ou=people,dc=oracle,dc=com
member: uid=admin,ou=people,dc=oracle,dc=com
EOF
    
    log_success "초기 LDIF 파일 생성 완료"
}

# 테스트 스크립트 생성
create_test_scripts() {
    log_info "테스트 스크립트 생성 중..."
    
    # 시스템 검증 스크립트
    cat > scripts/system-verification.sh << 'EOF'
#!/bin/bash

echo "=== Oracle IAM Docker 환경 종합 검증 ==="

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
        return 0
    else
        echo -e "${RED}✗ $2${NC}"
        return 1
    fi
}

TOTAL_TESTS=0
PASSED_TESTS=0

# 1. Docker 컨테이너 상태 확인
echo "1. Docker 컨테이너 상태 확인"
echo "================================"

for container in openldap-server openam-server phpldapadmin; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if docker ps --format "table {{.Names}}" | grep -q "$container"; then
        test_result 0 "$container 실행중"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        test_result 1 "$container 실행중"
    fi
done

# 2. 포트 접근성 테스트
echo ""
echo "2. 포트 접근성 테스트"
echo "====================="

for port in "389:OpenLDAP" "8080:OpenAM" "8081:phpLDAPadmin"; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    port_num=$(echo $port | cut -d: -f1)
    service=$(echo $port | cut -d: -f2)
    
    if nc -z localhost $port_num 2>/dev/null; then
        test_result 0 "$service 포트 $port_num 접근 가능"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        test_result 1 "$service 포트 $port_num 접근 가능"
    fi
done

# 3. LDAP 기능 테스트
echo ""
echo "3. LDAP 기능 테스트"
echo "====================="

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if docker-compose exec -T openldap ldapsearch -x -H ldap://localhost -b "dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 >/dev/null 2>&1; then
    test_result 0 "LDAP 관리자 인증"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    test_result 1 "LDAP 관리자 인증"
fi

# 4. OpenAM 기능 테스트
echo ""
echo "4. OpenAM 기능 테스트"
echo "==================="

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -s -f http://localhost:8080/openam/isAlive.jsp | grep -q "Server is ALIVE"; then
    test_result 0 "OpenAM 서버 상태"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    test_result 1 "OpenAM 서버 상태"
fi

echo ""
echo "=== 검증 결과 요약 ==="
echo "총 테스트: $TOTAL_TESTS"
echo "통과: $PASSED_TESTS"
echo "실패: $((TOTAL_TESTS - PASSED_TESTS))"

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}모든 테스트 통과!${NC}"
    exit 0
else
    echo -e "${RED}일부 테스트 실패.${NC}"
    exit 1
fi
EOF

    # SAML metadata export 스크립트
    cat > scripts/metadata-export.sh << 'EOF'
#!/bin/bash

echo "=== SAML Metadata Export ==="

# 출력 디렉토리 생성
mkdir -p metadata-exports
cd metadata-exports

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
mkdir -p "$TIMESTAMP"
cd "$TIMESTAMP"

echo "Export 디렉토리: metadata-exports/$TIMESTAMP"

# 표준 Metadata export
echo "1. 표준 Metadata export..."
curl -s -o standard-metadata.xml "http://localhost:8080/openam/saml2/jsp/exportmetadata.jsp?entityid=http://localhost:8080/openam&realm=/"

if [ -s "standard-metadata.xml" ]; then
    echo "✓ 표준 Metadata export 성공"
    if xmllint --noout standard-metadata.xml 2>/dev/null; then
        echo "✓ XML 형식 유효"
    else
        echo "✗ XML 형식 오류"
    fi
else
    echo "✗ 표준 Metadata export 실패"
fi

echo ""
echo "=== Export 완료 ==="
echo "위치: $(pwd)"
ls -la

cd ../..
EOF

    # 사용자 로그인 테스트 스크립트
    cat > scripts/user-login-test.sh << 'EOF'
#!/bin/bash

echo "=== LDAP 사용자 OpenAM 로그인 테스트 ==="

users=("testuser1" "testuser2" "admin")
password="Oracle_12345"

for user in "${users[@]}"; do
    echo ""
    echo "사용자 $user 로그인 테스트..."
    
    response=$(curl -s -X POST \
      "http://localhost:8080/openam/json/authenticate" \
      -H "Content-Type: application/json" \
      -H "X-OpenAM-Username: $user" \
      -H "X-OpenAM-Password: $password")
    
    token=$(echo "$response" | grep -o '"tokenId":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$token" ]; then
        echo "✓ $user 로그인 성공"
        echo "  토큰: ${token:0:20}..."
    else
        echo "✗ $user 로그인 실패"
    fi
done

echo ""
echo "=== 테스트 완료 ==="
EOF

    chmod +x scripts/*.sh
    
    log_success "테스트 스크립트 생성 완료"
}

# LDAP 초기 데이터 추가 방법 안내 스크립트 생성
create_ldap_setup_guide() {
    log_info "LDAP 데이터 추가 가이드 생성 중..."
    
    cat > scripts/setup-ldap-data.sh << 'EOF'
#!/bin/bash

echo "=== OpenLDAP 초기 데이터 설정 ==="

# OpenLDAP 컨테이너가 실행 중인지 확인
if ! docker ps | grep -q openldap-server; then
    echo "❌ OpenLDAP 컨테이너가 실행되지 않았습니다."
    echo "먼저 'make up' 명령으로 서비스를 시작하세요."
    exit 1
fi

# OpenLDAP이 완전히 시작될 때까지 대기
echo "OpenLDAP 서비스 준비 상태 확인 중..."
sleep 10  # 초기 대기

for i in {1..30}; do
    if docker-compose exec -T openldap ldapsearch -x -H ldap://localhost -b "dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 >/dev/null 2>&1; then
        echo "✓ OpenLDAP 서비스 준비 완료"
        break
    fi
    echo "대기 중... ($i/30)"
    sleep 3
done

# 데이터가 이미 있는지 확인
echo "기존 데이터 확인 중..."
if docker-compose exec -T openldap ldapsearch -x -H ldap://localhost -b "ou=people,dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 2>/dev/null | grep -q "testuser1"; then
    echo "✓ LDAP 데이터가 이미 존재합니다."
    
    echo ""
    echo "기존 사용자 목록:"
    docker-compose exec -T openldap ldapsearch -x -H ldap://localhost -b "ou=people,dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 "(objectClass=person)" uid 2>/dev/null | grep "^uid:" | head -5
    exit 0
fi

echo "LDAP 초기 데이터 추가 중..."

# 각 LDIF 파일을 순차적으로 추가
for ldif_file in ldap-custom/*.ldif; do
    if [ -f "$ldif_file" ]; then
        echo "추가 중: $ldif_file"
        
        # 파일을 컨테이너로 복사
        docker cp "$ldif_file" openldap-server:/tmp/
        
        # LDAP에 데이터 추가
        filename=$(basename "$ldif_file")
        if docker-compose exec -T openldap ldapadd -x -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 -f "/tmp/$filename" 2>/dev/null; then
            echo "✓ $filename 추가 성공"
        else
            echo "⚠ $filename 추가 실패 (이미 존재하거나 오류)"
        fi
        
        # 임시 파일 정리
        docker-compose exec -T openldap rm -f "/tmp/$filename" 2>/dev/null || true
    fi
done

echo ""
echo "=== 데이터 확인 ==="

# 사용자 확인
echo "추가된 사용자:"
docker-compose exec -T openldap ldapsearch -x -H ldap://localhost -b "ou=people,dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 "(objectClass=person)" uid cn mail 2>/dev/null | grep -E "^(uid|cn|mail):" | head -9

echo ""
echo "추가된 그룹:"
docker-compose exec -T openldap ldapsearch -x -H ldap://localhost -b "ou=groups,dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 "(objectClass=groupOfNames)" cn description 2>/dev/null | grep -E "^(cn|description):" | head -6

echo ""
echo "=== 사용자 인증 테스트 ==="
for user in testuser1 testuser2 admin; do
    if docker-compose exec -T openldap ldapwhoami -x -D "uid=$user,ou=people,dc=oracle,dc=com" -w Oracle_12345 >/dev/null 2>&1; then
        echo "✓ $user 인증 성공"
    else
        echo "✗ $user 인증 실패"
    fi
done

echo ""
echo "✓ LDAP 초기 데이터 설정 완료"
echo ""
echo "다음 단계:"
echo "1. OpenAM 웹 인터페이스에서 LDAP 연동 설정"
echo "2. http://localhost:8080/openam 접속"
echo "3. Custom Configuration 선택"
echo "4. User Data Store에서 External OpenDJ 설정:"
echo "   - Directory Name: ldap://openldap-server:389/dc=oracle,dc=com"
echo "   - Login ID: cn=admin,dc=oracle,dc=com"
echo "   - Password: Oracle_12345"
EOF

    chmod +x scripts/setup-ldap-data.sh
    
    log_success "LDAP 데이터 추가 가이드 생성 완료"
}

# README 파일 생성
create_readme() {
    log_info "README 파일 생성 중..."
    
    cat > README.md << 'EOF'
# Oracle IAM Docker Environment (Simplified)

Oracle Identity and Access Management (IAM) 환경을 Docker로 구성한 프로젝트입니다.

## 구성 요소

- **OpenAM 14.7.2**: Identity Provider (SAML SSO) - 커스텀 빌드
- **OpenLDAP 1.5.0**: Directory Server - 검증된 기본 이미지 사용
- **phpLDAPadmin**: LDAP 웹 관리 도구

## 빠른 시작

```bash
# 1. 환경 설정 및 파일 생성
./setup.sh

# 2. OpenAM 이미지 빌드
make build

# 3. 서비스 시작
make up

# 4. LDAP 초기 데이터 추가 (서비스 시작 후 실행)
./scripts/setup-ldap-data.sh

# 5. 시스템 검증
make test
```

## 접속 정보

### 웹 인터페이스
- **OpenAM**: http://localhost:8080/openam
  - Username: `amadmin`
  - Password: `Oracle_12345`

- **phpLDAPadmin**: http://localhost:8081
  - Login DN: `cn=admin,dc=oracle,dc=com`
  - Password: `Oracle_12345`

### 테스트 사용자
- `testuser1` / `Oracle_12345`
- `testuser2` / `Oracle_12345`
- `admin` / `Oracle_12345`

## 주요 명령어

```bash
# 서비스 관리
make up         # 서비스 시작
make down       # 서비스 중지
make restart    # 서비스 재시작
make logs       # 로그 확인

# 테스트
make test       # 전체 시스템 테스트
make test-login # 사용자 로그인 테스트
make metadata   # SAML metadata export

# 데이터 관리
make backup     # 데이터 백업
make restore    # 데이터 복구
make clean      # 정리
```

## SAML 설정

### Metadata URL
```
http://localhost:8080/openam/saml2/jsp/exportmetadata.jsp?entityid=http://localhost:8080/openam
```

### 주요 엔드포인트
- **Entity ID**: `http://localhost:8080/openam`
- **SSO URL**: `http://localhost:8080/openam/SSORedirect/metaAlias/idp`
- **SLO URL**: `http://localhost:8080/openam/SLORedirect/metaAlias/idp`

## 디렉토리 구조

```
.
├── Dockerfile.openam          # OpenAM 커스텀 이미지
├── docker-compose.yml         # Docker Compose 설정 (OpenLDAP 기본 이미지 사용)
├── Makefile                   # 빌드/관리 명령어
├── setup.sh                   # 자동 설치 스크립트
├── .env                       # 환경 변수
├── scripts/                   # 유틸리티 스크립트
│   ├── system-verification.sh # 시스템 검증
│   ├── setup-ldap-data.sh     # LDAP 초기 데이터 설정
│   ├── metadata-export.sh     # SAML metadata export
│   └── user-login-test.sh     # 로그인 테스트
└── ldap-custom/               # LDAP 초기 데이터 (LDIF 파일)
    ├── 01-oracle-structure.ldif
    ├── 02-oracle-users.ldif
    └── 03-oracle-groups.ldif
```

## 단계별 설치 가이드

### 1. 환경 준비
```bash
# Git 클론 후 (또는 파일 다운로드 후)
cd oracle-iam-docker

# 설치 스크립트 실행
chmod +x setup.sh
./setup.sh
```

### 2. 서비스 시작
```bash
# OpenAM 이미지 빌드 (OpenLDAP은 기본 이미지 사용)
make build

# 모든 서비스 시작
make up

# 서비스 상태 확인
make ps
```

### 3. LDAP 데이터 설정
```bash
# LDAP이 완전히 시작된 후 실행 (약 1-2분 대기)
./scripts/setup-ldap-data.sh
```

### 4. OpenAM 설정
브라우저에서 `http://localhost:8080/openam` 접속하여 초기 설정:

1. **Custom Configuration** 선택
2. **Server Settings**: 기본값 사용
3. **Configuration Data Store**: Embedded OpenDJ, 패스워드 `Oracle_12345`
4. **User Data Store**: External OpenDJ
   - Directory Name: `ldap://openldap-server:389/dc=oracle,dc=com`
   - Login ID: `cn=admin,dc=oracle,dc=com`
   - Password: `Oracle_12345`
5. 설정 완료

### 5. 테스트
```bash
# 전체 시스템 테스트
make test

# 사용자 로그인 테스트
make test-login

# SAML metadata export
make metadata
```

## 문제 해결

### 일반적인 문제

1. **OpenLDAP 연결 실패**
   ```bash
   # LDAP 상태 확인
   make logs-openldap
   
   # 네트워크 연결 확인
   docker-compose exec openam ping openldap-server
   ```

2. **OpenAM 시작 시간 지연**
   ```bash
   # OpenAM 로그 확인 (시작에 2-3분 소요 정상)
   make logs-openam
   ```

3. **LDAP 데이터 추가 실패**
   ```bash
   # 수동으로 데이터 추가
   docker cp ldap-custom/02-oracle-users.ldif openldap-server:/tmp/
   docker-compose exec openldap ldapadd -x -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 -f /tmp/02-oracle-users.ldif
   ```

### 로그 확인
```bash
# 전체 로그
make logs

# 개별 서비스 로그
make logs-openam
make logs-openldap
```

## 특징

✅ **간소화된 구성**: 핵심 서비스만 포함 (OpenLDAP, OpenAM, phpLDAPadmin)  
✅ **검증된 이미지**: OpenLDAP은 검증된 기본 이미지 사용  
✅ **60GB 메모리 최적화**: OpenAM 최대 20GB 할당  
✅ **통일된 패스워드**: Oracle_12345  
✅ **자동화된 설치**: setup.sh 원클릭 설치  
✅ **완전한 SAML SSO** 지원  

## 보안 고려사항

⚠️ **중요**: 이 설정은 개발/테스트 환경용입니다.

프로덕션 환경에서는:
- 모든 기본 패스워드 변경
- HTTPS/LDAPS 강제 사용
- 방화벽 규칙 적용
- 정기적인 보안 업데이트
EOF
    
    log_success "README 파일 생성 완료"
}

# 완료 메시지 출력
print_completion() {
    echo ""
    echo "=============================================="
    echo "  Oracle IAM Docker Environment 설치 완료!"
    echo "=============================================="
    echo ""
    echo "다음 단계:"
    echo "1. make build              # OpenAM 이미지 빌드"
    echo "2. make up                 # 서비스 시작"
    echo "3. ./scripts/setup-ldap-data.sh  # LDAP 데이터 추가"
    echo "4. make test               # 시스템 검증"
    echo ""
    echo "접속 정보:"
    echo "- OpenAM:       http://localhost:8080/openam"
    echo "- phpLDAPadmin: http://localhost:8081"
    echo ""
    echo "로그인 정보:"
    echo "- OpenAM 관리자: amadmin/Oracle_12345"
    echo "- LDAP 관리자:   cn=admin,dc=oracle,dc=com/Oracle_12345"
    echo "- 테스트 사용자: testuser1, testuser2, admin (모두 Oracle_12345)"
    echo ""
    echo "자세한 정보는 README.md 파일을 참조하세요."
    echo ""
}

# 메인 실행 함수
main() {
    print_header
    
    # 옵션 파싱
    SKIP_REQUIREMENTS=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-requirements)
                SKIP_REQUIREMENTS=true
                shift
                ;;
            -h|--help)
                echo "사용법: $0 [옵션]"
                echo ""
                echo "옵션:"
                echo "  --skip-requirements  시스템 요구사항 확인 건너뛰기"
                echo "  -h, --help          도움말 표시"
                exit 0
                ;;
            *)
                log_error "알 수 없는 옵션: $1"
                exit 1
                ;;
        esac
    done
    
    # 단계별 실행
    if [ "$SKIP_REQUIREMENTS" = false ]; then
        check_requirements
    fi
    
    create_directories
    create_openam_dockerfile
    create_env_file
    create_ldif_files
    create_test_scripts
    create_ldap_setup_guide
    create_readme
    
    print_completion
}

# 스크립트 실행
main "$@"

# Nginx 설정 파일 생성
create_nginx_config() {
    log_info "Nginx 설정 파일 생성 중..."
    
    cat > nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml;
    
    include /etc/nginx/conf.d/*.conf;
}
EOF

    cat > nginx/conf.d/oracle-iam.conf << 'EOF'
# Oracle IAM Reverse Proxy Configuration

# OpenAM 업스트림
upstream openam {
    server openam-server:8080;
    keepalive 32;
}

# phpLDAPadmin 업스트림
upstream phpldapadmin {
    server phpldapadmin:80;
    keepalive 16;
}

# HTTP to HTTPS 리다이렉트
server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

# HTTPS 서버
server {
    listen 443 ssl http2;
    server_name _;
    
    # SSL 설정 (자체 서명 인증서 사용)
    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE+AESGCM:ECDHE+AES256:ECDHE+AES128:!aNULL:!MD5:!DSS;
    ssl_prefer_server_ciphers on;
    
    # 보안 헤더
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    
    # OpenAM 프록시
    location /openam {
        proxy_pass http://openam;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    # phpLDAPadmin 프록시
    location /ldapadmin {
        proxy_pass http://phpldapadmin;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # 기본 페이지
    location / {
        return 200 'Oracle IAM Environment';
        add_header Content-Type text/plain;
    }
}
EOF
    
    log_success "Nginx 설정 파일 생성 완료"
}

# README 파일 생성
create_readme() {
    log_info "README 파일 생성 중..."
    
    cat > README.md << 'EOF'
# Oracle IAM Docker Environment

Oracle Identity and Access Management (IAM) 환경을 Docker로 구성한 프로젝트입니다.

## 구성 요소

- **OpenAM 14.7.2**: Identity Provider (SAML SSO)
- **OpenLDAP 1.5.0**: Directory Server
- **phpLDAPadmin**: LDAP 웹 관리 도구
- **Portainer**: Docker 관리 도구
- **Nginx**: 리버스 프록시 (선택사항)

## 빠른 시작

```bash
# 1. 환경 설정
make setup

# 2. 이미지 빌드
make build

# 3. 서비스 시작
make up

# 4. 시스템 검증
make test
```

## 접속 정보

### 웹 인터페이스
- **OpenAM**: http://localhost:8080/openam
  - Username: `amadmin`
  - Password: `Oracle_12345`

- **phpLDAPadmin**: http://localhost:8081
  - Login DN: `cn=admin,dc=oracle,dc=com`
  - Password: `Oracle_12345`

- **Portainer**: http://localhost:9000

### 테스트 사용자
- `testuser1` / `Oracle_12345`
- `testuser2` / `Oracle_12345`
- `admin` / `Oracle_12345`

## 주요 명령어

```bash
# 서비스 관리
make up         # 서비스 시작
make down       # 서비스 중지
make restart    # 서비스 재시작
make logs       # 로그 확인

# 테스트
make test       # 전체 시스템 테스트
make test-login # 사용자 로그인 테스트
make metadata   # SAML metadata export

# 데이터 관리
make backup     # 데이터 백업
make restore    # 데이터 복구
make clean      # 정리

# 개발/운영
make dev        # 개발 환경
make prod       # 프로덕션 환경 (Nginx 포함)
```

## SAML 설정

### Metadata URL
```
http://localhost:8080/openam/saml2/jsp/exportmetadata.jsp?entityid=http://localhost:8080/openam
```

### 주요 엔드포인트
- **Entity ID**: `http://localhost:8080/openam`
- **SSO URL**: `http://localhost:8080/openam/SSORedirect/metaAlias/idp`
- **SLO URL**: `http://localhost:8080/openam/SLORedirect/metaAlias/idp`

## 디렉토리 구조

```
.
├── Dockerfile.openam          # OpenAM Docker 이미지
├── Dockerfile.openldap        # OpenLDAP Docker 이미지
├── docker-compose.yml         # Docker Compose 설정
├── Makefile                   # 빌드/관리 명령어
├── .env                       # 환경 변수
├── data/                      # 데이터 볼륨
├── logs/                      # 로그 파일
├── backup/                    # 백업 데이터
├── scripts/                   # 유틸리티 스크립트
├── ldap-custom/              # LDAP 초기 데이터
├── openam-custom/            # OpenAM 커스텀 설정
└── nginx/                    # Nginx 설정
```

## 문제 해결

### 일반적인 문제

1. **포트 충돌**
   ```bash
   # 사용 중인 포트 확인
   netstat -tuln | grep -E ':(389|8080|8081)'
   ```

2. **메모리 부족**
   ```bash
   # 메모리 사용량 확인
   free -h
   docker stats
   ```

3. **컨테이너 시작 실패**
   ```bash
   # 로그 확인
   make logs
   docker-compose logs [service-name]
   ```

### 로그 확인

```bash
# 전체 로그
make logs

# 개별 서비스 로그
make logs-openam
make logs-openldap

# 실시간 모니터링
docker stats
```

## 보안 고려사항

⚠️ **중요**: 이 설정은 개발/테스트 환경용입니다.

프로덕션 환경에서는:
- 모든 기본 패스워드 변경
- HTTPS/LDAPS 강제 사용
- 방화벽 규칙 적용
- 정기적인 보안 업데이트

## 라이센스

이 프로젝트는 교육 및 개발 목적으로 제공됩니다.
EOF
    
    log_success "README 파일 생성 완료"
}

# 완료 메시지 출력
print_completion() {
    echo ""
    echo "=============================================="
    echo "  Oracle IAM Docker Environment 설치 완료!"
    echo "=============================================="
    echo ""
    echo "다음 단계:"
    echo "1. make build    # Docker 이미지 빌드"
    echo "2. make up       # 서비스 시작"
    echo "3. make test     # 시스템 검증"
    echo ""
    echo "접속 정보:"
    echo "- OpenAM:       http://localhost:8080/openam"
    echo "- phpLDAPadmin: http://localhost:8081"
    echo "- Portainer:    http://localhost:9000"
    echo ""
    echo "사용자: amadmin/Oracle_12345 (OpenAM)"
    echo "      cn=admin,dc=oracle,dc=com/Oracle_12345 (LDAP)"
    echo ""
    echo "자세한 정보는 README.md 파일을 참조하세요."
    echo ""
}

# 메인 실행 함수
main() {
    print_header
    
    # 옵션 파싱
    SKIP_REQUIREMENTS=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-requirements)
                SKIP_REQUIREMENTS=true
                shift
                ;;
            -h|--help)
                echo "사용법: $0 [옵션]"
                echo ""
                echo "옵션:"
                echo "  --skip-requirements  시스템 요구사항 확인 건너뛰기"
                echo "  -h, --help          도움말 표시"
                exit 0
                ;;
            *)
                log_error "알 수 없는 옵션: $1"
                exit 1
                ;;
        esac
    done
    
    # 단계별 실행
    if [ "$SKIP_REQUIREMENTS" = false ]; then
        check_requirements
    fi
    
    create_directories
    create_docker_files
    create_env_file
    create_ldif_files
    create_test_scripts
    create_nginx_config
    create_readme
    
    print_completion
}

# 스크립트 실행
main "$@"001

# 테스트 사용자 1
dn: uid=testuser1,ou=people,dc=oracle,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: testuser1
sn: User
givenName: Test
cn: Test User One
displayName: Test User One
uidNumber: 1002
gidNumber: 1002
userPassword: Oracle_12345
gecos: Test User One
loginShell: /bin/bash
homeDirectory: /home/testuser1
mail: testuser1@oracle.com
telephoneNumber: +1-555-0