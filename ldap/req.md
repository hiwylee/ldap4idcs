# Docker와 HTTPS를 사용한 OpenLDAP 설치 가이드

이 가이드는 Docker와 HTTPS 지원을 사용하여 OpenLDAP을 설정하기 위한 종합적인 지침을 제공합니다.

## 사전 요구 사항

- Docker 엔진 (버전 20.10.x 이상)
- Docker Compose (버전 2.x 이상)
- 인증서 생성을 위한 OpenSSL
- LDAP 개념에 대한 기본 이해
- 도메인 이름 (적절한 SSL/TLS 설정을 위해)

## 설치 단계

### 1. 디렉토리 구조 설정

OpenLDAP 배포를 위해 다음과 같은 디렉토리 구조를 생성하세요:

```
ldap/
├── certs/           # SSL/TLS 인증서
├── config/          # OpenLDAP 설정 파일
├── data/            # LDAP 데이터 저장소
├── init.ldif        # 초기 LDAP 데이터 가져오기 파일
├── docker-compose.yml
└── Dockerfile
```

### 2. Let's Encrypt를 사용한 SSL/TLS 인증서 생성

Let's Encrypt를 사용하여 무료로 신뢰할 수 있는 SSL/TLS 인증서를 발급받을 수 있습니다. 이를 위해 Certbot을 사용하겠습니다:

```bash
# 인증서 디렉토리 생성
mkdir -p certs

# Certbot 설치 (Oracle Linux용)
sudo dnf install -y epel-release
sudo dnf install -y certbot

# Let's Encrypt 인증서 발급 받기 (스탠드얼론 모드)
sudo certbot certonly --standalone -d ldapv3-idp.duckdns.org --agree-tos --email admin@example.com --non-interactive

# 인증서 파일을 OpenLDAP에서 사용할 위치로 복사
sudo cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/fullchain.pem certs/ldap.crt
sudo cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/privkey.pem certs/ldap.key

# CA 인증서 복사
sudo cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/chain.pem certs/ca.crt

# 향상된 보안을 위한 dhparam 파일 생성
openssl dhparam -out certs/dhparam.pem 2048

# 적절한 권한 설정
chmod 600 certs/ldap.key
chmod 644 certs/ldap.crt certs/ca.crt

# 인증서 자동 갱신을 위한 cron 작업 추가
echo "0 0 1 * * root certbot renew --quiet && cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/fullchain.pem /path/to/certs/ldap.crt && cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/privkey.pem /path/to/certs/ldap.key && cp /etc/letsencrypt/live/ldapv3-idp.duckdns.org/chain.pem /path/to/certs/ca.crt && systemctl restart openldap" | sudo tee -a /etc/crontab
```

위 명령어에서 `ldapv3-idp.duckdns.org`를 실제 도메인 이름으로 교체하고, `admin@example.com`을 실제 이메일 주소로 변경하세요. 또한, 인증서 갱신 스크립트에서 `/path/to/certs/`를 실제 인증서 경로로 변경해야 합니다.

### 3. OpenLDAP 설정

`config/slapd.conf`에 기본 slapd 설정 파일을 생성하세요:

```
include         /etc/openldap/schema/core.schema
include         /etc/openldap/schema/cosine.schema
include         /etc/openldap/schema/inetorgperson.schema
include         /etc/openldap/schema/nis.schema

pidfile         /var/run/slapd/slapd.pid
argsfile        /var/run/slapd/slapd.args

modulepath      /usr/lib/openldap
moduleload      back_mdb.la

TLSCACertificateFile    /etc/ssl/certs/ca.crt
TLSCertificateFile      /etc/ssl/certs/ldap.crt
TLSCertificateKeyFile   /etc/ssl/certs/ldap.key
TLSCipherSuite          HIGH:!SSLv3:!SSLv2:!TLSv1
TLSProtocolMin          3.2

database        mdb
maxsize         1073741824
suffix          "dc=duckdns,dc=org"
rootdn          "cn=admin,dc=duckdns,dc=org"
rootpw          {SSHA}xxxxxxxxxxxxxxxxxxxxxxxx
directory       /var/lib/ldap
index           objectClass eq
```

`rootpw`를 위한 SSHA 비밀번호 해시를 다음과 같이 생성해야 합니다:

```bash
slappasswd -s 여기에_비밀번호_입력
```

### 4. 초기 LDAP 데이터

초기 LDAP 구조를 정의하기 위해 `init.ldif` 파일을 생성하거나 수정하세요:

```ldif
# 기본 조직
dn: dc=duckdns,dc=org
objectClass: dcObject
objectClass: organization
dc: example
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
```

비밀번호 해시를 `slappasswd`를 사용하여 생성한 실제 SSHA 해시로 교체하세요.

### 5. Docker Compose 설정

`docker-compose.yml` 파일을 생성하세요:

```yaml
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
      - "636:636"   # LDAPS (LDAP over SSL)
    volumes:
      - ./data:/var/lib/ldap
      - ./config:/etc/ldap/slapd.d
      - ./certs:/etc/ssl/certs
      - ./init.ldif:/container/service/slapd/assets/config/bootstrap/ldif/custom/init.ldif
    networks:
      - ldap_network
    restart: unless-stopped

networks:
  ldap_network:
    driver: bridge
```

## OpenLDAP 서버 실행

1. OpenLDAP 서버를 시작하세요:

```bash
docker-compose up -d
```

2. 서버가 실행 중인지 확인하세요:

```bash
docker-compose ps
```

3. LDAP 연결을 테스트하세요:

```bash
# LDAP 연결 테스트 (비SSL)
ldapsearch -x -H ldap://158.180.82.84:389 -b "dc=duckdns,dc=org" -D "cn=admin,dc=duckdns,dc=org" -w admin_password

# LDAPS 연결 테스트 (SSL)
ldapsearch -x -H ldaps://158.180.82.84:636 -b "dc=duckdns,dc=org" -D "cn=admin,dc=duckdns,dc=org" -w admin_password -ZZ

# FQDN을 사용한 테스트
ldapsearch -x -H ldaps://ldapv3-idp.duckdns.org:636 -b "dc=duckdns,dc=org" -D "cn=admin,dc=duckdns,dc=org" -w admin_password -ZZ
```

## 문제 해결

- **연결 문제**: `docker-compose logs openldap` 명령어로 Docker 컨테이너 로그 확인
- **인증서 문제**: 인증서 경로와 권한 확인
- **인증 실패**: 관리자 비밀번호가 올바르게 설정되었는지 확인
- **데이터 가져오기 실패**: LDIF 파일의 구문 확인

## 보안 고려사항

- 프로덕션 환경에서 기본 비밀번호 변경
- 프로덕션용 적절한 CA 서명 인증서 사용
- 방화벽 규칙을 사용하여 LDAP 서버에 대한 액세스 제한
- 모든 통신에 TLS/SSL을 통한 LDAP 구현 고려
- LDAP 데이터 정기적 백업

## 추가 리소스

- [OpenLDAP 관리자 가이드](https://www.openldap.org/doc/admin24/)
- [Docker OpenLDAP 문서](https://github.com/osixia/docker-openldap)
- [LDAP 보안 모법 사례](https://ldap.com/2018/05/04/ldap-security-best-practices/)
