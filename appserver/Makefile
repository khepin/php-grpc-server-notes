###########################################################
# Build
###########################################################
build: appserver
appserver: $(shell find . -type f -name "*.go")
	docker-compose exec proto sh -c "cd appserver; make appserver_from_within_container"
appserver_from_within_container:
	go build -o appserver-server
	mv appserver-server appserver

assets:
	pkger -include /plugins/debugger/assets
