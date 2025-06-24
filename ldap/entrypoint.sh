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
echo "Starting OpenLDAP server..."
exec "$@"
