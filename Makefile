# =============================================================================
# Makefile thao tác PRODUCTION (Docker). Chạy DƯỚI MÁY DEV.
#
#   make deploy     # push code + build lại stack trên server
#   make share      # upload trang HTML trong share/ lên https://<host>/share/
#   make migrate    # chạy migration trên production
#   make attach     # mở IEx remote console vào backend đang chạy
#
# Đọc cấu hình server từ deploy.config (giống deploy.sh):
#   SSH_HOST, SSH_USER, SSH_PORT, APP_DIR
# (Backend dev: dùng backend/Makefile.)
# =============================================================================
.DEFAULT_GOAL := help
.PHONY: help deploy share migrate seed attach console logs ps restart rebuild down shell psql

COMPOSE := docker compose -f docker-compose.prod.yml

# Source deploy.config rồi SSH (forward agent -A để server git pull repo private).
SSH  := . ./deploy.config && ssh -A -p "$${SSH_PORT:-22}" "$${SSH_USER}@$${SSH_HOST}"
SSHT := . ./deploy.config && ssh -A -t -p "$${SSH_PORT:-22}" "$${SSH_USER}@$${SSH_HOST}"
RUN  := cd $${APP_DIR:-/opt/food_street} &&

help: ## Hiện danh sách lệnh
	@echo "Food Street — Production ops (chạy từ máy dev, đọc deploy.config)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

deploy: ## Deploy: push code + SSH server tự build lại (gọi ./deploy.sh)
	./deploy.sh

# Không --delete: giữ nguyên file admin đã upload qua UI trên server.
share: ## Upload trang HTML lên /share: rsync folder share/ (hoặc FILE="a.html b.html")
	@. ./deploy.config && \
	  rsync -rtvz --exclude='.*' -e "ssh -p $${SSH_PORT:-22}" \
	    $(if $(FILE),$(FILE),share/) \
	    "$${SSH_USER}@$${SSH_HOST}:$${APP_DIR:-/opt/food_street}/share/" && \
	  echo "==> Xem tại: $${SHARE_BASE_URL:-https://$${PHX_HOST:-$$SSH_HOST}}/share/"

migrate: ## Chạy migration trên production
	@$(SSH) "$(RUN) $(COMPOSE) exec -T backend /app/bin/migrate"

seed: ## Nạp seed dữ liệu mẫu trên production (idempotent)
	@$(SSH) "$(RUN) $(COMPOSE) exec -T backend /app/bin/seed"

attach: ## Mở IEx remote console vào node backend đang chạy
	@$(SSHT) "$(RUN) $(COMPOSE) exec backend /app/bin/food_street remote"

console: attach ## Alias của attach

logs: ## Theo dõi log backend (Ctrl-C để thoát)
	@$(SSHT) "$(RUN) $(COMPOSE) logs -f --tail=100 backend"

ps: ## Trạng thái các container
	@$(SSH) "$(RUN) $(COMPOSE) ps"

restart: ## Restart backend
	@$(SSH) "$(RUN) $(COMPOSE) restart backend"

rebuild: ## Build lại + khởi động lại toàn bộ stack
	@$(SSH) "$(RUN) $(COMPOSE) up -d --build"

down: ## Dừng toàn bộ stack (KHÔNG xóa dữ liệu)
	@$(SSH) "$(RUN) $(COMPOSE) down"

shell: ## Mở shell trong container backend
	@$(SSHT) "$(RUN) $(COMPOSE) exec backend /bin/sh"

psql: ## Mở psql vào DB production
	@$(SSHT) "$(RUN) $(COMPOSE) exec db sh -lc 'exec psql -U \$$POSTGRES_USER -d \$$POSTGRES_DB'"
