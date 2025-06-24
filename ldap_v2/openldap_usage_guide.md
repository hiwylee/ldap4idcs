# OpenLDAP Docker 사용법 가이드

## 🚀 기본 명령어

### 1. 컨테이너 상태 확인
```bash
# 서비스 상태 확인
make status
# 또는
docker-compose ps

# 실행 중인 컨테이너 확인
docker ps
```

### 2. 로그 확인
```bash
# 실시간 로그 확인
make logs
# 또는
docker-compose logs -f openldap

# 특정 시간대 로그 확인
docker logs openldap_server --since 2h
```

### 3. 컨테이너 접속
```bash
# Bash 쉘 접속
make shell
# 또는
docker exec -it openldap_server /bin/bash

# 특정 명령어 실행
docker exec openldap_server ldapsearch --version
```

## 🔍 LDAP 검색 (Search) 명령어

### 기본 검색
```bash
# 전체 트리 검색
docker exec openldap_server ldapsearch -x -H ldap://localhost:389 \
  -b "dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w Oracle_12345

# 특정 OU 검색
docker exec openldap_server ldapsearch -x -H ldap://localhost:389 \
  -b "ou=people,dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w Oracle_12345

# 특정 사용자 검색
docker exec openldap_server ldapsearch -x -H ldap://localhost:389 \
  -b "dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w Oracle_12345 \
  "(uid=testuser)"
```

### 고급 검색
```bash
# 필터를 사용한 검색
docker exec openldap_server ldapsearch -x -H ldap://localhost:389 \
  -b "dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w Oracle_12345 \
  "(&(objectClass=person)(cn=*User*))"

# 특정 속성만 반환
docker exec openldap_server ldapsearch -x -H ldap://localhost:389 \
  -b "ou=people,dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w Oracle_12345 \
  "(objectClass=inetOrgPerson)" cn mail

# UID 번호 범위로 검색
docker exec openldap_server ldapsearch -x -H ldap://localhost:389 \
  -b "ou=people,dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w Oracle_12345 \
  "(&(objectClass=posixAccount)(uidNumber>=1000)(uidNumber<=2000))"
```

## ➕ LDAP 항목 추가 (Add)

### 사용자 추가
```bash
# LDIF 파일 생성
cat > /tmp/add-user.ldif << 'EOF'
dn: uid=newuser,ou=people,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: newuser
sn: New
givenName: User
cn: New User
displayName: New User
uidNumber: 1003
gidNumber: 1003
userPassword: Oracle_12345
gecos: New User
loginShell: /bin/bash
homeDirectory: /home/newuser
mail: newuser@example.com
telephoneNumber: +1-555-987-6543
EOF

# 사용자 추가
docker exec -i openldap_server ldapadd -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w Oracle_12345 < /tmp/add-user.ldif
```

### 그룹 추가
```bash
# 그룹 LDIF 파일
cat > /tmp/add-group.ldif << 'EOF'
dn: cn=developers,ou=groups,dc=example,dc=com
objectClass: groupOfNames
objectClass: posixGroup
cn: developers
description: Development Team
gidNumber: 2001
member: uid=newuser,ou=people,dc=example,dc=com
member: uid=testuser,ou=people,dc=example,dc=com
EOF

# 그룹 추가
docker exec -i openldap_server ldapadd -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w Oracle_12345 < /tmp/add-group.ldif
```

## ✏️ LDAP 항목 수정 (Modify)

### 사용자 정보 수정
```bash
# 수정 LDIF 파일
cat > /tmp/modify-user.ldif << 'EOF'
dn: uid=testuser,ou=people,dc=example,dc=com
changetype: modify
replace: mail
mail: testuser.new@example.com
-
add: description
description: Updated test user account
-
replace: telephoneNumber
telephoneNumber: +1-555-111-2222
EOF

# 수정 실행
docker exec -i openldap_server ldapmodify -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w Oracle_12345 < /tmp/modify-user.ldif
```

### 비밀번호 변경
```bash
# 새 비밀번호 해시 생성
NEW_PASSWORD_HASH=$(docker exec openldap_server slappasswd -s "NewPassword123")

# 비밀번호 수정 LDIF
cat > /tmp/change-password.ldif << EOF
dn: uid=testuser,ou=people,dc=example,dc=com
changetype: modify
replace: userPassword
userPassword: $NEW_PASSWORD_HASH
EOF

# 적용
docker exec -i openldap_server ldapmodify -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w Oracle_12345 < /tmp/change-password.ldif
```

### 그룹 멤버 추가/제거
```bash
# 그룹에 멤버 추가
cat > /tmp/add-member.ldif << 'EOF'
dn: cn=developers,ou=groups,dc=example,dc=com
changetype: modify
add: member
member: uid=newuser,ou=people,dc=example,dc=com
EOF

# 그룹에서 멤버 제거
cat > /tmp/remove-member.ldif << 'EOF'
dn: cn=developers,ou=groups,dc=example,dc=com
changetype: modify
delete: member
member: uid=testuser,ou=people,dc=example,dc=com
EOF

# 적용
docker exec -i openldap_server ldapmodify -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w Oracle_12345 < /tmp/add-member.ldif
```

## 🗑️ LDAP 항목 삭제 (Delete)

### 사용자 삭제
```bash
# 단일 사용자 삭제
docker exec openldap_server ldapdelete -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w Oracle_12345 \
  "uid=newuser,ou=people,dc=example,dc=com"
```

### 그룹 삭제
```bash
# 그룹 삭제
docker exec openldap_server ldapdelete -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w Oracle_12345 \
  "cn=developers,ou=groups,dc=example,dc=com"
```

## 📊 LDAP 관리 및 모니터링

### 데이터베이스 통계
```bash
# 데이터베이스 덤프
docker exec openldap_server slapcat -F /etc/ldap/slapd.d -n 1

# 설정 덤프
docker exec openldap_server slapcat -F /etc/ldap/slapd.d -n 0

# 인덱스 확인
docker exec openldap_server ldapsearch -x -H ldap://localhost:389 \
  -b "olcDatabase={1}mdb,cn=config" -D "cn=config" -w Oracle_12345 \
  "(objectClass=olcMdbConfig)" olcDbIndex
```

### 접속자 모니터링
```bash
# 현재 연결 상태 확인
docker exec openldap_server ldapsearch -x -H ldap://localhost:389 \
  -b "cn=monitor" -D "cn=admin,dc=example,dc=com" -w Oracle_12345 \
  "(objectClass=*)" | grep -E "(dn:|monitoredInfo:)"
```

## 🔐 인증 테스트

### 사용자 인증 확인
```bash
# 특정 사용자로 bind 테스트
docker exec openldap_server ldapwhoami -x -H ldap://localhost:389 \
  -D "uid=testuser,ou=people,dc=example,dc=com" -w Oracle_12345

# 익명 bind 테스트
docker exec openldap_server ldapwhoami -x -H ldap://localhost:389
```

### 비밀번호 정책 확인
```bash
# 사용자의 비밀번호 속성 확인
docker exec openldap_server ldapsearch -x -H ldap://localhost:389 \
  -b "uid=testuser,ou=people,dc=example,dc=com" \
  -D "cn=admin,dc=example,dc=com" -w Oracle_12345 \
  "(objectClass=*)" userPassword shadowLastChange
```

## 💾 백업 및 복원

### 백업
```bash
# 자동 백업 (Makefile 사용)
make backup

# 수동 백업
mkdir -p backups
docker exec openldap_server slapcat -F /etc/ldap/slapd.d -n 1 > backups/data-$(date +%Y%m%d).ldif
docker exec openldap_server slapcat -F /etc/ldap/slapd.d -n 0 > backups/config-$(date +%Y%m%d).ldif
```

### 복원
```bash
# 서비스 중지
make down

# 데이터 볼륨 삭제
docker volume rm openldap_ldap_data openldap_ldap_config

# 서비스 재시작
make up

# 데이터 복원 (서비스 중지 후)
docker exec -i openldap_server slapadd -F /etc/ldap/slapd.d -n 1 < backups/data-20241225.ldif
```

## 🌐 외부 클라이언트 연결

### ldapsearch (외부에서)
```bash
# 호스트에서 직접 연결
ldapsearch -x -H ldap://localhost:389 \
  -b "dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w Oracle_12345
```

### Python 클라이언트 예시
```python
import ldap3

# 서버 연결
server = ldap3.Server('ldap://localhost:389')
conn = ldap3.Connection(server, 'cn=admin,dc=example,dc=com', 'Oracle_12345')

# 검색
conn.search('ou=people,dc=example,dc=com', '(objectClass=person)')
for entry in conn.entries:
    print(entry)
```

## 🔧 문제 해결

### 일반적인 문제들
```bash
# 권한 문제 확인
docker exec openldap_server ls -la /var/lib/ldap
docker exec openldap_server ls -la /etc/ldap/slapd.d

# 설정 문법 검사
docker exec openldap_server slaptest -F /etc/ldap/slapd.d

# 포트 확인
docker exec openldap_server netstat -tlnp | grep :389

# 프로세스 확인
docker exec openldap_server ps aux | grep slapd
```

### 로그 레벨 조정
```bash
# 더 상세한 로그로 재시작
docker-compose down
# docker-compose.yml에서 LDAP_LOG_LEVEL=65535로 변경
docker-compose up -d
```

이제 OpenLDAP Docker를 효과적으로 사용할 수 있습니다! 필요에 따라 위의 명령어들을 조합하여 LDAP 디렉토리를 관리하세요.