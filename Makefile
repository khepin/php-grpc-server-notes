###########################################################
# Protobufs
###########################################################
proto_from_within_container:
	# PHP
	protoc /var/www/simplecache.proto \
		--php_out=/var/www/php-client/src \
		$(: 👇 custom plugin from roadrunner to generate server interface) \
		--php-grpc_out=/var/www/php-client/src \
		$(: 👇 generates the client code) \
		--grpc_out=/var/www/php-client/src \
		-I=/go/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.16.0/third_party/googleapis/ \
		--plugin=protoc-gen-grpc=/protobuf/grpc/bins/opt/grpc_php_plugin \
		--proto_path /var/www
	# Go (used to generate the Go Client, but also for grpc-gateway)
	mkdir -p /var/www/gateway/protos
	mkdir -p /var/www/swagger
	protoc /var/www/simplecache.proto \
		--proto_path /var/www \
		--go_out=paths=source_relative,plugins=grpc:./gateway/protos \
		-I=/go/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.16.0/third_party/googleapis/ \
		--swagger_out=logtostderr=true:./swagger \
		--grpc-gateway_out=logtostderr=true:gateway/protos
	mv gateway/protos/github.com/khepin/simplecache/protos/simplecache.pb.gw.go gateway/protos/simplecache.pb.gw.go
	rm -rf gateway/protos/github.com

proto:
	rm -rf php-client/src
	mkdir -p php-client/src
	docker-compose run proto make proto_from_within_container

###########################################################
# Go builds
###########################################################
build-appserver-server: appserver/appserver
appserver/appserver: $(wildcard appserver/**/*.go) $(wildcard appserver/*.go)
	docker-compose run proto make appserver_from_within_container
appserver_from_within_container:
	cd appserver && go build -o appserver

build-gateway-server: gateway/gateway
gateway/gateway: $(wildcard gateway/**/*.go) $(wildcard gateway/*.go)
	docker-compose run proto make gateway_from_within_container
gateway_from_within_container:
	cd gateway && go build -o gateway

###########################################################
# Watchers
###########################################################
run: build-gateway-server build-appserver-server
	docker-compose up -d --force-recreate

watch: run
	make watch-php &
	make watch-gateway &
	make watch-appserver

watch-php:
	watchexec -w app -- make reset
watch-gateway:
	watchexec -w gateway -i gateway/gateway -- make rerun-gateway-server
watch-appserver:
	watchexec -w appserver -i appserver/appserver -- make rerun-appserver-server

rerun-gateway-server: build-gateway-server
	docker-compose up -d --force-recreate gateway
rerun-appserver-server: build-appserver-server
	docker-compose up -d --force-recreate simplecache

reset:
	docker-compose exec -T simplecache ./appserver/appserver grpc:reset
