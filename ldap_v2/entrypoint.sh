#!/bin/bash
set -e

# 환경 변수 기본값 설정
LDAP_ORGANISATION=${LDAP_ORGANISATION:-"My Organization"}
LDAP_DOMAIN=${LDAP_DOMAIN:-"example.org"}
LDAP_BASE_DN=${LDAP_BASE_DN:-"dc=example,dc=org"}
LDAP_ADMIN_PASSWORD=${LDAP_ADMIN_PASSWORD:-"Oracle_12345"}
LDAP_CONFIG_PASSWORD=${LDAP_CONFIG_PASSWORD:-"Oracle_12345"}

echo "Starting OpenLDAP initialization..."

# 디렉토리 권한 사전 설정
mkdir -p /var/lib/ldap /var/run/slapd /etc/ldap/slapd.d
chown -R openldap:openldap /var/lib/ldap
chown -R openldap:openldap /var/run/slapd
chown -R openldap:openldap /etc/ldap/slapd.d

# 설정 디렉토리가 비어있는지 확인
if [ ! -f "/etc/ldap/slapd.d/cn=config.ldif" ]; then
    echo "Initializing OpenLDAP configuration database..."
    
    # 기존 설정 정리
    rm -rf /etc/ldap/slapd.d/*
    
    # 관리자 비밀번호 해시 생성
    echo "Generating password hashes..."
    ADMIN_PASSWORD_HASH=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")
    CONFIG_PASSWORD_HASH=$(slappasswd -s "$LDAP_CONFIG_PASSWORD")
    
    echo "Generated admin hash: $ADMIN_PASSWORD_HASH"
    echo "Generated config hash: $CONFIG_PASSWORD_HASH"
    
    # 기본 설정 LDIF 생성
    cat > /tmp/init-config.ldif << EOF
dn: cn=config
objectClass: olcGlobal
cn: config
olcArgsFile: /var/run/slapd/slapd.args
olcPidFile: /var/run/slapd/slapd.pid
olcServerID: 1

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

dn: cn={0}core,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: {0}core

dn: cn={1}cosine,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: {1}cosine

dn: cn={2}nis,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: {2}nis

dn: cn={3}inetorgperson,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: {3}inetorgperson

dn: olcDatabase={-1}frontend,cn=config
objectClass: olcDatabaseConfig
objectClass: olcFrontendConfig
olcDatabase: {-1}frontend
olcAccess: {0}to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
olcAccess: {1}to dn.exact="" by * read
olcAccess: {2}to dn.base="cn=Subschema" by * read

dn: olcDatabase={0}config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: {0}config
olcAccess: {0}to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
olcRootDN: cn=config
olcRootPW: $CONFIG_PASSWORD_HASH

dn: olcDatabase={1}mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: {1}mdb
olcDbDirectory: /var/lib/ldap
olcSuffix: $LDAP_BASE_DN
olcAccess: {0}to attrs=userPassword by self write by anonymous auth by * none
olcAccess: {1}to attrs=shadowLastChange by self write by * read
olcAccess: {2}to * by * read
olcLastMod: TRUE
olcRootDN: cn=admin,$LDAP_BASE_DN
olcRootPW: $ADMIN_PASSWORD_HASH
olcDbCheckpoint: 512 30
olcDbIndex: objectClass eq
olcDbIndex: cn,uid eq
olcDbIndex: uidNumber,gidNumber eq
olcDbIndex: member,memberUid eq
olcDbMaxSize: 104857600
EOF

    # 설정 데이터베이스 초기화
    echo "Initializing configuration database..."
    slapadd -F /etc/ldap/slapd.d -n 0 -l /tmp/init-config.ldif
    
    # 권한 설정 (데이터 추가 전)
    chown -R openldap:openldap /etc/ldap/slapd.d
    chown -R openldap:openldap /var/lib/ldap
    
    # 기본 DIT 구조 생성
    cat > /tmp/init-data.ldif << EOF
dn: $LDAP_BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
o: $LDAP_ORGANISATION
dc: $(echo $LDAP_DOMAIN | cut -d. -f1)

dn: cn=admin,$LDAP_BASE_DN
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
description: LDAP administrator
userPassword: $ADMIN_PASSWORD_HASH

dn: ou=people,$LDAP_BASE_DN
objectClass: organizationalUnit
ou: people

dn: ou=groups,$LDAP_BASE_DN
objectClass: organizationalUnit
ou: groups
EOF

    # 데이터 추가 (권한 변경 후)
    echo "Adding initial data..."
    slapadd -F /etc/ldap/slapd.d -n 1 -l /tmp/init-data.ldif
    
    echo "OpenLDAP configuration initialized successfully"
fi

# 최종 권한 설정
chown -R openldap:openldap /var/lib/ldap
chown -R openldap:openldap /etc/ldap/slapd.d
chown -R openldap:openldap /var/run/slapd

# 필요한 디렉토리 생성
mkdir -p /var/run/slapd
chown openldap:openldap /var/run/slapd

echo "Starting slapd with minimal logging..."

# 설정 테스트 먼저 실행
echo "Testing configuration..."
slaptest -F /etc/ldap/slapd.d -u

if [ $? -eq 0 ]; then
    echo "Configuration test passed. Starting slapd..."
    # slapd 실행 (최소 로깅)
    exec slapd -d ${LDAP_LOG_LEVEL:-65535} -h "ldap://0.0.0.0:389/" -F /etc/ldap/slapd.d -u openldap -g openldap
else
    echo "Configuration test failed!"
    exit 1
fi