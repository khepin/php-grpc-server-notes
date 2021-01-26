package main

import (
	grpc "github.com/spiral/php-grpc"
	rr "github.com/spiral/roadrunner/cmd/rr/cmd"
	"github.com/spiral/roadrunner/service/limit"
	"github.com/spiral/roadrunner/service/metrics"
	"github.com/spiral/roadrunner/service/rpc"

	// grpc specific commands
	_ "github.com/spiral/php-grpc/cmd/rr-grpc/grpc"

	"github.com/khepin/rr-appserver/plugins/debugger"
)

func main() {
	rr.Container.Register(rpc.ID, &rpc.Service{})
	rr.Container.Register(grpc.ID, &grpc.Service{})

	rr.Container.Register(metrics.ID, &metrics.Service{})
	rr.Container.Register(limit.ID, &limit.Service{})

	// Custom services
	// --------------------------------------------
	rr.Container.Register(debugger.ID, &debugger.Service{})

	rr.Execute()
}
