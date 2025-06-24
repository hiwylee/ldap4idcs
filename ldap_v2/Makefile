# OpenLDAP Docker Management Makefile

# 기본 변수들
COMPOSE_FILE = docker-compose.yml
CONTAINER_NAME = openldap_server
IMAGE_NAME = openldap:latest

# 기본 타겟
.PHONY: help
help:  ## 도움말 출력
	@echo "OpenLDAP Docker 관리 명령어:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build:  ## Docker 이미지 빌드
	docker-compose -f $(COMPOSE_FILE) build

.PHONY: up
up:  ## 서비스 시작 (백그라운드)
	docker-compose -f $(COMPOSE_FILE) up -d

.PHONY: down
down:  ## 서비스 중지
	docker-compose -f $(COMPOSE_FILE) down

.PHONY: restart
restart:  ## 서비스 재시작
	docker-compose -f $(COMPOSE_FILE) restart

.PHONY: logs
logs:  ## 로그 확인
	docker-compose -f $(COMPOSE_FILE) logs -f openldap

.PHONY: shell
shell:  ## 컨테이너 쉘 접속
	docker exec -it $(CONTAINER_NAME) /bin/bash

.PHONY: status
status:  ## 서비스 상태 확인
	docker-compose -f $(COMPOSE_FILE) ps

.PHONY: clean
clean:  ## 컨테이너와 이미지 정리
	docker-compose -f $(COMPOSE_FILE) down -v
	docker rmi $(IMAGE_NAME) 2>/dev/null || true

.PHONY: test-connection
test-connection:  ## LDAP 연결 테스트
	@echo "LDAP 서버 연결 테스트..."
	@docker exec $(CONTAINER_NAME) ldapsearch -x -H ldap://localhost:389 -b "dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -w Oracle_12345 "(objectClass=*)"

.PHONY: add-user
add-user:  ## 테스트 사용자 추가
	@echo "테스트 사용자 추가..."
	@docker exec -i $(CONTAINER_NAME) ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w Oracle_12345 << 'EOF'
	dn: uid=testuser,ou=people,dc=example,dc=com
	objectClass: inetOrgPerson
	objectClass: posixAccount
	objectClass: shadowAccount
	uid: testuser
	sn: User
	givenName: Test
	cn: Test User
	displayName: Test User
	uidNumber: 1001
	gidNumber: 1001
	userPassword: Oracle_12345
	gecos: Test User
	loginShell: /bin/bash
	homeDirectory: /home/testuser
	EOF

.PHONY: backup
backup:  ## LDAP 데이터 백업
	@echo "LDAP 데이터 백업 중..."
	@mkdir -p backups
	@docker exec $(CONTAINER_NAME) slapcat -F /etc/ldap/slapd.d -n 1 > backups/ldap-backup-$(shell date +%Y%m%d-%H%M%S).ldif
	@echo "백업 완료: backups/ldap-backup-$(shell date +%Y%m%d-%H%M%S).ldif"

.PHONY: restore
restore:  ## LDAP 데이터 복원 (BACKUP_FILE 변수 필요)
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "사용법: make restore BACKUP_FILE=backup.ldif"; \
		exit 1; \
	fi
	@echo "LDAP 데이터 복원 중..."
	@docker exec -i $(CONTAINER_NAME) slapadd -F /etc/ldap/slapd.d -n 1 -c < $(BACKUP_FILE)

.PHONY: reset
reset:  ## 모든 데이터 초기화 (주의!)
	@echo "모든 LDAP 데이터를 초기화하시겠습니까? [y/N]"
	@read -r REPLY; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		docker-compose -f $(COMPOSE_FILE) down -v; \
		docker volume rm $$(docker volume ls -q | grep ldap) 2>/dev/null || true; \
		echo "초기화 완료"; \
	else \
		echo "취소됨"; \
	fi