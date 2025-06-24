#!/bin/bash
# Oracle Linux에서 Docker, Docker Compose 설치 및 OpenLDAP 설정 스크립트
# 실행 방법: sudo bash setup-oracle-linux.sh

set -e

echo "===== Oracle Linux에서 OpenLDAP 설치 스크립트 시작 ====="

# 시스템 업데이트
echo "시스템 업데이트 중..."
dnf update -y

# 필요한 패키지 설치
echo "필요한 패키지 설치 중..."
dnf install -y dnf-utils zip unzip curl wget net-tools yum-utils device-mapper-persistent-data lvm2 epel-release

# Docker 저장소 추가
echo "Docker 저장소 추가 중..."
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

# Docker 설치
echo "Docker 설치 중..."
dnf install -y docker-ce docker-ce-cli containerd.io

# Docker 서비스 시작 및 자동 시작 설정
echo "Docker 서비스 시작 및 자동 시작 설정 중..."
systemctl start docker
systemctl enable docker

# 현재 사용자를 docker 그룹에 추가
echo "현재 사용자를 docker 그룹에 추가 중..."
usermod -aG docker $USER

# Docker Compose 설치
echo "Docker Compose 설치 중..."
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Docker Compose 버전 확인
echo "Docker Compose 버전 확인 중..."
docker-compose --version

# OpenLDAP 디렉토리 구조 생성
echo "OpenLDAP 디렉토리 구조 생성 중..."
mkdir -p ldap/{certs,config,data}

# Certbot 설치
echo "Certbot 설치 중..."
dnf install -y certbot

# Let's Encrypt 인증서 발급 (80 포트가 열려있어야 함)
echo "Let's Encrypt 인증서 발급 중..."
certbot certonly --standalone -d ldapv3-idp.duckdns.org --agree-tos --email admin@example.com --non-interactive

# 인증서 파일을 OpenLDAP에서 사용할 위치로 복사
echo "인증서 파일 복사 중..."
cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/fullchain.pem ldap/certs/ldap.crt
cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/privkey.pem ldap/certs/ldap.key
cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/chain.pem ldap/certs/ca.crt

# dhparam 파일 생성
echo "dhparam 파일 생성 중..."
openssl dhparam -out ldap/certs/dhparam.pem 2048

# 적절한 권한 설정
echo "인증서 권한 설정 중..."
chmod 600 ldap/certs/ldap.key
chmod 644 ldap/certs/ldap.crt ldap/certs/ca.crt

# 인증서 자동 갱신을 위한 cron 작업 추가
echo "인증서 자동 갱신 cron 작업 추가 중..."
CERT_RENEWAL="0 0 1 * * root certbot renew --quiet && cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/fullchain.pem $(pwd)/ldap/certs/ldap.crt && cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/privkey.pem $(pwd)/ldap/certs/ldap.key && cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/chain.pem $(pwd)/ldap/certs/ca.crt && docker-compose -f $(pwd)/ldap/docker-compose.yml restart openldap"
echo "$CERT_RENEWAL" >> /etc/crontab

# Dockerfile 생성
echo "Dockerfile 생성 중..."
cat > ldap/Dockerfile << 'EOF'
FROM debian:bullseye-slim

# 설치 중 대화형 프롬프트 방지
ENV DEBIAN_FRONTEND=noninteractive

# OpenLDAP 및 필요한 종속성 설치
RUN apt-get update && apt-get install -y \
    slapd \
    ldap-utils \
    openssl \
    ca-certificates \
    libsasl2-modules \
    libsasl2-modules-ldap \
    libsasl2-modules-sql \
    libsasl2-modules-gssapi-mit \
    krb5-user \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 필요한 디렉토리 생성
RUN mkdir -p /var/lib/ldap /etc/ldap/slapd.d /var/run/slapd /container/service/slapd/assets/config/bootstrap/ldif/custom

# 적절한 권한 설정
RUN chown -R openldap:openldap /var/lib/ldap /etc/ldap/slapd.d /var/run/slapd

# 엔트리포인트 스크립트 복사
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# LDAP 포트 노출
EXPOSE 389 636

# 환경 변수 설정
ENV LDAP_ORGANISATION="LDAPv3 Organization" \
    LDAP_DOMAIN="duckdns.org" \
    LDAP_ADMIN_PASSWORD="admin" \
    LDAP_CONFIG_PASSWORD="config" \
    LDAP_TLS=true \
    LDAP_TLS_CRT_FILENAME="ldap.crt" \
    LDAP_TLS_KEY_FILENAME="ldap.key" \
    LDAP_TLS_CA_CRT_FILENAME="ca.crt" \
    LDAP_TLS_VERIFY_CLIENT="try"

# 엔트리포인트 설정
ENTRYPOINT ["/entrypoint.sh"]

# 기본 명령어
CMD ["slapd", "-d", "256", "-h", "ldap:/// ldaps:/// ldapi:///", "-F", "/etc/ldap/slapd.d"]
EOF

# entrypoint.sh 생성
echo "entrypoint.sh 생성 중..."
cat > ldap/entrypoint.sh << 'EOF'
#!/bin/bash
set -e

# SSHA 비밀번호 해시를 생성하는 함수
generate_password_hash() {
    local password=$1
    local hash=$(slappasswd -s "$password")
    echo "$hash"
}

# SSL/TLS 인증서 설정
setup_ssl() {
    if [ "$LDAP_TLS" = "true" ]; then
        echo "TLS/SSL 설정 중..."
        
        # 인증서가 존재하는지 확인
        if [ ! -f "/etc/ssl/certs/$LDAP_TLS_CRT_FILENAME" ] || [ ! -f "/etc/ssl/certs/$LDAP_TLS_KEY_FILENAME" ]; then
            echo "오류: TLS 인증서를 찾을 수 없습니다!"
            exit 1
        fi
        
        # slapd에서 TLS 구성
        cat > /etc/ldap/ssl.ldif << EOF
dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ssl/certs/$LDAP_TLS_CA_CRT_FILENAME
-
add: olcTLSCertificateFile
olcTLSCertificateFile: /etc/ssl/certs/$LDAP_TLS_CRT_FILENAME
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/ssl/certs/$LDAP_TLS_KEY_FILENAME
-
add: olcTLSVerifyClient
olcTLSVerifyClient: $LDAP_TLS_VERIFY_CLIENT
EOF
    fi
}

# 초기화되지 않은 경우 OpenLDAP 초기화
initialize_ldap() {
    # slapd.d가 비어 있는지 확인
    if [ -z "$(ls -A /etc/ldap/slapd.d)" ]; then
        echo "OpenLDAP 초기화 중..."
        
        # 구성 생성
        cat > /tmp/slapd.conf << EOF
# 스키마 파일 포함
include /etc/ldap/schema/core.schema
include /etc/ldap/schema/cosine.schema
include /etc/ldap/schema/nis.schema
include /etc/ldap/schema/inetorgperson.schema

# 전역 매개변수 정의
pidfile /var/run/slapd/slapd.pid
argsfile /var/run/slapd/slapd.args

# TLS 설정
TLSCACertificateFile /etc/ssl/certs/$LDAP_TLS_CA_CRT_FILENAME
TLSCertificateFile /etc/ssl/certs/$LDAP_TLS_CRT_FILENAME
TLSCertificateKeyFile /etc/ssl/certs/$LDAP_TLS_KEY_FILENAME
TLSCipherSuite HIGH:!SSLv3:!SSLv2:!TLSv1
TLSProtocolMin 3.2

# 데이터베이스 정의
database mdb
maxsize 1073741824
suffix "dc=$LDAP_DOMAIN_COMPONENT,dc=$LDAP_DOMAIN_TLD"
rootdn "cn=admin,dc=$LDAP_DOMAIN_COMPONENT,dc=$LDAP_DOMAIN_TLD"
rootpw $(generate_password_hash "$LDAP_ADMIN_PASSWORD")
directory /var/lib/ldap
index objectClass eq
EOF

        # 도메인 구성요소 추출
        IFS='.' read -ra DOMAIN_PARTS <<< "$LDAP_DOMAIN"
        export LDAP_DOMAIN_COMPONENT=${DOMAIN_PARTS[0]}
        export LDAP_DOMAIN_TLD=${DOMAIN_PARTS[1]}
        
        # slapd.conf를 slapd.d 형식으로 변환
        mkdir -p /etc/ldap/slapd.d
        slaptest -f /tmp/slapd.conf -F /etc/ldap/slapd.d
        
        # 적절한 소유권 설정
        chown -R openldap:openldap /etc/ldap/slapd.d /var/lib/ldap
        
        # TLS 구성이 활성화된 경우 적용
        if [ "$LDAP_TLS" = "true" ]; then
            slapadd -n 0 -F /etc/ldap/slapd.d -l /etc/ldap/ssl.ldif
        fi
        
        # 초기 LDIF가 존재하는 경우 가져오기
        if [ -f "/container/service/slapd/assets/config/bootstrap/ldif/custom/init.ldif" ]; then
            echo "초기 LDIF 데이터 가져오는 중..."
            # LDIF의 도메인 플레이스홀더 교체
            sed -i "s/dc=duckdns,dc=org/dc=$LDAP_DOMAIN_COMPONENT,dc=$LDAP_DOMAIN_TLD/g" \
                /container/service/slapd/assets/config/bootstrap/ldif/custom/init.ldif
            
            # 데이터 가져오기를 위해 slapd 임시 시작
            slapd -h "ldapi:///" -F /etc/ldap/slapd.d
            sleep 2
            
            # 데이터 가져오기
            ldapadd -Y EXTERNAL -H ldapi:/// -f /container/service/slapd/assets/config/bootstrap/ldif/custom/init.ldif
            
            # slapd 중지
            kill $(cat /var/run/slapd/slapd.pid)
            sleep 1
        fi
    fi
}

# Main execution
setup_ssl
initialize_ldap

# Start slapd in foreground
echo "OpenLDAP 서버 시작 중..."
exec "$@"
EOF

# init.ldif 생성
echo "init.ldif 생성 중..."
cat > ldap/init.ldif << 'EOF'
# 기본 조직
dn: dc=duckdns,dc=org
objectClass: dcObject
objectClass: organization
dc: duckdns
o: LDAPv3 Organization
description: LDAP LDAPv3 Organization

# 관리자 사용자
dn: cn=admin,dc=duckdns,dc=org
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
description: LDAP Administrator
userPassword: {SSHA}xxxxxxxxxxxxxxxxxxxxxxxx

# 그룹 조직 단위
dn: ou=groups,dc=duckdns,dc=org
objectClass: organizationalUnit
ou: groups
description: Groups branch

# 사용자 조직 단위
dn: ou=users,dc=duckdns,dc=org
objectClass: organizationalUnit
ou: users
description: Users branch

# 예제 사용자
dn: uid=user1,ou=users,dc=duckdns,dc=org
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: user1
sn: User
givenName: Test
cn: Test User
displayName: Test User
uidNumber: 10000
gidNumber: 10000
userPassword: {SSHA}xxxxxxxxxxxxxxxxxxxxxxxx
gecos: Test User
loginShell: /bin/bash
homeDirectory: /home/user1
shadowExpire: -1
shadowFlag: 0
shadowWarning: 7
shadowMin: 0
shadowMax: 99999
shadowLastChange: 0
mail: user1@example.com
EOF

# docker-compose.yml 생성
echo "docker-compose.yml 생성 중..."
cat > ldap/docker-compose.yml << 'EOF'
version: '3.8'

services:
  openldap:
    build: .
    container_name: openldap
    environment:
      - LDAP_ORGANISATION=LDAPv3 Organization
      - LDAP_DOMAIN=duckdns.org
      - LDAP_ADMIN_PASSWORD=admin_password
      - LDAP_CONFIG_PASSWORD=config_password
      - LDAP_TLS=true
      - LDAP_TLS_CRT_FILENAME=ldap.crt
      - LDAP_TLS_KEY_FILENAME=ldap.key
      - LDAP_TLS_CA_CRT_FILENAME=ca.crt
      - LDAP_TLS_VERIFY_CLIENT=try
    ports:
      - "389:389"   # LDAP
      - "636:636"   # LDAPS (LDAP over SSL 암호화)
    volumes:
      - ./data:/var/lib/ldap
      - ./config:/etc/ldap/slapd.d
      - ./certs:/etc/ssl/certs
      - ./init.ldif:/container/service/slapd/assets/config/bootstrap/ldif/custom/init.ldif
    networks:
      ldap_network:
        ipv4_address: 158.180.82.84
    restart: unless-stopped

networks:
  ldap_network:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 158.180.82.0/24
          gateway: 158.180.82.1
EOF

# 실행 권한 설정
chmod +x ldap/entrypoint.sh

# 비밀번호 해시 생성 및 설정
echo "비밀번호 해시 생성 중..."
apt-get update && apt-get install -y slapd ldap-utils || dnf install -y openldap-servers openldap-clients
ADMIN_HASH=$(slappasswd -s admin_password)
USER_HASH=$(slappasswd -s user_password)

# 해시 값 설정
sed -i "s|{SSHA}xxxxxxxxxxxxxxxxxxxxxxxx|$ADMIN_HASH|g" ldap/init.ldif
sed -i "0,/{SSHA}xxxxxxxxxxxxxxxxxxxxxxxx/{s/{SSHA}xxxxxxxxxxxxxxxxxxxxxxxx/$USER_HASH/}" ldap/init.ldif

echo "OpenLDAP 서버 시작 중..."
cd ldap
docker-compose up -d

echo "===== OpenLDAP 설치 완료 ====="
echo "LDAP 서버가 시작되었습니다."
echo "관리자 DN: cn=admin,dc=duckdns,dc=org"
echo "관리자 비밀번호: admin_password"
echo "LDAP URL: ldap://158.180.82.84:389"
echo "LDAPS URL: ldaps://158.180.82.84:636"
echo "FQDN URL: ldaps://ldapv3-idp.duckdns.org:636"

echo "LDAP 연결 테스트 방법:"
echo "ldapsearch -x -H ldap://158.180.82.84:389 -b \"dc=duckdns,dc=org\" -D \"cn=admin,dc=duckdns,dc=org\" -w admin_password"
echo "ldapsearch -x -H ldaps://158.180.82.84:636 -b \"dc=duckdns,dc=org\" -D \"cn=admin,dc=duckdns,dc=org\" -w admin_password -ZZ"
echo "ldapsearch -x -H ldaps://ldapv3-idp.duckdns.org:636 -b \"dc=duckdns,dc=org\" -D \"cn=admin,dc=duckdns,dc=org\" -w admin_password -ZZ"
