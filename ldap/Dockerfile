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
