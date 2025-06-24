#!/bin/bash
set -e

echo "=== MINIMAL OPENLDAP TEST ==="

# 환경 변수 기본값
LDAP_BASE_DN=${LDAP_BASE_DN:-"dc=oracle,dc=local"}
LDAP_ADMIN_PASSWORD=${LDAP_ADMIN_PASSWORD:-"Oracle_12345"}

# 디렉토리 생성
mkdir -p /var/lib/ldap /var/run/slapd /etc/ldap/slapd.d
chown -R openldap:openldap /var/lib/ldap /var/run/slapd /etc/ldap/slapd.d

# 설정이 없으면 최소 설정 생성
if [ ! -f "/etc/ldap/slapd.d/cn=config.ldif" ]; then
    echo "Creating minimal config..."
    
    # 비밀번호 해시
    ADMIN_HASH=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")
    
    # 최소 설정 파일
    cat > /tmp/minimal-config.ldif << EOF
dn: cn=config
objectClass: olcGlobal
cn: config
olcPidFile: /var/run/slapd/slapd.pid

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

dn: cn={0}core,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: {0}core

dn: olcDatabase={0}config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: {0}config

dn: olcDatabase={1}mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: {1}mdb
olcDbDirectory: /var/lib/ldap
olcSuffix: $LDAP_BASE_DN
olcRootDN: cn=admin,$LDAP_BASE_DN
olcRootPW: $ADMIN_HASH
olcDbMaxSize: 524288
EOF
    
    echo "Adding minimal config..."
    slapadd -F /etc/ldap/slapd.d -n 0 -l /tmp/minimal-config.ldif
    
    echo "Setting permissions..."
    chown -R openldap:openldap /etc/ldap/slapd.d /var/lib/ldap
    
    echo "Minimal configuration created successfully"
fi

echo "Testing configuration..."
slaptest -F /etc/ldap/slapd.d -u

echo "Starting slapd with extreme debugging..."
exec slapd -d 65535 -h "ldap://0.0.0.0:389/" -F /etc/ldap/slapd.d -u openldap -g openldap