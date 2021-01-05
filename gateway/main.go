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
