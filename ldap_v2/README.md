# OpenLDAP Docker Setup

이 프로젝트는 Docker를 사용하여 OpenLDAP 서버를 구축하고 관리하는 완전한 솔루션을 제공합니다.

## 구성 요소

- **Dockerfile**: OpenLDAP 서버 이미지 빌드
- **entrypoint.sh**: 초기화 및 실행 스크립트
- **docker-compose.yml**: 서비스 오케스트레이션
- **Makefile**: 편리한 관리 명령어들
- **phpLDAPadmin**: 웹 기반 관리 인터페이스

## 빠른 시작

### 1. 프로젝트 구조 준비
```bash
mkdir openldap-docker
cd openldap-docker
# 모든 파일들을 이 디렉토리에 생성
```

### 2. 서비스 빌드 및 실행
```bash
# 이미지 빌드
make build

# 서비스 시작
make up

# 로그 확인
make logs
```

### 3. 연결 테스트
```bash
# LDAP 서버 연결 확인
make test-connection

# 테스트 사용자 추가
make add-user
```

## 환경 변수

docker-compose.yml에서 다음 환경 변수들을 설정할 수 있습니다:

| 변수명 | 기본값 | 설명 |
|--------|--------|------|
| `LDAP_ORGANISATION` | My Company | 조직명 |
| `LDAP_DOMAIN` | example.com | 도메인명 |
| `LDAP_BASE_DN` | dc=example,dc=com | Base DN |
| `LDAP_ADMIN_PASSWORD` | Oracle_12345 | 관리자 비밀번호 |
| `LDAP_CONFIG_PASSWORD` | Oracle_12345 | 설정 비밀번호 |
| `LDAP_LOG_LEVEL` | 256 | 로그 레벨 |

## 사용 가능한 명령어

```bash
# 기본 관리
make build          # 이미지 빌드
make up             # 서비스 시작
make down           # 서비스 중지
make restart        # 서비스 재시작
make logs           # 로그 확인
make status         # 상태 확인

# 컨테이너 관리
make shell          # 컨테이너 쉘 접속
make clean          # 정리

# LDAP 관리
make test-connection # 연결 테스트
make add-user       # 테스트 사용자 추가
make backup         # 데이터 백업
make restore BACKUP_FILE=backup.ldif  # 데이터 복원
make reset          # 데이터 초기화
```

## 웹 관리 인터페이스

phpLDAPadmin을 통해 웹에서 LDAP을 관리할 수 있습니다:

- URL: http://localhost:8080
- 서버: openldap
- 사용자: cn=admin,dc=example,dc=com
- 비밀번호: Oracle_12345

## 포트 정보

- **389**: LDAP 서버 포트
- **636**: LDAPS 서버 포트 (SSL/TLS)
- **8080**: phpLDAPadmin 웹 인터페이스

## 데이터 영속성

Docker 볼륨을 사용하여 데이터를 영속 저장합니다:

- `ldap_data`: LDAP 데이터베이스 파일
- `ldap_config`: LDAP 설정 파일

## 기본 구조

초기화 시 다음 구조가 생성됩니다:

```
dc=example,dc=com
├── cn=admin,dc=example,dc=com
├── ou=people,dc=example,dc=com
└── ou=groups,dc=example,dc=com
```

## 사용자 추가 예시

```bash
# LDIF 파일 생성
cat > add-user.ldif << 'EOF'
dn: uid=john,ou=people,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: john
sn: Doe
givenName: John
cn: John Doe
displayName: John Doe
uidNumber: 1002
gidNumber: 1002
userPassword: {SSHA}hashedpassword
gecos: John Doe
loginShell: /bin/bash
homeDirectory: /home/john
mail: john@example.com
EOF

# 사용자 추가
docker exec -i openldap_server ldapadd -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w Oracle_12345 < add-user.ldif
```

## 백업 및 복원

```bash
# 자동 백업
make backup

# 수동 백업
docker exec openldap_server slapcat -F /etc/ldap/slapd.d -n 1 > backup.ldif

# 복원
make restore BACKUP_FILE=backup.ldif
```

## 문제 해결

### 1. 권한 문제
```bash
# 컨테이너 내부에서 권한 확인
make shell
ls -la /var/lib/ldap
ls -la /etc/ldap/slapd.d
```

### 2. 설정 문제
```bash
# 설정 파일 문법 검사
docker exec openldap_server slaptest -F /etc/ldap/slapd.d
```

### 3. 연결 문제
```bash
# 네트워크 상태 확인
docker network ls
docker network inspect openldap_ldap_network
```

## 보안 고려사항

1. **기본 비밀번호 변경**: 프로덕션 환경에서는 반드시 기본 비밀번호를 변경하세요.
2. **TLS/SSL 설정**: LDAPS 포트(636)에 대한 인증서 설정을 고려하세요.
3. **방화벽 설정**: 필요한 포트만 외부에 노출하세요.
4. **정기 백업**: 중요한 데이터는 정기적으로 백업하세요.

## 라이센스

이 프로젝트는 MIT 라이센스 하에 배포됩니다.
