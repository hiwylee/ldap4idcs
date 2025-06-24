FROM debian:11-slim

# 패키지 설치
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    slapd \
    ldap-utils \
    && rm -rf /var/lib/apt/lists/*

# 디렉토리 생성
RUN mkdir -p /var/lib/ldap /var/run/slapd /etc/ldap/slapd.d

# OpenLDAP 사용자 및 그룹 생성 (이미 존재할 수 있음)
RUN groupadd -r openldap 2>/dev/null || true && \
    useradd -r -g openldap -d /var/lib/ldap -s /bin/false openldap 2>/dev/null || true

# 초기 설정 파일 복사
#COPY init-config.ldif /tmp/
#COPY init-data.ldif /tmp/
COPY entrypoint.sh /usr/local/bin/

# 실행 권한 부여
RUN chmod +x /usr/local/bin/entrypoint.sh

# 포트 노출
EXPOSE 389 636

# 볼륨 설정
VOLUME ["/var/lib/ldap", "/etc/ldap/slapd.d"]

# 엔트리포인트 설정
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
