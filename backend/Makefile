.DEFAULT_GOAL := help
.PHONY: help setup deps server s iex test format migrate rollback seed reset secret \
        up upd down down-v build rebuild logs ps sh psql restart dmigrate dseed dreset \
        diex dconsole

# ====== Local (mix) ======

help: ## Hiện danh sách lệnh
	@echo "Food Street — Backend (port 4003)"
	@echo ""
	@echo "Local (mix):"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v DOCKER | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## Cài deps + tạo DB + migrate + seed
	mix setup

deps: ## Tải dependencies
	mix deps.get

server s: ## Chạy Phoenix server (port 4003)
	mix phx.server

iex: ## Chạy server trong IEx
	iex -S mix phx.server

test: ## Chạy test
	mix test

format: ## Format code
	mix format

migrate: ## Chạy migrations
	mix ecto.migrate

rollback: ## Rollback migration gần nhất
	mix ecto.rollback

seed: ## Nạp dữ liệu mẫu
	mix run priv/repo/seeds.exs

reset: ## Drop + tạo lại + migrate + seed DB
	mix ecto.reset

secret: ## Sinh SECRET_KEY_BASE
	mix phx.gen.secret

# ====== Docker (dev) ======  DOCKER

up: ## [docker] Chạy stack (foreground)
	docker compose up

upd: ## [docker] Chạy stack (nền)
	docker compose up -d

down: ## [docker] Dừng stack
	docker compose down

down-v: ## [docker] Dừng + xóa dữ liệu DB
	docker compose down -v

build: ## [docker] Build image
	docker compose build

rebuild: ## [docker] Build lại không cache
	docker compose build --no-cache

logs: ## [docker] Xem log backend
	docker compose logs -f backend

ps: ## [docker] Trạng thái container
	docker compose ps

sh: ## [docker] Mở shell trong container backend
	docker compose exec backend bash

psql: ## [docker] Mở psql vào DB
	docker compose exec db psql -U postgres -d food_street_dev

restart: ## [docker] Khởi động lại backend
	docker compose restart backend

diex: ## [docker] Chạy server TRONG IEx (tương tác + log). Dùng THAY cho `up`.
	docker compose run --rm --service-ports backend iex -S mix phx.server

dconsole: ## [docker] Mở IEx console gắn vào stack ĐANG chạy (chạy query, không bật web)
	docker compose exec backend iex -S mix

dmigrate: ## [docker] Chạy migrations trong container
	docker compose exec backend mix ecto.migrate

dseed: ## [docker] Nạp seed trong container
	docker compose exec backend mix run priv/repo/seeds.exs

dreset: ## [docker] Reset DB trong container
	docker compose exec backend mix ecto.reset
