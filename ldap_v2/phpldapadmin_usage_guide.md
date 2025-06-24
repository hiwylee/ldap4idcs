# phpLDAPadmin 사용법 가이드

## 🌐 접속 및 로그인

### 1. 웹 브라우저 접속
```
URL: http://localhost:8080
```

### 2. 로그인 정보
- **서버**: `openldap` (또는 `localhost`)
- **로그인 DN**: `cn=admin,dc=example,dc=com`
- **비밀번호**: `Oracle_12345`

### 3. 로그인 방법
1. 좌측 상단의 "login" 클릭
2. Login DN과 Password 입력
3. "Authenticate" 버튼 클릭

## 🏗️ 기본 인터페이스 구성

### 좌측 패널 (Tree View)
- **LDAP 트리 구조** 표시
- 폴더 아이콘을 클릭하여 확장/축소
- 각 항목을 클릭하면 우측에 상세 정보 표시

### 우측 패널 (Content View)
- **선택된 항목의 상세 정보** 표시
- 속성 편집 및 관리 기능
- 새 항목 생성 인터페이스

### 상단 메뉴바
- **Home**: 메인 화면
- **Import**: LDIF 파일 가져오기
- **Export**: LDIF 파일 내보내기
- **Search**: 고급 검색 기능

## 👥 사용자 관리

### 1. 새 사용자 생성
#### 방법 1: 템플릿 사용
1. `ou=people,dc=example,dc=com` 선택
2. "Create a child entry" 클릭
3. "Generic: User Account" 템플릿 선택
4. 필수 정보 입력:
   - **RDN**: `uid=사용자명`
   - **First name**: 이름
   - **Last name**: 성
   - **Common Name**: 전체 이름
   - **User ID**: 사용자 ID
   - **Password**: 비밀번호
5. "Create Object" 클릭

#### 방법 2: 수동 생성
1. `ou=people,dc=example,dc=com` 선택
2. "Create a child entry" 클릭
3. "Generic: Posix Account" 선택
4. 상세 정보 입력:
   ```
   RDN: uid=newuser
   Object Classes:
   - inetOrgPerson
   - posixAccount  
   - shadowAccount
   
   Attributes:
   - uid: newuser
   - cn: New User
   - sn: User
   - givenName: New
   - uidNumber: 1005
   - gidNumber: 1005
   - homeDirectory: /home/newuser
   - loginShell: /bin/bash
   - userPassword: Oracle_12345
   ```

### 2. 사용자 정보 수정
1. 수정할 사용자 선택 (예: `uid=testuser,ou=people,dc=example,dc=com`)
2. 우측 패널에서 수정할 속성 옆의 "편집" 아이콘 클릭
3. 새 값 입력 후 "Update Object" 클릭

### 3. 사용자 비밀번호 변경
1. 사용자 선택
2. `userPassword` 속성 옆의 편집 아이콘 클릭
3. "Clear" 또는 "SHA" 암호화 방식 선택
4. 새 비밀번호 입력
5. "Update Object" 클릭

### 4. 사용자 삭제
1. 삭제할 사용자 선택
2. 우측 상단의 "Delete this entry" 클릭
3. 확인 메시지에서 "Delete" 클릭

## 👨‍👩‍👧‍👦 그룹 관리

### 1. 새 그룹 생성
1. `ou=groups,dc=example,dc=com` 선택
2. "Create a child entry" 클릭
3. "Generic: Posix Group" 템플릿 선택
4. 그룹 정보 입력:
   ```
   RDN: cn=newgroup
   Common Name: newgroup
   GID Number: 2005
   Group Members: (선택사항)
   ```
5. "Create Object" 클릭

### 2. 그룹 멤버 추가
#### 방법 1: 그룹 속성에서 추가
1. 그룹 선택 (예: `cn=users,ou=groups,dc=example,dc=com`)
2. `member` 속성 옆의 "+" 아이콘 클릭
3. 사용자 DN 입력 (예: `uid=newuser,ou=people,dc=example,dc=com`)
4. "Add value" 클릭

#### 방법 2: 사용자 속성에서 추가
1. 사용자 선택
2. `memberOf` 속성이 있다면 편집
3. 그룹 DN 추가

### 3. 그룹 멤버 제거
1. 그룹 선택
2. `member` 속성에서 제거할 멤버 옆의 "X" 클릭
3. "Update Object" 클릭

## 🔍 검색 기능

### 1. 기본 검색
1. 상단 메뉴에서 "Search" 클릭
2. 검색 옵션 설정:
   - **Base DN**: 검색 시작점 (예: `dc=example,dc=com`)
   - **Search Scope**: 검색 범위
     - `Base`: 기본 객체만
     - `One Level`: 한 단계 하위
     - `Subtree`: 모든 하위 (기본값)
   - **Search Filter**: 검색 필터
3. "Search" 버튼 클릭

### 2. 자주 사용하는 검색 필터
```ldap
# 모든 사용자
(objectClass=inetOrgPerson)

# 특정 이름 검색
(cn=*John*)

# 특정 UID 범위
(&(objectClass=posixAccount)(uidNumber>=1000)(uidNumber<=2000))

# 이메일이 있는 사용자
(mail=*)

# 특정 그룹 멤버
(memberOf=cn=admins,ou=groups,dc=example,dc=com)

# 최근 로그인 사용자 (shadowLastChange 기준)
(&(objectClass=shadowAccount)(shadowLastChange>=18000))
```

### 3. 고급 검색 예시
1. **개발팀 사용자 검색**:
   - Base DN: `ou=people,dc=example,dc=com`
   - Filter: `(&(objectClass=inetOrgPerson)(departmentNumber=IT))`

2. **비활성 계정 검색**:
   - Filter: `(&(objectClass=posixAccount)(loginShell=/bin/false))`

## 📥📤 데이터 가져오기/내보내기

### 1. LDIF 파일 가져오기 (Import)
1. 상단 메뉴에서 "Import" 클릭
2. LDIF 파일 선택 또는 텍스트 직접 입력
3. 예시 LDIF:
   ```ldif
   dn: uid=imported,ou=people,dc=example,dc=com
   objectClass: inetOrgPerson
   objectClass: posixAccount
   uid: imported
   cn: Imported User
   sn: User
   uidNumber: 1010
   gidNumber: 1010
   homeDirectory: /home/imported
   loginShell: /bin/bash
   userPassword: Oracle_12345
   ```
4. "Proceed" 클릭

### 2. LDIF 파일 내보내기 (Export)
1. 내보낼 항목 선택
2. 상단 메뉴에서 "Export" 클릭
3. 내보내기 옵션 설정:
   - **Export format**: LDIF
   - **Line end style**: Unix/Windows 선택
   - **Include system attributes**: 시스템 속성 포함 여부
4. "Export" 클릭

## 🏢 조직 단위(OU) 관리

### 1. 새 OU 생성
1. 상위 노드 선택 (예: `dc=example,dc=com`)
2. "Create a child entry" 클릭
3. "Generic: Organisational Unit" 선택
4. OU 정보 입력:
   ```
   RDN: ou=departments
   Organisational Unit Name: departments
   Description: Company Departments
   ```

### 2. OU 구조 예시
```
dc=example,dc=com
├── ou=people
├── ou=groups  
├── ou=departments
│   ├── ou=engineering
│   ├── ou=marketing
│   └── ou=sales
└── ou=services
    ├── ou=email
    └── ou=applications
```

## 🔧 고급 기능

### 1. 속성 추가
1. 객체 선택
2. 우측 패널 하단의 "Add new attribute" 클릭
3. 속성 이름 선택 (예: `telephoneNumber`)
4. 값 입력
5. "Add Attribute" 클릭

### 2. ObjectClass 추가
1. 객체 선택
2. `objectClass` 속성 편집
3. 새 ObjectClass 추가 (예: `organizationalPerson`)
4. 필수 속성들 추가

### 3. 스키마 브라우징
1. 좌측 트리에서 "schema" 항목 클릭
2. ObjectClasses와 Attributes 확인
3. 각 스키마의 상세 정보 조회

## 📊 모니터링 및 통계

### 1. 서버 정보 확인
1. 좌측 트리 최상단의 서버 아이콘 클릭
2. 서버 통계 및 설정 정보 확인:
   - 연결 수
   - 바인드 횟수  
   - 검색 횟수
   - 서버 버전

### 2. 데이터베이스 통계
1. `cn=monitor` 노드 확인 (있는 경우)
2. 각종 운영 통계 조회

## 🚨 문제 해결

### 1. 로그인 실패
- **서버 주소 확인**: `openldap` 또는 `localhost`
- **DN 형식 확인**: `cn=admin,dc=example,dc=com`
- **비밀번호 확인**: `Oracle_12345`

### 2. 권한 오류
- 관리자 계정으로 로그인되어 있는지 확인
- ACL(Access Control List) 설정 확인

### 3. 페이지 로딩 문제
- 브라우저 캐시 삭제
- JavaScript 활성화 확인
- 다른 브라우저로 시도

### 4. 한글 깨짐 현상
- UTF-8 인코딩 확인
- 브라우저 문자 인코딩 설정

## 💡 유용한 팁

### 1. 빠른 네비게이션
- 좌측 트리에서 `Ctrl+클릭`으로 새 탭에서 열기
- 브레드크럼(경로) 사용하여 상위 레벨 이동

### 2. 대량 작업
- LDIF 형식으로 대량 데이터 준비
- Import 기능으로 일괄 추가
- 스크립트와 조합하여 자동화

### 3. 백업 전략
- 정기적으로 전체 트리 Export
- 중요 OU별로 개별 백업
- 설정 변경 전 반드시 백업

### 4. 보안 고려사항
- 강력한 관리자 비밀번호 설정
- 일반 사용자는 제한된 권한으로 접근
- HTTPS 사용 고려 (프로덕션 환경)

이제 phpLDAPadmin을 통해 OpenLDAP을 효율적으로 관리할 수 있습니다!