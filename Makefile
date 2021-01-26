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
# Watchers
###########################################################
run:
	cd appserver; make build
	cd gateway; make build
	docker-compose up -d --force-recreate

watch: run
	watchspatch

appserver.rerun:
	docker-compose up -d --force-recreate simplecache
	sleep 2
	curl --request POST --url http://localhost:8080/v1/set --header 'user-agent: vscode-restclient' --data '{"Key": "hello","Value": "world"}'
gateway.rerun:
	docker-compose up -d --force-recreate gateway

reset-php:
	docker-compose exec simplecache ./appserver/appserver grpc:reset

vue:
	cd appserver/plugins/debugger/frontend; vue build
	rm -rf appserver/plugins/debugger/assets
	mv appserver/plugins/debugger/frontend/dist appserver/plugins/debugger/assets
