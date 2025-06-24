# Oracle IAM Docker Makefile
# ==========================

# 변수 정의
COMPOSE_FILE = docker-compose.yml
PROJECT_NAME = oracle-iam
BACKUP_DIR = ./backup/$(shell date +%Y%m%d_%H%M%S)

# 기본 타겟
.PHONY: help build up down restart logs clean test backup restore

# 도움말
help:
	@echo "Oracle IAM Docker 관리 명령어"
	@echo "============================="
	@echo ""
	@echo "기본 명령어:"
	@echo "  make build     - Docker 이미지 빌드 (OpenAM)"
	@echo "  make up        - 서비스 시작"
	@echo "  make down      - 서비스 중지"
	@echo "  make restart   - 서비스 재시작"
	@echo "  make logs      - 로그 확인"
	@echo "  make ps        - 컨테이너 상태 확인"
	@echo ""
	@echo "관리 명령어:"
	@echo "  make clean     - 정리 (컨테이너, 이미지, 볼륨)"
	@echo "  make test      - 시스템 테스트 실행"
	@echo "  make backup    - 데이터 백업"
	@echo "  make restore   - 데이터 복구"
	@echo ""
	@echo "개발 명령어:"
	@echo "  make dev       - 개발 환경 시작"
	@echo "  make debug     - 디버그 모드 시작"

# 환경 설정
setup:
	@echo "Oracle IAM Docker 환경 설정 중..."
	@mkdir -p ldap-custom
	@echo "✓ 디렉토리 구조 생성 완료"
	@if [ ! -f .env ]; then \
		echo "COMPOSE_PROJECT_NAME=$(PROJECT_NAME)" > .env; \
		echo "✓ .env 파일 생성 완료"; \
	fi

# Docker 이미지 빌드 (OpenAM만)
build: setup
	@echo "OpenAM Docker 이미지 빌드 중..."
	docker-compose -f $(COMPOSE_FILE) build --no-cache openam openldap phpldapadmin
	@echo "✓ 빌드 완료"

# 서비스 시작 (기본 3개 서비스)
up: setup
	@echo "Oracle IAM 서비스 시작 중..."
	docker-compose -f $(COMPOSE_FILE) up -d openldap phpldapadmin openam
	@echo "✓ 서비스 시작 완료"
	@echo ""
	@echo "접속 정보:"
	@echo "- OpenAM:       http://localhost:8080/openam"
	@echo "- phpLDAPadmin: http://localhost:8081"

# 서비스 중지
down:
	@echo "Oracle IAM 서비스 중지 중..."
	docker-compose -f $(COMPOSE_FILE) down
	@echo "✓ 서비스 중지 완료"

# 서비스 재시작
restart:
	@echo "Oracle IAM 서비스 재시작 중..."
	docker-compose -f $(COMPOSE_FILE) restart
	@echo "✓ 서비스 재시작 완료"

# 로그 확인
logs:
	@echo "서비스 로그 (Ctrl+C로 종료):"
	docker-compose -f $(COMPOSE_FILE) logs -f

# 특정 서비스 로그
logs-openam:
	docker-compose -f $(COMPOSE_FILE) logs -f openam

logs-openldap:
	docker-compose -f $(COMPOSE_FILE) logs -f openldap

# 컨테이너 상태 확인
ps:
	@echo "컨테이너 상태:"
	docker-compose -f $(COMPOSE_FILE) ps
	@echo ""
	@echo "리소스 사용량:"
	docker stats --no-stream

# 개발 환경
dev: setup
	@echo "개발 환경 시작..."
	docker-compose -f $(COMPOSE_FILE) up -d
	@echo "✓ 개발 환경 시작 완료"

# 디버그 모드
debug: setup
	@echo "디버그 모드 시작..."
	docker-compose -f $(COMPOSE_FILE) up openldap openam phpldapadmin

# 시스템 테스트
test:
	@echo "시스템 테스트 실행 중..."
	@if [ -f "./scripts/system-verification.sh" ]; then \
		./scripts/system-verification.sh; \
	else \
		echo "scripts/system-verification.sh 스크립트가 없습니다."; \
		echo "setup.sh를 실행하여 스크립트를 생성하세요."; \
	fi

# 사용자 로그인 테스트
test-login:
	@echo "사용자 로그인 테스트..."
	@if [ -f "./scripts/user-login-test.sh" ]; then \
		./scripts/user-login-test.sh; \
	else \
		echo "scripts/user-login-test.sh 스크립트가 없습니다."; \
	fi

# SAML metadata export
metadata:
	@echo "SAML Metadata export..."
	@if [ -f "./scripts/metadata-export.sh" ]; then \
		./scripts/metadata-export.sh; \
	else \
		echo "scripts/metadata-export.sh 스크립트가 없습니다."; \
	fi

# 데이터 백업
backup:
	@echo "데이터 백업 중..."
	@mkdir -p $(BACKUP_DIR)
	@echo "백업 위치: $(BACKUP_DIR)"
	
	# OpenAM 데이터 백업
	@docker run --rm -v oracle-iam_openam-data:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		tar czf /backup/openam-data.tar.gz -C /data .
	
	# OpenLDAP 데이터 백업
	@docker run --rm -v oracle-iam_ldap-data:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		tar czf /backup/ldap-data.tar.gz -C /data .
	
	# OpenLDAP 설정 백업
	@docker run --rm -v oracle-iam_ldap-config:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		tar czf /backup/ldap-config.tar.gz -C /data .
	
	# 설정 파일 백업
	@cp docker-compose.yml $(BACKUP_DIR)/
	@cp .env $(BACKUP_DIR)/ 2>/dev/null || true
	
	@echo "✓ 백업 완료: $(BACKUP_DIR)"

# 데이터 복구
restore:
	@echo "데이터 복구를 위해 백업 디렉토리를 지정하세요:"
	@echo "make restore-from BACKUP_DIR=./backup/20231201_120000"

restore-from:
	@if [ -z "$(BACKUP_DIR)" ]; then \
		echo "오류: BACKUP_DIR을 지정해야 합니다."; \
		echo "예: make restore-from BACKUP_DIR=./backup/20231201_120000"; \
		exit 1; \
	fi
	@if [ ! -d "$(BACKUP_DIR)" ]; then \
		echo "오류: 백업 디렉토리가 존재하지 않습니다: $(BACKUP_DIR)"; \
		exit 1; \
	fi
	
	@echo "경고: 현재 데이터가 삭제됩니다!"
	@echo "복구할 백업: $(BACKUP_DIR)"
	@read -p "계속하시겠습니까? (y/N): " confirm; \
	if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then \
		echo "복구 취소됨"; \
		exit 0; \
	fi
	
	@echo "서비스 중지 중..."
	@make down
	
	@echo "데이터 복구 중..."
	@docker run --rm -v oracle-iam_openam-data:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		sh -c "cd /data && tar xzf /backup/openam-data.tar.gz"
	@docker run --rm -v oracle-iam_ldap-data:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		sh -c "cd /data && tar xzf /backup/ldap-data.tar.gz"
	@docker run --rm -v oracle-iam_ldap-config:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		sh -c "cd /data && tar xzf /backup/ldap-config.tar.gz"
	
	@echo "✓ 복구 완료"
	@echo "서비스를 시작하려면 'make up'을 실행하세요."

# 정리 작업
clean:
	@echo "정리 작업 중..."
	@echo "경고: 모든 컨테이너, 이미지, 볼륨이 삭제됩니다!"
	@read -p "계속하시겠습니까? (y/N): " confirm; \
	if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then \
		echo "정리 취소됨"; \
		exit 0; \
	fi
	
	@docker-compose -f $(COMPOSE_FILE) down -v --remove-orphans
	@docker system prune -af --volumes
	@echo "✓ 정리 완료"

# 소프트 정리 (볼륨 보존)
clean-soft:
	@docker-compose -f $(COMPOSE_FILE) down --remove-orphans
	@docker image prune -f
	@echo "✓ 소프트 정리 완료"

# 볼륨만 정리
clean-volumes:
	@echo "볼륨 정리 중..."
	@echo "경고: 모든 데이터가 삭제됩니다!"
	@read -p "계속하시겠습니까? (y/N): " confirm; \
	if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then \
		echo "볼륨 정리 취소됨"; \
		exit 0; \
	fi
	
	@docker-compose -f $(COMPOSE_FILE) down -v
	@docker volume prune -f
	@echo "✓ 볼륨 정리 완료"

# 환경 정보 출력
info:
	@echo "Oracle IAM Docker 환경 정보"
	@echo "=========================="
	@echo "프로젝트명: $(PROJECT_NAME)"
	@echo "Compose 파일: $(COMPOSE_FILE)"
	@echo ""
	@echo "시스템 정보:"
	@echo "- Docker 버전: $(docker --version)"
	@echo "- Docker Compose 버전: $(docker-compose --version)"
	@echo "- 시스템 메모리: $(free -h | grep Mem | awk '{print $2}')"
	@echo ""
	@echo "네트워크 포트:"
	@echo "- OpenLDAP:     389, 636"
	@echo "- OpenAM:       8080, 8443"
	@echo "- phpLDAPadmin: 8081"

# 업데이트
update:
	@echo "이미지 업데이트 중..."
	@docker-compose -f $(COMPOSE_FILE) pull
	@echo "✓ 이미지 업데이트 완료"
	@echo "변경사항을 적용하려면 'make restart'를 실행하세요."

# 기본 타겟
.DEFAULT_GOAL := help# Oracle IAM Docker Makefile
# ==========================

# 변수 정의
COMPOSE_FILE = docker-compose.yml
PROJECT_NAME = oracle-iam
BACKUP_DIR = ./backup/$(shell date +%Y%m%d_%H%M%S)

# 기본 타겟
.PHONY: help build up down restart logs clean test backup restore

# 도움말
help:
	@echo "Oracle IAM Docker 관리 명령어"
	@echo "============================="
	@echo ""
	@echo "기본 명령어:"
	@echo "  make build     - Docker 이미지 빌드"
	@echo "  make up        - 서비스 시작"
	@echo "  make down      - 서비스 중지"
	@echo "  make restart   - 서비스 재시작"
	@echo "  make logs      - 로그 확인"
	@echo "  make ps        - 컨테이너 상태 확인"
	@echo ""
	@echo "관리 명령어:"
	@echo "  make clean     - 정리 (컨테이너, 이미지, 볼륨)"
	@echo "  make test      - 시스템 테스트 실행"
	@echo "  make backup    - 데이터 백업"
	@echo "  make restore   - 데이터 복구"
	@echo ""
	@echo "개발 명령어:"
	@echo "  make dev       - 개발 환경 시작"
	@echo "  make prod      - 프로덕션 환경 시작"
	@echo "  make debug     - 디버그 모드 시작"
	@echo ""
	@echo "옵션 서비스:"
	@echo "  make with-nginx    - Nginx 포함하여 시작"
	@echo "  make with-cache    - Redis 캐시 포함하여 시작"
	@echo "  make with-logging  - ELK 스택 포함하여 시작"

# 환경 설정
setup:
	@echo "Oracle IAM Docker 환경 설정 중..."
	@mkdir -p data/ldap-data data/ldap-config data/openam-data
	@mkdir -p logs/openam logs/nginx
	@mkdir -p backup/ldap backup/openam
	@mkdir -p ldap-custom openam-custom nginx/conf.d
	@echo "✓ 디렉토리 구조 생성 완료"
	@if [ ! -f .env ]; then \
		echo "COMPOSE_PROJECT_NAME=$(PROJECT_NAME)" > .env; \
		echo "✓ .env 파일 생성 완료"; \
	fi

# Docker 이미지 빌드
build: setup
	@echo "Docker 이미지 빌드 중..."
	docker-compose -f $(COMPOSE_FILE) build --no-cache
	@echo "✓ 빌드 완료"

# 서비스 시작 (기본)
up: setup
	@echo "Oracle IAM 서비스 시작 중..."
	docker-compose -f $(COMPOSE_FILE) up -d openldap openam openldap openam
	@echo "✓ 서비스 시작 완료"
	@echo ""
	@echo "접속 정보:"
	@echo "- OpenAM:       http://localhost:8080/openam"
	#@echo "- phpLDAPadmin: http://localhost:8081"

# 서비스 중지
down:
	@echo "Oracle IAM 서비스 중지 중..."
	docker-compose -f $(COMPOSE_FILE) down
	@echo "✓ 서비스 중지 완료"

# 서비스 재시작
restart:
	@echo "Oracle IAM 서비스 재시작 중..."
	docker-compose -f $(COMPOSE_FILE) restart
	@echo "✓ 서비스 재시작 완료"

# 로그 확인
logs:
	@echo "서비스 로그 (Ctrl+C로 종료):"
	docker-compose -f $(COMPOSE_FILE) logs -f

# 특정 서비스 로그
logs-openam:
	docker-compose -f $(COMPOSE_FILE) logs -f openam

logs-openldap:
	docker-compose -f $(COMPOSE_FILE) logs -f openldap

# 컨테이너 상태 확인
ps:
	@echo "컨테이너 상태:"
	docker-compose -f $(COMPOSE_FILE) ps
	@echo ""
	@echo "리소스 사용량:"
	docker stats --no-stream

# Nginx 포함 시작
with-nginx: setup
	@echo "Nginx 리버스 프록시 포함하여 시작..."
	docker-compose -f $(COMPOSE_FILE) --profile nginx up -d
	@echo "✓ Nginx 포함 시작 완료"
	@echo "- HTTP 접속:  http://localhost"
	@echo "- HTTPS 접속: https://localhost"

# Redis 캐시 포함 시작
with-cache: setup
	@echo "Redis 캐시 포함하여 시작..."
	docker-compose -f $(COMPOSE_FILE) --profile cache up -d
	@echo "✓ Redis 캐시 포함 시작 완료"

# ELK 스택 포함 시작
with-logging: setup
	@echo "ELK 로깅 스택 포함하여 시작..."
	docker-compose -f $(COMPOSE_FILE) --profile logging up -d
	@echo "✓ ELK 스택 포함 시작 완료"
	@echo "- Kibana: http://localhost:5601"

# 개발 환경
dev: setup
	@echo "개발 환경 시작..."
	docker-compose -f $(COMPOSE_FILE) up -d
	@echo "✓ 개발 환경 시작 완료"

# 프로덕션 환경
prod: setup
	@echo "프로덕션 환경 시작..."
	docker-compose -f $(COMPOSE_FILE) --profile nginx up -d
	@echo "✓ 프로덕션 환경 시작 완료"

# 디버그 모드
debug: setup
	@echo "디버그 모드 시작..."
	docker-compose -f $(COMPOSE_FILE) up openldap openam openldap openam

# 시스템 테스트
test:
	@echo "시스템 테스트 실행 중..."
	@if [ -f "./system-verification.sh" ]; then \
		./system-verification.sh; \
	else \
		echo "system-verification.sh 스크립트가 없습니다."; \
		echo "가이드 문서에서 스크립트를 생성하세요."; \
	fi

# 사용자 로그인 테스트
test-login:
	@echo "사용자 로그인 테스트..."
	@if [ -f "./user-login-test.sh" ]; then \
		./user-login-test.sh; \
	else \
		echo "user-login-test.sh 스크립트가 없습니다."; \
	fi

# SAML metadata export
metadata:
	@echo "SAML Metadata export..."
	@if [ -f "./metadata-export.sh" ]; then \
		./metadata-export.sh; \
	else \
		echo "metadata-export.sh 스크립트가 없습니다."; \
	fi

# 데이터 백업
backup:
	@echo "데이터 백업 중..."
	@mkdir -p $(BACKUP_DIR)
	@echo "백업 위치: $(BACKUP_DIR)"
	
	# OpenAM 데이터 백업
	@docker run --rm -v oracle-iam_openam-data:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		tar czf /backup/openam-data.tar.gz -C /data .
	
	# OpenLDAP 데이터 백업
	@docker run --rm -v oracle-iam_ldap-data:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		tar czf /backup/ldap-data.tar.gz -C /data .
	
	# OpenLDAP 설정 백업
	@docker run --rm -v oracle-iam_ldap-config:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		tar czf /backup/ldap-config.tar.gz -C /data .
	
	# 설정 파일 백업
	@cp docker-compose.yml $(BACKUP_DIR)/
	@cp .env $(BACKUP_DIR)/ 2>/dev/null || true
	
	@echo "✓ 백업 완료: $(BACKUP_DIR)"

# 데이터 복구
restore:
	@echo "데이터 복구를 위해 백업 디렉토리를 지정하세요:"
	@echo "make restore-from BACKUP_DIR=./backup/20231201_120000"

restore-from:
	@if [ -z "$(BACKUP_DIR)" ]; then \
		echo "오류: BACKUP_DIR을 지정해야 합니다."; \
		echo "예: make restore-from BACKUP_DIR=./backup/20231201_120000"; \
		exit 1; \
	fi
	@if [ ! -d "$(BACKUP_DIR)" ]; then \
		echo "오류: 백업 디렉토리가 존재하지 않습니다: $(BACKUP_DIR)"; \
		exit 1; \
	fi
	
	@echo "경고: 현재 데이터가 삭제됩니다!"
	@echo "복구할 백업: $(BACKUP_DIR)"
	@read -p "계속하시겠습니까? (y/N): " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "복구 취소됨"; \
		exit 0; \
	fi
	
	@echo "서비스 중지 중..."
	@make down
	
	@echo "데이터 복구 중..."
	@docker run --rm -v oracle-iam_openam-data:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		sh -c "cd /data && tar xzf /backup/openam-data.tar.gz"
	@docker run --rm -v oracle-iam_ldap-data:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		sh -c "cd /data && tar xzf /backup/ldap-data.tar.gz"
	@docker run --rm -v oracle-iam_ldap-config:/data -v $(PWD)/$(BACKUP_DIR):/backup alpine \
		sh -c "cd /data && tar xzf /backup/ldap-config.tar.gz"
	
	@echo "✓ 복구 완료"
	@echo "서비스를 시작하려면 'make up'을 실행하세요."

# 정리 작업
clean:
	@echo "정리 작업 중..."
	@echo "경고: 모든 컨테이너, 이미지, 볼륨이 삭제됩니다!"
	@read -p "계속하시겠습니까? (y/N): " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "정리 취소됨"; \
		exit 0; \
	fi
	
	@docker-compose -f $(COMPOSE_FILE) down -v --remove-orphans
	@docker system prune -af --volumes
	@echo "✓ 정리 완료"

# 소프트 정리 (볼륨 보존)
clean-soft:
	@echo "소프트 정리 중 (볼륨 보존)..."
	@docker-compose -f $(COMPOSE_FILE) down --remove-orphans
	@docker image prune -f
	@echo "✓ 소프트 정리 완료"

# 볼륨만 정리
clean-volumes:
	@echo "볼륨 정리 중..."
	@echo "경고: 모든 데이터가 삭제됩니다!"
	@read -p "계속하시겠습니까? (y/N): " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "볼륨 정리 취소됨"; \
		exit 0; \
	fi
	
	@docker-compose -f $(COMPOSE_FILE) down -v
	@docker volume prune -f
	@echo "✓ 볼륨 정리 완료"

# 환경 정보 출력
info:
	@echo "Oracle IAM Docker 환경 정보"
	@echo "=========================="
	@echo "프로젝트명: $(PROJECT_NAME)"
	@echo "Compose 파일: $(COMPOSE_FILE)"
	@echo ""
	@echo "시스템 정보:"
	@echo "- Docker 버전: $$(docker --version)"
	@echo "- Docker Compose 버전: $$(docker-compose --version)"
	@echo "- 시스템 메모리: $$(free -h | grep Mem | awk '{print $$2}')"
	@echo ""
	@echo "네트워크 포트:"
	@echo "- OpenLDAP:     389, 636"
	@echo "- OpenAM:       8080, 8443"
	@echo "- phpLDAPadmin: 8081"

# 업데이트
update:
	@echo "이미지 업데이트 중..."
	@docker-compose -f $(COMPOSE_FILE) pull
	@echo "✓ 이미지 업데이트 완료"
	@echo "변경사항을 적용하려면 'make restart'를 실행하세요."

# 기본 타겟
.DEFAULT_GOAL := help