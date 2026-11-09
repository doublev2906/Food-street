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

# Upload trang HTML lên /share (rsync qua SSH). Không --delete: giữ file upload qua UI.
#   make share                           # cả folder share/ (giữ nguyên cây thư mục)
#   make share DIR=bao-cao               # chỉ share/bao-cao/ -> server share/bao-cao/
#   make share FILE="a.html b.html"      # vài file lẻ -> thư mục gốc
#   make share FILE=a.html DIR=bao-cao   # file lẻ -> thư mục con (tự tạo nếu chưa có)
#   ... OVERWRITE=1                      # ghi đè file trùng tên (mặc định BỎ QUA file đã có
#                                        # trên server; dữ liệu người xem đã nhập vẫn giữ).
#                                        # So theo nội dung (--checksum): file cùng size+mtime
#                                        # nhưng khác nội dung vẫn được đè.
share: ## Upload HTML lên /share (FILE=…, DIR=thư/mục, OVERWRITE=1 để đè file trùng tên)
	$(if $(findstring ..,$(DIR)),$(error DIR không được chứa ".."))
	@. ./deploy.config && \
	  dest="$${APP_DIR:-/opt/food_street}/share/$(DIR)" && \
	  $(if $(DIR),ssh -p "$${SSH_PORT:-22}" "$${SSH_USER}@$${SSH_HOST}" "mkdir -p '$$dest'" &&) \
	  rsync -rtvz $(if $(OVERWRITE),--checksum,--ignore-existing) --exclude='.*' -e "ssh -p $${SSH_PORT:-22}" \
	    $(if $(FILE),$(FILE),share/$(if $(DIR),$(DIR)/)) \
	    "$${SSH_USER}@$${SSH_HOST}:$$dest/" && \
	  echo "==> $(if $(OVERWRITE),Đã ghi đè file trùng tên.,File trùng tên đã có trên server được giữ nguyên (OVERWRITE=1 để đè).)" && \
	  echo "==> Xem tại: $${SHARE_BASE_URL:-https://$${PHX_HOST:-$$SSH_HOST}}/share/$(if $(DIR),$(DIR)/)"

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
