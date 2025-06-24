# SSL/TLS 인증서 생성 및 설정 가이드 (Let's Encrypt)

## 개요
이 문서는 OCI IDCS SSO 플랫폼에서 Let's Encrypt를 사용한 SSL/TLS 인증서 생성 및 설정 방법을 안내합니다.
외부 LDAP 서버 `ldapv3-idp.duckdns.org` (158.180.82.84)와의 보안 연결을 위한 인증서 설정을 포함합니다.

## 📋 목차
- [Let's Encrypt 인증서 발급](#lets-encrypt-인증서-발급)
- [DuckDNS 도메인 인증서](#duckdns-도메인-인증서)
- [자동 갱신 설정](#자동-갱신-설정)
- [인증서 검증](#인증서-검증)
- [트러블슈팅](#트러블슈팅)

## 🔧 Let's Encrypt 인증서 발급

### 1. Certbot 설치

```bash
#!/bin/bash
# Certbot 설치 스크립트

# Ubuntu/Debian 시스템
if command -v apt-get &> /dev/null; then
    echo "Ubuntu/Debian 시스템에서 Certbot 설치..."
    sudo apt update
    sudo apt install -y certbot python3-certbot-nginx python3-certbot-dns-cloudflare
    
# CentOS/RHEL/Rocky Linux 시스템
elif command -v yum &> /dev/null; then
    echo "CentOS/RHEL 시스템에서 Certbot 설치..."
    sudo yum install -y epel-release
    sudo yum install -y certbot python3-certbot-nginx python3-certbot-dns-cloudflare
    
# Fedora 시스템
elif command -v dnf &> /dev/null; then
    echo "Fedora 시스템에서 Certbot 설치..."
    sudo dnf install -y certbot python3-certbot-nginx python3-certbot-dns-cloudflare
    
else
    echo "지원하지 않는 시스템입니다."
    exit 1
fi

# Snap을 통한 최신 버전 설치 (권장)
if command -v snap &> /dev/null; then
    echo "Snap을 통한 최신 Certbot 설치..."
    sudo snap install core; sudo snap refresh core
    sudo snap install --classic certbot
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot
fi

echo "Certbot 설치 완료!"
certbot --version
```

### 2. DuckDNS 도메인 인증서 발급

```bash
#!/bin/bash
# DuckDNS 도메인용 Let's Encrypt 인증서 발급

DOMAIN="ldapv3-idp.duckdns.org"
EMAIL="admin@ldapv3-idp.duckdns.org"
PROJECT_ROOT="/path/to/oci-idcs-sso-platform"

# SSL 디렉토리 생성
mkdir -p $PROJECT_ROOT/ssl

echo "DuckDNS 도메인 $DOMAIN 용 인증서 발급 시작..."

# 방법 1: Standalone 방식 (80/443 포트 사용)
# 주의: 웹서버가 실행 중이면 먼저 중지해야 함
echo "기존 웹서버 중지..."
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl stop apache2 2>/dev/null || true
docker-compose down 2>/dev/null || true

# Let's Encrypt 인증서 발급
sudo certbot certonly \
    --standalone \
    --preferred-challenges http \
    -d $DOMAIN \
    --email $EMAIL \
    --agree-tos \
    --non-interactive \
    --expand

# 방법 2: DNS Challenge 방식 (DuckDNS API 사용)
# DuckDNS 토큰이 필요합니다
read -p "DuckDNS 토큰을 입력하세요: " DUCKDNS_TOKEN

# DNS Challenge 스크립트 생성
cat > /tmp/duckdns-auth.sh << EOF
#!/bin/bash
curl -s "https://www.duckdns.org/update?domains=ldapv3-idp&token=$DUCKDNS_TOKEN&txt=\$CERTBOT_VALIDATION"
sleep 30
EOF

cat > /tmp/duckdns-cleanup.sh << EOF
#!/bin/bash
curl -s "https://www.duckdns.org/update?domains=ldapv3-idp&token=$DUCKDNS_TOKEN&txt=removed&clear=true"
EOF

chmod +x /tmp/duckdns-*.sh

# DNS Challenge로 인증서 발급
sudo certbot certonly \
    --manual \
    --preferred-challenges dns \
    --manual-auth-hook /tmp/duckdns-auth.sh \
    --manual-cleanup-hook /tmp/duckdns-cleanup.sh \
    -d $DOMAIN \
    --email $EMAIL \
    --agree-tos \
    --non-interactive

echo "인증서 발급 완료!"
```

### 3. 인증서 파일 복사 및 설정

```bash
#!/bin/bash
# Let's Encrypt 인증서를 프로젝트로 복사

DOMAIN="ldapv3-idp.duckdns.org"
PROJECT_ROOT="/path/to/oci-idcs-sso-platform"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

echo "Let's Encrypt 인증서를 프로젝트로 복사..."

# 인증서 파일 복사
sudo cp $CERT_PATH/fullchain.pem $PROJECT_ROOT/ssl/server.crt
sudo cp $CERT_PATH/privkey.pem $PROJECT_ROOT/ssl/server.key
sudo cp $CERT_PATH/chain.pem $PROJECT_ROOT/ssl/ca.crt

# LDAP 전용 인증서 (동일한 인증서 사용)
sudo cp $CERT_PATH/fullchain.pem $PROJECT_ROOT/ssl/ldap.crt
sudo cp $CERT_PATH/privkey.pem $PROJECT_ROOT/ssl/ldap.key

# SAML 서명용 인증서 생성 (별도)
openssl genrsa -out $PROJECT_ROOT/ssl/saml_private_key.pem 2048
openssl req -new -x509 -key $PROJECT_ROOT/ssl/saml_private_key.pem \
    -out $PROJECT_ROOT/ssl/saml_certificate.pem -days 365 \
    -subj "/C=KR/ST=Seoul/L=Seoul/O=SSO Platform/OU=SAML Services/CN=sso.ldapv3-idp.duckdns.org"

# 권한 설정
sudo chown $USER:$USER $PROJECT_ROOT/ssl/*
chmod 600 $PROJECT_ROOT/ssl/*.key $PROJECT_ROOT/ssl/*.pem
chmod 644 $PROJECT_ROOT/ssl/*.crt

echo "인증서 복사 및 권한 설정 완료!"

# 인증서 정보 확인
echo "인증서 정보:"
openssl x509 -in $PROJECT_ROOT/ssl/server.crt -text -noout | grep -E "(Subject:|DNS:|IP Address:)"
```

## 🔄 자동 갱신 설정

### 1. 갱신 스크립트 생성

```bash
#!/bin/bash
# Let's Encrypt 인증서 자동 갱신 스크립트

cat > /usr/local/bin/renew-letsencrypt-certs.sh << 'EOF'
#!/bin/bash
# Let's Encrypt 인증서 자동 갱신 및 배포 스크립트

DOMAIN="ldapv3-idp.duckdns.org"
PROJECT_ROOT="/path/to/oci-idcs-sso-platform"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
LOG_FILE="/var/log/letsencrypt-renewal.log"

echo "$(date): 인증서 갱신 시작" >> $LOG_FILE

# 기존 서비스 중지
echo "$(date): 서비스 중지" >> $LOG_FILE
cd $PROJECT_ROOT
docker-compose down

# 인증서 갱신 시도
echo "$(date): 인증서 갱신 시도" >> $LOG_FILE
certbot renew --quiet --deploy-hook "systemctl reload nginx" >> $LOG_FILE 2>&1

if [ $? -eq 0 ]; then
    echo "$(date): 인증서 갱신 성공" >> $LOG_FILE
    
    # 새 인증서 복사
    cp $CERT_PATH/fullchain.pem $PROJECT_ROOT/ssl/server.crt
    cp $CERT_PATH/privkey.pem $PROJECT_ROOT/ssl/server.key
    cp $CERT_PATH/chain.pem $PROJECT_ROOT/ssl/ca.crt
    cp $CERT_PATH/fullchain.pem $PROJECT_ROOT/ssl/ldap.crt
    cp $CERT_PATH/privkey.pem $PROJECT_ROOT/ssl/ldap.key
    
    # 권한 설정
    chown $USER:$USER $PROJECT_ROOT/ssl/*
    chmod 600 $PROJECT_ROOT/ssl/*.key
    chmod 644 $PROJECT_ROOT/ssl/*.crt
    
    echo "$(date): 인증서 복사 완료" >> $LOG_FILE
else
    echo "$(date): 인증서 갱신 실패" >> $LOG_FILE
fi

# 서비스 재시작
echo "$(date): 서비스 재시작" >> $LOG_FILE
docker-compose up -d

echo "$(date): 인증서 갱신 프로세스 완료" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE
EOF

chmod +x /usr/local/bin/renew-letsencrypt-certs.sh
```

### 2. Cron 작업 설정

```bash
#!/bin/bash
# Cron 작업으로 자동 갱신 설정

echo "Cron 작업 설정..."

# 매월 1일 오전 3시에 갱신 시도
(crontab -l 2>/dev/null; echo "0 3 1 * * /usr/local/bin/renew-letsencrypt-certs.sh") | crontab -

# 또는 systemd timer 사용 (권장)
cat > /etc/systemd/system/letsencrypt-renewal.service << 'EOF'
[Unit]
Description=Let's Encrypt certificate renewal
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/renew-letsencrypt-certs.sh
User=root
EOF

cat > /etc/systemd/system/letsencrypt-renewal.timer << 'EOF'
[Unit]
Description=Run Let's Encrypt certificate renewal monthly
Requires=letsencrypt-renewal.service

[Timer]
OnCalendar=monthly
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

# Systemd timer 활성화
sudo systemctl daemon-reload
sudo systemctl enable letsencrypt-renewal.timer
sudo systemctl start letsencrypt-renewal.timer

echo "자동 갱신 설정 완료!"
echo "타이머 상태 확인: systemctl status letsencrypt-renewal.timer"
```

## ✅ 인증서 검증

### 1. 인증서 유효성 검증 스크립트

```bash
#!/bin/bash
# 인증서 유효성 검증

PROJECT_ROOT="/path/to/oci-idcs-sso-platform"
DOMAIN="ldapv3-idp.duckdns.org"

echo "=== 인증서 검증 시작 ==="

# 1. 인증서 파일 존재 확인
echo "1. 인증서 파일 존재 확인..."
for file in server.crt server.key ca.crt ldap.crt ldap.key; do
    if [ -f "$PROJECT_ROOT/ssl/$file" ]; then
        echo "✓ $file 존재"
    else
        echo "✗ $file 없음"
    fi
done

# 2. 인증서 만료일 확인
echo -e "\n2. 인증서 만료일 확인..."
openssl x509 -in $PROJECT_ROOT/ssl/server.crt -noout -dates
echo "현재 날짜: $(date)"

# 3. 인증서 도메인 확인
echo -e "\n3. 인증서 도메인 확인..."
openssl x509 -in $PROJECT_ROOT/ssl/server.crt -noout -text | grep -A 5 "Subject Alternative Name"

# 4. 개인 키와 인증서 매칭 확인
echo -e "\n4. 개인 키와 인증서 매칭 확인..."
CERT_MD5=$(openssl x509 -noout -modulus -in $PROJECT_ROOT/ssl/server.crt | openssl md5)
KEY_MD5=$(openssl rsa -noout -modulus -in $PROJECT_ROOT/ssl/server.key | openssl md5)

if [ "$CERT_MD5" = "$KEY_MD5" ]; then
    echo "✓ 개인 키와 인증서가 매칭됨"
else
    echo "✗ 개인 키와 인증서가 매칭되지 않음"
fi

# 5. LDAP 서버 SSL 연결 테스트
echo -e "\n5. LDAP 서버 SSL 연결 테스트..."
openssl s_client -connect ldapv3-idp.duckdns.org:636 -servername ldapv3-idp.duckdns.org < /dev/null

# 6. 웹서버 SSL 테스트
echo -e "\n6. 웹서버 SSL 테스트..."
curl -I https://$DOMAIN --max-time 10

echo -e "\n=== 인증서 검증 완료 ==="
```

### 2. SSL Labs 테스트

```bash
#!/bin/bash
# SSL Labs 온라인 테스트

DOMAIN="ldapv3-idp.duckdns.org"

echo "SSL Labs 테스트 URL:"
echo "https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"

echo -e "\nCertificate Transparency 로그 확인:"
echo "https://crt.sh/?q=$DOMAIN"

echo -e "\n수동 OpenSSL 테스트:"
echo "openssl s_client -connect $DOMAIN:443 -servername $DOMAIN"
```

## 🔧 트러블슈팅

### 1. 일반적인 문제 해결

```bash
#!/bin/bash
# 일반적인 Let's Encrypt 문제 해결

echo "=== Let's Encrypt 트러블슈팅 ==="

# 1. Certbot 버전 확인
echo "1. Certbot 버전:"
certbot --version

# 2. 인증서 목록 확인
echo -e "\n2. 발급된 인증서 목록:"
sudo certbot certificates

# 3. 로그 확인
echo -e "\n3. 최근 Certbot 로그:"
sudo tail -20 /var/log/letsencrypt/letsencrypt.log

# 4. DNS 레코드 확인
echo -e "\n4. DNS 레코드 확인:"
nslookup ldapv3-idp.duckdns.org
dig ldapv3-idp.duckdns.org

# 5. 포트 접근성 확인
echo -e "\n5. 포트 접근성 확인:"
nc -zv ldapv3-idp.duckdns.org 80
nc -zv ldapv3-idp.duckdns.org 443

# 6. Rate Limit 확인
echo -e "\n6. Let's Encrypt Rate Limit 확인:"
echo "https://letsencrypt.org/docs/rate-limits/"
echo "주간 한도: 같은 도메인에 대해 주당 50개 인증서"
echo "갱신 한도: 주당 5회 갱신 시도"
```

### 2. 수동 갱신 방법

```bash
#!/bin/bash
# 수동 인증서 갱신

DOMAIN="ldapv3-idp.duckdns.org"

echo "수동 인증서 갱신 시작..."

# 1. 기존 서비스 중지
docker-compose down

# 2. 수동 갱신
sudo certbot renew --cert-name $DOMAIN --force-renewal

# 3. 인증서 복사
./scripts/copy-certificates.sh

# 4. 서비스 재시작
docker-compose up -d

echo "수동 갱신 완료!"
```

### 3. 백업 및 복구

```bash
#!/bin/bash
# Let's Encrypt 인증서 백업 및 복구

BACKUP_DIR="/backup/letsencrypt"
DOMAIN="ldapv3-idp.duckdns.org"

# 백업
backup_certificates() {
    echo "인증서 백업 시작..."
    mkdir -p $BACKUP_DIR
    sudo tar -czf $BACKUP_DIR/letsencrypt-backup-$(date +%Y%m%d).tar.gz /etc/letsencrypt/
    echo "백업 완료: $BACKUP_DIR/letsencrypt-backup-$(date +%Y%m%d).tar.gz"
}

# 복구
restore_certificates() {
    if [ -z "$1" ]; then
        echo "사용법: restore_certificates <백업파일>"
        return 1
    fi
    
    echo "인증서 복구 시작..."
    sudo tar -xzf $1 -C /
    sudo systemctl restart certbot.timer
    echo "복구 완료"
}

# 실행
case "$1" in
    backup)
        backup_certificates
        ;;
    restore)
        restore_certificates $2
        ;;
    *)
        echo "사용법: $0 {backup|restore <파일>}"
        ;;
esac
```

## 📋 체크리스트

### 인증서 설정 완료 체크리스트

- [ ] Certbot 설치 완료
- [ ] DuckDNS 도메인 인증서 발급 완료
- [ ] 인증서 파일 프로젝트 디렉토리 복사 완료
- [ ] 파일 권한 설정 완료 (600 for keys, 644 for certs)
- [ ] 자동 갱신 스크립트 설정 완료
- [ ] Cron/Systemd 타이머 설정 완료
- [ ] LDAP SSL 연결 테스트 통과
- [ ] 웹서버 HTTPS 연결 테스트 통과
- [ ] 인증서 만료일 확인 (90일 이내)
- [ ] SSL Labs 테스트 A+ 등급
- [ ] 백업 스크립트 설정 완료

이제 Let's Encrypt를 사용한 무료 SSL 인증서로 안전한 LDAP 및 웹 서비스 연결이 가능합니다!AP 서버 전용 인증서 생성

# LDAP 서버용 개인 키 생성
openssl genrsa -out ssl/ldap-server.key 2048

# LDAP 서버용 CSR 생성
openssl req -new -key ssl/ldap-server.key -out ssl/ldap-server.csr -config <(
cat <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=KR
ST=Seoul
L=Seoul
O=LDAP Directory Services
OU=Directory Services
CN=ldapv3-idp.duckdns.org

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ldapv3-idp.duckdns.org
DNS.2 = *.duckdns.org
IP.1 = 158.180.82.84
EOF
)

# LDAP 서버용 자체 서명 인증서 생성
openssl x509 -req -in ssl/ldap-server.csr -signkey ssl/ldap-server.key \
  -out ssl/ldap-server.crt -days 365 -extensions v3_req -extfile <(
cat <<EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ldapv3-idp.duckdns.org
DNS.2 = *.duckdns.org
IP.1 = 158.180.82.84
EOF
)

# LDAP 클라이언트 인증서 생성 (상호 인증용)
openssl genrsa -out ssl/ldap-client.key 2048
openssl req -new -key ssl/ldap-client.key -out ssl/ldap-client.csr -config <(
cat <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req