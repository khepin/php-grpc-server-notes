# Building a gRPC server in PHP

**A series of notes / a rough tutorial**

PHP "doesn't have support for building gRPC servers". This is true if using traditional ways of running PHP (via Apache, NGINX, PHP-FPM ...).
RoadRunner is a Go server that offers a different way to run PHP applications and will allow us to create a gRPC server in PHP.

The code is available at https://github.com/khepin/php-grpc-server-notes

## How RoadRunner works

The Go RoadRunner server will run a couple of PHP workers. .f you've ever built a message queue consumer in PHP, also called queue workers or jobs sometimes, this is the same thing: a long running PHP process waiting to process messages.

There are 2 distinctions between RoadRunner workers and the ones you might have already built for queues:
1. The delivery mechanism.
RoadRunner workers do not receive the payload to work on from a queue or message broker but from RoadRunner via either:
- Standard Input (STDIN) of the running PHP script
- TCP
- Local unix socket
2. They can return a response. Most of the time in PHP, queue workers are used to offload some work that can happen in the background. There is no client waiting for a response. In the case of RoadRunner workers, a response is expected.

## RoadRunner and HTTP

RoadRunner can run your workers to respond to HTTP requests. There's even integrations available for Symfony, Laravel and a host of other frameworks.

Since with RoadRunner you have a long running PHP process responding to your requests, you can achieve much higher performance as you don't have to reload everything for each request for example:
- no need to reload the PHP code responding to the request (though opcode cache makes this step very low cost on more traditional servers for PHP)
- no need to re-connect to your database on every request (PHP allows persistent DB connections, but they're rarely used. Connecting to a DB that has SSL enabled has a significant cost here, usually higher than 10ms)
- possibility to share a common Guzzle Client so that if you need to connect to a remote HTTP service, the underlying connection doesn't need to be reset all the time. Here again, creating a brand new HTTPS connection has a non-trivial cost and latency.

Here, we're not so interested in our ability to run HTTP applications, but more in the possibility of creating a gRPC server in PHP.

## gRPC

### Service definition

We'll create a very simple cache service. This will only have 3 methods: Get, Set and Delete. This will be enough for us to demonstrate how to build a gRPC server without creating a complex project.

gRPC service definitions are done via protobuf and in this case our protobuf file is going to look like this:

```proto
//simplecache.proto
syntax="proto3";
package simplecache;

option php_namespace="Khepin\\SimpleCache";
option php_metadata_namespace="Khepin\\SimpleCache\\Meta";

message SetRequest {
    string Key = 1;
    string Value = 2;
}

message SetResponse {
    bool OK = 1;
}

message DelRequest {
    string Key = 1;
}

message DelResponse {
    bool OK = 1;
}

message GetRequest {
    string Key = 1;
}

message GetResponse {
    string Key = 1;
    string Value = 2;
}

service SimpleCache {
    rpc Set(SetRequest) returns (SetResponse);
    rpc Del(DelRequest) returns (DelResponse);
    rpc Get(GetRequest) returns (GetResponse);
}
```

### Code generation

We can now generate the PHP code. For this we need:
- the `protoc` protobuf compiler
- the `protobuf-grpc` plugin (to generate a gRPC PHP client)
- the RoadRunner grpc plugin (generates the server side server interface)

To avoid having to install everything on your machine, we'll use `docker-compose` and a custom Dockerfile. At this stage, docker-compose should look like this:

```yaml
version: '2'

services:
  proto:
    build:
      dockerfile: Dockerfile-proto
      context: .
    working_dir: /var/www
    volumes:
      - .:/var/www
```

And the Dockerfile:

⚠️ This is not exactly how you'd normaly write a Dockerfile. You would typically reduce everything down to a single `RUN` and a multi-line script. This is not a topic for this time.

```Dockerfile
# Dockerfile-proto
FROM golang:1.15

ARG PROTOBUF_VERSION=3.14.0
ARG PHP_GRPC_VERSION=1.34.0

# Utils
RUN apt-get update
RUN apt-get install unzip
# Protobuf
RUN mkdir -p /protobuf
RUN cd /protobuf \
    && wget https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protoc-${PROTOBUF_VERSION}-linux-x86_64.zip -O protobuf.zip \
    && unzip protobuf.zip && rm protobuf.zip

# grpc PHP (generate client)
RUN apt-get install php php-dev php-pear phpunit zlib1g-dev -y
RUN pecl install grpc-${PHP_GRPC_VERSION}
RUN cd /protobuf && git clone -b v${PHP_GRPC_VERSION} https://github.com/grpc/grpc \
    && cd /protobuf/grpc && git submodule update --init
RUN apt-get install autoconf libtool automake build-essential -y
RUN cd /protobuf/grpc && make grpc_php_plugin

# RoadRunner's custom PHP gRPC plugin (server interface definition)
RUN apt-get install -y git
RUN git clone https://github.com/spiral/php-grpc.git
RUN cd php-grpc/cmd/rr-grpc && go install
RUN cd php-grpc/cmd/protoc-gen-php-grpc && go install

ENV PATH "/protobuf/bin:${PATH}"
```

The command to build the generated PHP protobuf code isn't something you'd remember how to type each time, so we'll start a Makefile with that build command:

```Makefile
# Makefile

# Note `$(: a b c)` allows to put a comment in the middle of a bash command
proto_from_within_container:
	# PHP
	protoc /var/www/simplecache.proto \
		--php_out=/var/www/php-client/src \
		$(: 👇 custom plugin from roadrunner to generate server interface) \
		--php-grpc_out=/var/www/php-client/src \
		$(: 👇 generates the client code) \
		--grpc_out=/var/www/php-client/src \
		--plugin=protoc-gen-grpc=/protobuf/grpc/bins/opt/grpc_php_plugin \
		--proto_path /var/www

proto:
	rm -rf php-client/src
	mkdir -p php-client/src
	docker-compose run proto make proto_from_within_container
```

Now we can just run `make proto` to generate our PHP code. Note that in this case we have generated all the protobuf classes as well as the client and the server interface definition under `php-client`.

⚠️ The first run will build your docker image which will take a while (10 to 20 minutes for me).

Let's look at the generated server interface:

```php
<?php
# Generated by the protocol buffer compiler (spiral/php-grpc). DO NOT EDIT!
# source: simplecache.proto

namespace Khepin\SimpleCache;

use Spiral\GRPC;

interface SimpleCacheInterface extends GRPC\ServiceInterface
{
    // GRPC specific service name.
    public const NAME = "simplecache.SimpleCache";

    /**
    * @param GRPC\ContextInterface $ctx
    * @param SetRequest $in
    * @return SetResponse
    *
    * @throws GRPC\Exception\InvokeException
    */
    public function Set(GRPC\ContextInterface $ctx, SetRequest $in): SetResponse;

    /**
    * @param GRPC\ContextInterface $ctx
    * @param DelRequest $in
    * @return DelResponse
    *
    * @throws GRPC\Exception\InvokeException
    */
    public function Del(GRPC\ContextInterface $ctx, DelRequest $in): DelResponse;

    /**
    * @param GRPC\ContextInterface $ctx
    * @param GetRequest $in
    * @return GetResponse
    *
    * @throws GRPC\Exception\InvokeException
    */
    public function Get(GRPC\ContextInterface $ctx, GetRequest $in): GetResponse;
}
```

For other apps to be able to use this client code, you would then have multiple choices:
- make this a repo of its own with its own `composer.json`
- make a git submodule for `php-client` again, defining its own `composer.json`

In this case since we will keep everything local under the same repository / directory, we'll define a global `composer.json` and will not concern ourselves with making the client code itself available to other apps.

### PHP Setup

Let's define our `composer.json` for the app:

```json
{
    "require": {
        "spiral/roadrunner": "^1.9",
        "composer/package-versions-deprecated": "1.11.99.1",
        "spiral/php-grpc": "^1.4",
        "grpc/grpc": "^1.34"
    },
    "autoload": {
        "psr-4": {
            "App\\": "app",
            "Khepin\\SimpleCache\\": "php-client/src/Khepin/SimpleCache"
        }
    }
}

```

We need the protobuf and gRPC extensions enabled for PHP, so we'll use the base PHP image and a custom Dockerfile again. We add the following service to `docker-compose.yaml`

```yaml
  # ...
  simplecache:
    image: php:7.4-cli
    build:
      dockerfile: Dockerfile-app
      context: .
    working_dir: /var/www
    ports:
      - 9090:9090
    volumes:
      - .:/var/www
```

The dockerfile will be:

```Dockerfile
# Dockerfile-app
FROM php:7.4-cli

# Extensions
RUN echo starting && \
    docker-php-ext-enable grpc && \
    docker-php-ext-enable protobuf
```

We can now install our PHP dependencies and generate our autoloader with `docker-compose run simplecache composer install`

### PHP Service

Our service implementation is fairly straightforward, the service is instantiated with an empty array property and will store, serve and remove values as requested.

⚠️ This is definitely not meant to be used "for real", there's no checks around how much memory is used, whether they keys / values are valid, should be stored or ignored, there's no shared memory between the workers, so you don't have 1 but multiple independent caches etc...

```php
<?php declare(strict_types=1);

namespace App\GRPC;

use Khepin\SimpleCache\DelRequest;
use Khepin\SimpleCache\DelResponse;
use Khepin\SimpleCache\GetRequest;
use Khepin\SimpleCache\GetResponse;
use Khepin\SimpleCache\SetRequest;
use Khepin\SimpleCache\SetResponse;
use Khepin\SimpleCache\SimpleCacheInterface;
use Spiral\GRPC\ContextInterface;
use Spiral\GRPC\Exception\NotFoundException;

class SimpleCacheService implements SimpleCacheInterface
{
    protected $storage = [];

    public function Set(ContextInterface $ctx, SetRequest $in): SetResponse
    {
        $this->storage[$in->getKey()] = $in->getValue();
        return new SetResponse(['OK' => true]);
    }

    public function Del(ContextInterface $ctx, DelRequest $in): DelResponse
    {
        unset($this->storage[$in->getKey()]);
        return new DelResponse(['OK' => true]);
    }

    public function Get(ContextInterface $ctx, GetRequest $in): GetResponse
    {
        if (!array_key_exists($in->getKey(), $this->storage)) {
            throw new NotFoundException();
        }

        return new GetResponse([
            'Key' => $in->getKey(),
            'Value' => $this->storage[$in->getKey()] ?? null,
        ]);
    }
}
```

Each method follows the definition from the interface, itself derived from the protobuf service definition. It takes in the given request type and returns the correct response type.
The first argument is always a `Context` which can be used to set and retrieve additional data from the request for example. It's used to read request headers / metadata. It's also used to add
response headers / metadata.

The `NotFoundException` is provided by the `Spiral\Grpc` framework and will result in a gRPC NotFound code being returned to the client.

### The gRPC worker

We said earlier that RoadRunner manages php workers. Let's define our PHP worker for this gRPC service:

```php
<?php declare(strict_types=1);
//worker.grpc.php

use App\GRPC\SimpleCacheService;
use Khepin\SimpleCache\SimpleCacheInterface;
use Spiral\Goridge\StreamRelay;
use Spiral\RoadRunner\Worker;

ini_set('display_errors', 'stderr'); // error_log will be reflected properly in roadrunner logs
require "vendor/autoload.php";

//To run server in debug mode - new \Spiral\GRPC\Server(null, ['debug' => true]);
$server = new \Spiral\GRPC\Server();

// Register our cache service
$server->registerService(SimpleCacheInterface::class, new SimpleCacheService());

// RoadRunner to PHP communication will happen over stdin and stdout pipes
$relay = new StreamRelay(STDIN, STDOUT);
$w = new Worker($relay);
$server->serve($w);
```

### Building the app server

To run RoadRunner gRPC, you can either download a pre-built binary from https://github.com/spiral/php-grpc/releases or build it. We'll be building our own for 2 reasons:

- The latest version tagged in the repo: 1.4.2, doesn't have the pre-built binaries
- Building your own allows you to create Go code that can be called directly from PHP which we might explore later on

First off, let's create a directory for our appserver code: `mkdir appserver`

The appserver (and roadrunner) are built in Go. You might not have Go installed on your machine. In this case, we can use the `proto` container we defined earlier since it's using the base Go image.

We need to run this one time to initialize the appserver go module.

```bash
# exec into the proto container
docker-compose run proto bash
# navigate to appserver directory
cd appserver
# Create a go module for our app server (change `khepin` for your own username)
go mod init github.com/khepin/rr-appserver
touch main.go
```

We can then update `main.go` with the following content:

```go
package main

import (
	grpc "github.com/spiral/php-grpc"
	rr "github.com/spiral/roadrunner/cmd/rr/cmd"
	"github.com/spiral/roadrunner/service/limit"
	"github.com/spiral/roadrunner/service/metrics"
	"github.com/spiral/roadrunner/service/rpc"

	// grpc specific commands
	_ "github.com/spiral/php-grpc/cmd/rr-grpc/grpc"
)

func main() {
	rr.Container.Register(rpc.ID, &rpc.Service{})
	rr.Container.Register(grpc.ID, &grpc.Service{})

	rr.Container.Register(metrics.ID, &metrics.Service{})
	rr.Container.Register(limit.ID, &limit.Service{})

	rr.Execute()
}
```

The build instructions are added to our `Makefile`:

```Makefile
# easy to remember rule name
build-appserver-server: appserver/appserver
# actual rule with dependencies on any `go` file within `appserver/*` being updated
appserver/appserver: $(wildcard appserver/**/*.go) $(wildcard appserver/*.go)
	docker-compose run proto make appserver_from_within_container
appserver_from_within_container:
	cd appserver && go build -o appserver
```

Now `make build-appserver-server` will out put `appserver/appserver`.

### Running our gRPC service

We create a `.rr.yaml` config file to define how roadrunner should run the service:

```yaml
# Enable RoadRunner's rpc. Used for restarting the workers in our case
rpc:
  enable: true
  listen: tcp://127.0.0.1:6001

# gRPC params
grpc:
  listen: "tcp://:9090" # gRPC is enabled on port 9090
  proto: "simplecache.proto"
  workers:
    command: "php worker.grpc.php"
    pool:
      numWorkers: 1 # Since we have a cache that's based on an instance variable, we can only have 1 worker for this sample scenario
```

We can now update `docker-compose.yaml` to run RoadRunner and our server

```yaml
version: '2'

services:
  simplecache:
    # ...
    command: ./appserver/appserver serve -v -d
```

Now when we call `docker-compose up` we should see roadrunner starting and giving us the following output:

```
simplecache_1  | DEBU[0000] [metrics]: disabled
simplecache_1  | DEBU[0000] [rpc]: started
simplecache_1  | DEBU[0000] [grpc]: started
```

### A PHP Client

To try it, we need to be able to make a gRPC request. We'll create a simple PHP client to test that things are working properly:

`testclient.php`
```php
use Khepin\SimpleCache\SimpleCacheClient;

require "vendor/autoload.php";

use Grpc\ChannelCredentials;
use Khepin\SimpleCache\DelRequest;
use Khepin\SimpleCache\GetRequest;
use Khepin\SimpleCache\SetRequest;
use Spiral\GRPC\StatusCode;

$client = new SimpleCacheClient(
    'localhost:9090',
    [
        'credentials' => ChannelCredentials::createInsecure(),
    ]
);

[$response, $status] = $client->Set(new SetRequest(['Key' => 'hello', 'Value' => 'world']))->wait();
echo "================== SET ==================\n";
echo $response->getOK() === true, "\n";

[$response, $status] = $client->Get(new GetRequest(['Key' => 'hello']))->wait();
echo "================== GET ==================\n";
echo $response->getKey(), " : ", $response->getValue(), "\n";

[$response, $status] = $client->Del(new DelRequest(['Key' => 'hello']))->wait();
echo "================== DEL ==================\n";
echo $response->getOK() === true, "\n";

[$response, $status] = $client->Get(new GetRequest(['Key' => 'hello']))->wait();
echo "================== GET ==================\n";
echo $status->code === StatusCode::NOT_FOUND, "\n";
```

You can now exec into the app container to run the client code:

```bash
$ docker-compose exec simplecache bash
root@9db54706$ php testclient.php
```

Which should give the following output:

```
================== SET ==================
1
================== GET ==================
hello : world
================== DEL ==================
1
================== GET ==================
1
```

## gRPC Gateway

The gRPC ecosystem has created gRPC Gateway as a way to use gRPC / protobuf APIs over HTTP / json. To set it up, we need to:

- generate the Go gRPC code
- create a gateway server (in Go)
- Point it to the remote gRPC server

This could be done as a separate server or within our appserver by listening on a separate port. Here we'll show how to create it as a separate service. All the code for the gateway will go in `mkdir gateway`. Then similar to how we created the appserver module earlier, we'll create a module for the gateway:

`go mod init github.com/khepin/simplecache/gateway`.

And we'll add similar build targets in the `Makefile`:

```Makefile
build-gateway-server: gateway/gateway
gateway/gateway: $(wildcard gateway/**/*.go) $(wildcard gateway/*.go)
	docker-compose run proto make gateway_from_within_container
gateway_from_within_container:
	cd gateway && go build -o gateway
```

Before we can write the gateway code, we need to generate the Golang protobuf code.

### Golang Protobuf Generation

In our `Dockerfile-proto`, we'll add the required `Go` dependencies:

`Dockerfile-proto`
```Dockerfile
#...

ARG GOLANG_GRPC_VERSION=1.4.3

#...

# grpc Go
RUN mkdir -p /mock-go-module
RUN cd /mock-go-module \
    && go mod init mockmodule \
    && go get github.com/golang/protobuf/protoc-gen-go@v${GOLANG_GRPC_VERSION} \
    && go get -u github.com/golang/protobuf/protoc-gen-go
# grpc-gateway
RUN cd /mock-go-module \
    && go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway \
    && go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger

RUN cd /protobuf \
    && rm -rf /mock-go-module
```

The proto definition also needs to be updated with the name of the go package to generate code for:

```proto
option go_package="github.com/khepin/simplecache/gateway/protos";
```

With this in place we can update the `Makefile` to build the Go output

```Makefile
proto_from_within_container:
	# PHP
    # ...
	# Go (used to generate the Go Client, but also for grpc-gateway)
	mkdir -p /var/www/gateway/protos
	mkdir -p /var/www/swagger
	protoc /var/www/simplecache.proto \
		--proto_path /var/www \
		--go_out=paths=source_relative,plugins=grpc:./gateway/protos \
		-I/go/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.16.0/third_party/googleapis/ \
		--swagger_out=logtostderr=true:./swagger \
		--grpc-gateway_out=logtostderr=true:gateway/protos
```

When running `make proto`, we now get generated go code at `gateway/protos/simplecache.pb.go`. We're sill missing the gateway definition. This is because it needs to be first configured properly in the proto service definition. Eg: which method maps to an HTTP POST or DELETE or GET, how does the proto request map to the json body and query string params etc...

### Gateway definition

Our proto definition becomes:

```proto
// ...

import "google/api/annotations.proto";

// ...

service SimpleCache {
    rpc Set(SetRequest) returns (SetResponse) {
        option (google.api.http) = {
            post: "/v1/set",
            body: "*"
        };
    };
    rpc Del(DelRequest) returns (DelResponse) {
        option (google.api.http) = {
            post: "/v1/del",
            body: "*"
        };
    };
    rpc Get(GetRequest) returns (GetResponse) {
        option (google.api.http) = {
            post: "/v1/get",
            body: "*"
        };
    };
}
```

Since I don't want to dive too much into how things are mapped between the HTTP request body vs query string parameters, I've kept everything as a POST where the Request object represents the entire HTTP body. This is not your only option though and if your goal is not to simply expose your RPC service over HTTP but to define an actual REST interface making good use of the right HTTP verbs in the right place, that is possible and I encourage you to look into https://grpc-ecosystem.github.io/grpc-gateway/ for more information.

We again update our build command in the Makefile:

```Makefile
proto_from_within_container:
	# PHP
	protoc /var/www/simplecache.proto \
		--php_oËout=/var/www/php-client/src \
		$(: ...) \
		-I=/go/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.16.0/third_party/googleapis/ \
		$(: ...)
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
```

With this in place, we've generated a swagger definition for our API: `swagger/simplecache.swagger.json` and can start creating the gateway server. Here's the Go code for that:

```go
package main

import (
	"context"
	"net/http"

	"github.com/grpc-ecosystem/grpc-gateway/runtime"
	"github.com/khepin/simplecache/gateway/protos"
	"github.com/sirupsen/logrus"
	"google.golang.org/grpc"
)

func main() {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	mux := runtime.NewServeMux()
	opts := []grpc.DialOption{grpc.WithInsecure()}
	err := protos.RegisterSimpleCacheHandlerFromEndpoint(ctx, mux, "simplecache:9090", opts)
	if err != nil {
		logrus.Fatal(err)
	}
	logrus.Info("endpoint created")

	logrus.Info("listening")
	err = http.ListenAndServe(":8080", mux)
	if err != nil {
		logrus.Fatal(err)
	}
}
```

And in `docker-compose.yaml` we add the gateway service:

```yaml
  gateway:
    image: golang:latest
    command: ./gateway
    working_dir: /var/www
    volumes:
      - ./gateway:/var/www
    ports:
      - 8080:8080
```

Before we can run our HTTP test, we still need to request the http protobuf definitions for PHP: `composer require google/common-protos`

We can now access our API via HTTP on localhost:8080. For example:

Set:
```
curl --request POST \
  --url http://localhost:8080/v1/set \
  --data '{"Key": "hello","Value": "world"}'
```

Get:
```
curl --request POST \
  --url http://localhost:8080/v1/get \
  --data '{"Key": "hello"}'
```

## Auto-Reloading

With all this built, we're missing something key to PHP. When you change a PHP file, you can just go to your browser, hit refresh and see the new code running. This isn't the case here, you might have to rebuild many things when you change appserver code or gateway code or PHP code.

To regain PHP's ease here, we'll make use of `watchexec` (see: https://github.com/watchexec/watchexec) and a couple Makefile rules. Here's what I use:

```Makefile
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
```

With this in place, updating any file in your codebase should rebuild or restart the required services, making sure you're always running up to date code with your latest changes.

## OMG What have we done?

This should give you a headstart in your explorations of making gRPC servers in PHP. Here are some things I plan to keep exploring / write about on this topic:

- using headers (request & response) for metadata
- handling errors
- building Go services to use from PHP
