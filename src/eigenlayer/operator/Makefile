include .env

export $(shell sed 's/=.*//' .env)

start-db:
	docker-compose up --build

start-listener:
	yarn listener

start-worker:
	yarn worker
