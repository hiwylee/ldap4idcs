#!/bin/bash
echo "=== OpenLDAP TLS 오류 수정 ==="

# 서비스 중지
make down 2>/dev/null || docker-compose down

# 볼륨 정리
docker volume rm oracle-iam_ldap-data oracle-iam_ldap-config 2>/dev/null || true

# 권한 수정
sudo chown -R $USER:$USER ldap-custom/ 2>/dev/null || true
chmod 755 ldap-custom/
chmod 644 ldap-custom/*.ldif 2>/dev/null || true

# 서비스 시작
make up

echo "수정 완료! LDAP 시작 대기 중..."
sleep 15

# 연결 테스트
docker-compose exec -T openldap ldapsearch -x -H ldap://localhost -b "dc=oracle,dc=com" -D "cn=admin,dc=oracle,dc=com" -w Oracle_12345
