###########################################################
# Build
###########################################################
build: gateway
gateway: $(shell find . -type f -name "*.go")
	docker-compose exec proto sh -c "cd gateway; make gateway_from_within_container"
gateway_from_within_container:
	go build -o gateway-server
	mv gateway-server gateway
