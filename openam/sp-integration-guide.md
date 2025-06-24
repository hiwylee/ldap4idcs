# OpenAM & OpenLDAP Docker 구성 및 SAML Metadata Export 가이드

## 목차
1. [개요](#개요)
2. [사전 요구사항](#사전-요구사항)
3. [OpenLDAP Docker 구성](#openldap-docker-구성)
4. [OpenAM Docker 구성](#openam-docker-구성)
5. [OpenAM과 OpenLDAP 연동](#openam과-openldap-연동)
6. [SAML 설정](#saml-설정)
7. [SAML Metadata Export](#saml-metadata-export)
8. [문제 해결](#문제-해결)

## 개요

이 가이드는 Docker를 사용하여 OpenAM(Identity Provider)과 OpenLDAP(Directory Server)를 구성하고, SAML SSO를 위한 metadata를 export하는 방법을 설명합니다.

## 사전 요구사항

- Docker 및 Docker Compose 설치
- 최소 4GB RAM 권장
- 포트 389, 636, 8080, 8443 사용 가능

## 외부 LDAP 서버 사용 (ldapv3-idp.duckdns.org)

이 가이드에서는 외부 LDAP 서버 `ldapv3-idp.duckdns.org`를 사용하므로, OpenLDAP 컨테이너 대신 외부 서버에 연결합니다.

### 1. Docker Compose 파일 생성

`docker-compose.yml` 파일을 생성합니다:

```yaml
version: '3.8'

services:
  openam:
    image: openidentityplatform/openam:14.7.2
    container_name: openam-server
    ports:
      - "8080:8080"
    environment:
      CATALINA_OPTS: "-Xmx2048m -server"
      OPENAM_ROOT_PASSWORD: "password123"
    volumes:
      - openam-data:/usr/openam/config
    networks:
      - openam-network
    extra_hosts:
      - "ldapv3-idp.duckdns.org:${LDAP_SERVER_IP:-8.8.8.8}"

  # LDAP 관리용 웹 인터페이스 (선택사항)
  phpldapadmin:
    image: osixia/phpldapadmin:latest
    container_name: phpldapadmin
    environment:
      PHPLDAPADMIN_LDAP_HOSTS: "ldapv3-idp.duckdns.org"
      PHPLDAPADMIN_HTTPS: "false"
    ports:
      - "8081:80"
    networks:
      - openam-network
    extra_hosts:
      - "ldapv3-idp.duckdns.org:${LDAP_SERVER_IP:-8.8.8.8}"

volumes:
  openam-data:

networks:
  openam-network:
    driver: bridge
```

### 2. 환경 변수 설정

외부 LDAP 서버를 사용하기 위해 `.env` 파일을 생성합니다:

```bash
# .env 파일 생성
cat > .env << 'EOF'
# 외부 LDAP 서버 설정
LDAP_SERVER_HOST=ldapv3-idp.duckdns.org
LDAP_SERVER_PORT=389
LDAP_SERVER_SSL_PORT=636
LDAP_BASE_DN=dc=oracle,dc=com
LDAP_ADMIN_DN=cn=admin,dc=oracle,dc=com
LDAP_ADMIN_PASSWORD=Oracle_12345
LDAP_USER_BASE_DN=ou=people,dc=oracle,dc=com
LDAP_GROUP_BASE_DN=ou=groups,dc=oracle,dc=com

# OpenAM 설정
OPENAM_ADMIN_PASSWORD=Oracle_12345
EOF
```

### 3. 컨테이너 실행

```bash
# Docker Compose로 서비스 시작
docker-compose up -d

# 컨테이너 상태 확인
docker-compose ps

# OpenAM 로그 확인
docker-compose logs -f openam
```

### 4. 외부 LDAP 서버 연결 테스트

OpenAM 컨테이너에서 외부 LDAP 서버에 연결할 수 있는지 확인합니다:

```bash
# 컨테이너 내부에서 LDAP 연결 테스트
docker exec -it openam-server bash

# LDAP 연결 테스트 (컨테이너 내부에서)
apt-get update && apt-get install -y ldap-utils
ldapsearch -x -H ldap://ldapv3-idp.duckdns.org:389 -b "dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345

# 네트워크 연결 확인
ping ldapv3-idp.duckdns.org
telnet ldapv3-idp.duckdns.org 389
```

## OpenAM Docker 구성

### 1. OpenAM 초기 설정

브라우저에서 `http://localhost:8080/openam`에 접속하여 초기 설정을 진행합니다.

#### 설정 단계:
1. **Custom Configuration** 선택
2. **Server Settings**:
   - Server URL: `http://localhost:8080/openam`
   - Cookie Domain: `localhost`
3. **Configuration Data Store**:
   - Data Store Type: `Embedded OpenDJ`
   - Directory Manager Password: `Oracle_12345`
4. **User Data Store** (로컬 OpenLDAP 사용 시):
   - User Data Store Type: `External OpenDJ`
   - SSL/TLS Enabled: `No`
   - Directory Name: `ldap://openldap-server:389/dc=oracle,dc=com`
   - Login ID: `cn=admin,dc=oracle,dc=com`
   - Password: `Oracle_12345`
4. **User Data Store** (외부 LDAP 사용 시):
   - User Data Store Type: `External OpenDJ`
   - SSL/TLS Enabled: `No` (또는 LDAPS 사용 시 `Yes`)
   - Directory Name: `ldap://ldapv3-idp.duckdns.org:389/dc=oracle,dc=com`
   - Login ID: `cn=admin,dc=oracle,dc=com`
   - Password: `Oracle_12345`
5. **Site Configuration**: 기본값 사용
6. **Default Policy Agent User**: `Oracle_12345`

### 2. OpenAM 관리자 계정

- URL: `http://localhost:8080/openam`
- Username: `amadmin`
- Password: `Oracle_12345`

### 3. phpLDAPadmin 웹 인터페이스

LDAP 서버 관리를 위한 웹 인터페이스:

- URL: `http://localhost:8081`
- Login DN: `cn=admin,dc=oracle,dc=com`
- Password: `Oracle_12345`

## OpenAM과 OpenLDAP 연동

### 1. Data Store 설정

OpenAM 관리 콘솔(`http://localhost:8080/openam`)에 로그인 후:

1. **Realms** → **Top Level Realm** → **Data Stores** 이동
2. **New...** 클릭하여 새 Data Store 생성
3. **Data Store 설정**:
   - **Name**: `Oracle-LDAP-DataStore`
   - **Data Store Type**: `LDAPv3 (OpenDJ)`
   - **LDAP Server**: `ldap://openldap-server:389`
   - **LDAP Bind DN**: `cn=admin,dc=oracle,dc=com`
   - **LDAP Bind Password**: `Oracle_12345`
   - **LDAP Organization DN**: `dc=oracle,dc=com`
   - **LDAP Users Search Base**: `ou=people,dc=oracle,dc=com`
   - **LDAP Groups Search Base**: `ou=groups,dc=oracle,dc=com`
   - **LDAP User Search Filter**: `(uid=%s)`
   - **LDAP User Object Class**: `inetOrgPerson`
   - **LDAP Group Search Filter**: `(cn=%s)`
   - **LDAP Group Object Class**: `groupOfNames`

### 2. Authentication Module 설정

LDAP 인증 모듈을 설정합니다:

1. **Authentication** → **Modules** 이동
2. **New...** 클릭하여 LDAP 모듈 생성
3. **LDAP Authentication Module 설정**:
   - **Module Name**: `Oracle-LDAP-Auth`
   - **Type**: `LDAP`
   - **Primary LDAP Server**: `ldap://openldap-server:389`
   - **LDAP Bind DN**: `cn=admin,dc=oracle,dc=com`
   - **LDAP Bind Password**: `Oracle_12345`
   - **LDAP Base DN**: `ou=people,dc=oracle,dc=com`
   - **LDAP User Search Attribute**: `uid`
   - **LDAP User Object Class**: `inetOrgPerson`
   - **LDAP User Attributes**: `uid,cn,sn,givenName,mail`
   - **LDAP Search Scope**: `SUBTREE`

### 3. Authentication Chain 설정

LDAP 인증을 기본으로 사용하도록 설정:

1. **Authentication** → **Chains** 이동
2. **New...** 클릭하여 새 체인 생성:
   - **Chain Name**: `Oracle-LDAP-Chain`
   - **Authentication Modules**: `Oracle-LDAP-Auth` 추가
   - **Criteria**: `REQUIRED`

3. **Authentication Configuration** 설정:
   - **Authentication** → **Settings** → **Core** 이동
   - **Organization Authentication Configuration**: `Oracle-LDAP-Chain` 선택

### 4. 고급 LDAP 연동 설정

#### Connection Pool 최적화 (60GB 메모리 활용)

1. **Configuration** → **System** → **Platform** 이동
2. **Server Defaults** → **SDK** 탭 선택
3. **LDAP Connection Pool Settings**:
   - **LDAP Connection Pool Minimum Size**: `10`
   - **LDAP Connection Pool Maximum Size**: `50`
   - **LDAP Connection Pool Heartbeat Interval**: `10`
   - **LDAP Connection Pool Heartbeat Time Unit**: `SECONDS`
   - **LDAP Connection Pool Idle Timeout**: `300`

#### SSL/TLS 설정 (선택사항)

LDAPS를 사용하려면:

1. Data Store에서 LDAP Server를 `ldaps://openldap-server:636`으로 변경
2. **SSL/TLS Enabled**: `Yes`
3. **Trust Store**: OpenLDAP 인증서 추가

### 5. 사용자 속성 매핑 설정

OpenAM과 LDAP 간 사용자 속성 매핑을 설정합니다:

1. **Realms** → **Top Level Realm** → **Services** 이동
2. **User** 서비스 선택
3. **User Profile** 탭에서 속성 매핑:
   - **cn**: `cn`
   - **sn**: `sn`
   - **givenName**: `givenName`
   - **mail**: `mail`
   - **uid**: `uid`
   - **telephoneNumber**: `telephoneNumber`

### 6. 연동 테스트 스크립트

OpenAM-OpenLDAP 연동을 테스트하는 스크립트를 생성합니다:

```bash
# 연동 테스트 스크립트 생성
cat > test-integration.sh << 'EOF'
#!/bin/bash

echo "=== OpenAM-OpenLDAP 연동 테스트 ==="

# 1. OpenLDAP 연결 테스트
echo "1. OpenLDAP 연결 테스트..."
docker-compose exec openldap ldapsearch -x -H ldap://localhost -b "dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 "(objectClass=*)" dn

# 2. OpenLDAP 사용자 확인
echo "2. LDAP 사용자 확인..."
docker-compose exec openldap ldapsearch -x -H ldap://localhost -b "ou=people,dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 "(uid=testuser1)"

# 3. OpenAM 상태 확인
echo "3. OpenAM 상태 확인..."
curl -s http://localhost:8080/openam/isAlive.jsp

# 4. OpenAM에서 LDAP 연결 테스트
echo "4. OpenAM 컨테이너에서 LDAP 연결 테스트..."
docker-compose exec openam bash -c '
if command -v ldapsearch &> /dev/null; then
    ldapsearch -x -H ldap://openldap-server:389 -b "dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345 "(objectClass=*)" dn
else
    echo "ldap-utils가 설치되지 않음. 네트워크 연결만 확인..."
    nc -zv openldap-server 389
fi
'

# 5. 네트워크 연결 확인
echo "5. 컨테이너 간 네트워크 연결 확인..."
docker-compose exec openam ping -c 3 openldap-server

echo "=== 테스트 완료 ==="
EOF

chmod +x test-integration.sh

# 테스트 실행
./test-integration.sh
```

### 7. LDAP 사용자 인증 테스트

웹 브라우저에서 OpenAM 로그인 테스트:

1. `http://localhost:8080/openam` 접속
2. **Log Out** (관리자 로그아웃)
3. 다음 계정으로 로그인 테스트:
   - Username: `testuser1`, Password: `Oracle_12345`
   - Username: `testuser2`, Password: `Oracle_12345`
   - Username: `admin`, Password: `Oracle_12345`

### 8. 연동 문제 해결

#### 일반적인 연동 문제

**LDAP 연결 실패 시:**
```bash
# OpenAM 로그 확인
docker-compose exec openam tail -f /usr/local/tomcat/logs/catalina.out | grep -i ldap

# LDAP 로그 확인
docker-compose exec openldap tail -f /var/log/slapd.log

# 네트워크 연결 확인
docker-compose exec openam telnet openldap-server 389
```

**인증 실패 시:**
```bash
# LDAP 사용자 패스워드 확인
docker-compose exec openldap ldapwhoami -x -D "uid=testuser1,ou=people,dc=oracle,dc=com" -w Oracle_12345

# OpenAM 디버그 로깅 활성화
# Configuration → System → Logging → Debug Logging
# com.sun.identity.authentication = MESSAGE
```

**속성 매핑 문제 시:**
```bash
# LDAP 사용자 속성 확인
docker-compose exec openldap ldapsearch -x -H ldap://localhost -b "uid=testuser1,ou=people,dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345
```

### 4. 고급 LDAP 설정

LDAP 서버 사용 시 추가 고려사항:

#### SSL/TLS 설정 (권장)
```yaml
# LDAPS 사용 시 (포트 636)
LDAP Server: ldaps://ldapv3-idp.duckdns.org:636
# 또는 로컬 LDAP의 경우
LDAP Server: ldaps://openldap-server:636
```

#### 연결 풀 설정
- **LDAP Connection Pool Minimum Size**: `1`
- **LDAP Connection Pool Maximum Size**: `10`
- **LDAP Connection Heartbeat Interval**: `10`
- **LDAP Connection Heartbeat Time Unit**: `SECONDS`

#### 네트워크 타임아웃 설정
- **LDAP Connection Timeout**: `10` (seconds)
- **LDAP Operations Timeout**: `30` (seconds)

### 5. Authentication Chain 설정

OpenAM에서 LDAP 인증을 기본으로 사용하도록 설정:

1. **Authentication** → **Chains** 이동
2. **ldapService** 선택 (또는 새로 생성)
3. 생성한 LDAP Authentication Module 추가
4. **Authentication Configuration** → **Organization Authentication Configuration** 에서 기본 체인으로 설정트 636)
LDAP Server: ldaps://ldapv3-idp.duckdns.org:636

#### 연결 풀 설정
- **LDAP Connection Pool Minimum Size**: `1`
- **LDAP Connection Pool Maximum Size**: `10`
- **LDAP Connection Heartbeat Interval**: `10`
- **LDAP Connection Heartbeat Time Unit**: `SECONDS`

#### 네트워크 타임아웃 설정
- **LDAP Connection Timeout**: `10` (seconds)
- **LDAP Operations Timeout**: `30` (seconds)

## SAML 설정

### 1. Federation 설정

1. **Federation** → **Entity Providers** 이동
2. **New...** 클릭하여 Hosted Identity Provider 생성
3. **IDP 설정**:
   - Entity ID: `http://localhost:8080/openam`
   - Meta Alias: `/idp`
   - Signing Certificate Alias: 기본값 사용

### 2. Circle of Trust 생성

1. **Federation** → **Circle of Trust** 이동
2. **New...** 클릭
3. **COT 설정**:
   - Name: `default-cot`
   - Description: `Default Circle of Trust`
   - Add Entity Providers에서 생성한 IDP 선택

### 3. Service Provider 설정 (선택사항)

실제 SP와 연동하기 위해서는 SP metadata를 import해야 합니다:

1. **Federation** → **Entity Providers** 이동
2. **Import...** 클릭
3. SP의 metadata XML 파일 또는 URL 입력

## SAML Metadata Export

### 1. 웹 인터페이스를 통한 Export

OpenAM 관리 콘솔에서:

1. **Federation** → **Entity Providers** 이동
2. 생성한 Identity Provider 선택
3. **Export** 탭 클릭
4. **Standard Metadata** 선택하여 XML 다운로드

### 2. 직접 URL 접근

브라우저에서 다음 URL로 직접 접근:

```
http://localhost:8080/openam/saml2/jsp/exportmetadata.jsp?entityid=http://localhost:8080/openam&realm=/
```

### 3. REST API를 통한 Export

```bash
# cURL을 사용한 metadata 조회
curl -X GET \
  "http://localhost:8080/openam/json/realm-config/saml2/idp/metadata" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json"
```

### 4. 명령줄을 통한 Export

OpenAM 컨테이너 내부에서:

```bash
# 컨테이너 접속
docker exec -it openam-server bash

# ssoadm 도구를 사용한 metadata export
cd /usr/openam/bin
./ssoadm export-entity \
  --entityid "http://localhost:8080/openam" \
  --realm "/" \
  --adminid amadmin \
  --password-file /tmp/pwd.txt \
  --sign \
  --meta-data-file /tmp/idp-metadata.xml
```

### 5. Metadata 파일 예시

Export된 metadata는 다음과 같은 형태입니다:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<EntityDescriptor entityID="http://localhost:8080/openam" 
                  xmlns="urn:oasis:names:tc:SAML:2.0:metadata">
    <IDPSSODescriptor WantAuthnRequestsSigned="false" 
                      protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
        <KeyDescriptor use="signing">
            <!-- 인증서 정보 -->
        </KeyDescriptor>
        <SingleLogoutService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
                            Location="http://localhost:8080/openam/SLORedirect/metaAlias/idp"/>
        <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
                            Location="http://localhost:8080/openam/SSORedirect/metaAlias/idp"/>
        <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
                            Location="http://localhost:8080/openam/SSOPOST/metaAlias/idp"/>
    </IDPSSODescriptor>
</EntityDescriptor>
```

## 검증 및 테스트

### 1. 외부 LDAP 연결 테스트

```bash
# 호스트에서 외부 LDAP 서버 연결 테스트
# ldap-utils 설치 (Ubuntu/Debian)
sudo apt-get install ldap-utils

# 또는 CentOS/RHEL
sudo yum install openldap-clients

# LDAP 서버 연결 테스트
ldapsearch -x -H ldap://ldapv3-idp.duckdns.org:389 -b "dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w your_password

# 특정 사용자 검색
ldapsearch -x -H ldap://ldapv3-idp.duckdns.org:389 -b "ou=people,dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w your_password "(uid=testuser)"

# 네트워크 연결 확인
ping ldapv3-idp.duckdns.org
telnet ldapv3-idp.duckdns.org 389
```

### 2. OpenAM에서 외부 LDAP 연결 확인

OpenAM 관리 콘솔에서:

1. **Configuration** → **System** → **Platform** 이동
2. **Server Defaults** → **SDK** 탭
3. **LDAP Connection Pool Settings** 확인

### 3. 연결 문제 해결

외부 LDAP 서버 연결 시 발생할 수 있는 문제들:

#### DNS 해결 문제
```bash
# OpenAM 컨테이너에서 DNS 확인
docker exec -it openam-server nslookup ldapv3-idp.duckdns.org

# 필요시 /etc/hosts 수정
docker exec -it openam-server bash
echo "IP_ADDRESS ldapv3-idp.duckdns.org" >> /etc/hosts
```

#### 방화벽 및 포트 접근
```bash
# 포트 접근성 확인
telnet ldapv3-idp.duckdns.org 389
telnet ldapv3-idp.duckdns.org 636  # LDAPS의 경우
```

### 2. OpenAM 로그인 테스트

1. `http://localhost:8080/openam` 접속
2. testuser / password123으로 로그인 시도
3. 성공 시 OpenAM 사용자 프로파일 페이지 표시

### 3. SAML SSO 테스트

SP 애플리케이션에서 SAML SSO 요청을 보내어 정상적으로 인증되는지 확인합니다.

## 문제 해결

### 1. 일반적인 문제들

**외부 LDAP 연결 실패**
```bash
# DNS 해결 확인
nslookup ldapv3-idp.duckdns.org

# 네트워크 연결 확인
ping ldapv3-idp.duckdns.org
telnet ldapv3-idp.duckdns.org 389

# OpenAM 컨테이너에서 외부 서버 접근 테스트
docker exec -it openam-server bash
apt-get update && apt-get install -y ldap-utils telnet dnsutils
ldapsearch -x -H ldap://ldapv3-idp.duckdns.org:389 -b "dc=example,dc=com"
```

**방화벽 및 네트워크 문제**
```bash
# 포트 스캔
nmap -p 389,636 ldapv3-idp.duckdns.org

# Docker 컨테이너에서 외부 네트워크 접근 확인
docker exec openam-server ping 8.8.8.8
docker exec openam-server ping ldapv3-idp.duckdns.org
```

**SSL/TLS 인증서 문제 (LDAPS 사용 시)**
```bash
# SSL 연결 테스트
openssl s_client -connect ldapv3-idp.duckdns.org:636 -verify_return_error

# 인증서 정보 확인
echo | openssl s_client -connect ldapv3-idp.duckdns.org:636 2>/dev/null | openssl x509 -noout -dates
```

**OpenAM 메모리 부족**
```yaml
# docker-compose.yml에서 메모리 증가
environment:
  CATALINA_OPTS: "-Xmx4096m -server"
```

**포트 충돌**
```bash
# 포트 사용 현황 확인
netstat -tulpn | grep :8080
netstat -tulpn | grep :389
```

### 2. 로그 확인

```bash
# OpenAM 로그
docker exec openam-server tail -f /usr/local/tomcat/logs/catalina.out

# OpenAM 디버그 로그 (LDAP 연결 관련)
docker exec openam-server find /usr/openam/config -name "*.log" -exec tail -f {} +

# 컨테이너 로그
docker-compose logs -f openam

# 네트워크 연결 디버깅
docker exec -it openam-server bash
netstat -an | grep 389
ss -tuln | grep 389
```

### 3. 외부 LDAP 서버 정보 확인

외부 LDAP 서버(`ldapv3-idp.duckdns.org`)의 정확한 설정을 확인해야 합니다:

```bash
# LDAP 서버 스키마 및 구조 확인
ldapsearch -x -H ldap://ldapv3-idp.duckdns.org:389 -b "" -s base "(objectclass=*)" namingContexts

# 지원되는 인증 메커니즘 확인
ldapsearch -x -H ldap://ldapv3-idp.duckdns.org:389 -b "" -s base "(objectclass=*)" supportedSASLMechanisms

# 베이스 DN 구조 확인
ldapsearch -x -H ldap://ldapv3-idp.duckdns.org:389 -b "dc=example,dc=com" -s one "(objectclass=*)"
```

### 3. 컨테이너 재시작

```bash
# OpenAM 재시작
docker-compose restart openam

# 전체 환경 재구성
docker-compose down
docker-compose up -d

# 볼륨 초기화 (주의: 설정 데이터 삭제됨)
docker-compose down -v
docker volume prune
docker-compose up -d
```

### 4. 외부 LDAP 서버 연동 체크리스트

외부 LDAP 서버 연동 전 확인사항:

- [ ] LDAP 서버 주소: `ldapv3-idp.duckdns.org`
- [ ] 포트 접근 가능 (389, 636)
- [ ] 관리자 계정 정보 확인
- [ ] 베이스 DN 구조 파악
- [ ] 사용자/그룹 검색 베이스 확인
- [ ] SSL/TLS 설정 (필요시)
- [ ] 방화벽 규칙 확인
- [ ] 네트워크 연결성 테스트

## 보안 고려사항

1. **프로덕션 환경에서는 반드시 HTTPS 사용**
2. **강력한 비밀번호 설정**
3. **방화벽 규칙 적용**
4. **정기적인 보안 업데이트**
5. **SSL/TLS 인증서 적절한 관리**

## 참고 자료

- [OpenAM Documentation](https://backstage.forgerock.com/docs/openam)
- [OpenLDAP Documentation](https://www.openldap.org/doc/)
- [SAML 2.0 Specification](https://docs.oasis-open.org/security/saml/v2.0/)
- [Docker OpenAM](https://github.com/OpenIdentityPlatform/OpenAM)

이 가이드를 통해 OpenAM과 OpenLDAP을 Docker 환경에서 성공적으로 구성하고 SAML metadata를 export할 수 있습니다.