package debugger

import (
	"container/ring"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/markbates/pkger"
	"github.com/spiral/roadrunner/service"
	"github.com/spiral/roadrunner/service/rpc"
)

const ID = "debugger"

type Service struct {
	Config *Config
	Buffer *ring.Ring
	echo   *echo.Echo
}

func (s *Service) Init(r *rpc.Service, cfg *Config) (ok bool, err error) {
	s.Config = cfg
	s.Buffer = ring.New(int(cfg.HistorySize))

	r.Register("debugger", &rpcService{Service: s})

	s.prepareHttp()

	return true, nil
}

func (s *Service) Serve() error {
	fmt.Println("starting http server")
	return s.echo.Start(s.Config.Address)
}

func (s *Service) Stop() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	s.Buffer = ring.New(int(s.Config.HistorySize))
	s.echo.Shutdown(ctx)
}

func (s *Service) prepareHttp() {
	e := echo.New()

	// Static files
	e.GET("/", echo.WrapHandler(http.FileServer(pkger.Dir("/plugins/debugger/assets"))))
	e.GET("/index.html", echo.WrapHandler(http.FileServer(pkger.Dir("/plugins/debugger/assets"))))
	e.GET("/css/*", echo.WrapHandler(http.FileServer(pkger.Dir("/plugins/debugger/assets"))))
	e.GET("/js/*", echo.WrapHandler(http.FileServer(pkger.Dir("/plugins/debugger/assets"))))

	e.GET("/debuglogs", func(c echo.Context) error {
		out := []map[string]interface{}{}
		s.Buffer.Do(func(item interface{}) {
			s, ok := item.(map[string]interface{})
			if !ok {
				return
			}
			out = append(out, s)
		})

		return c.JSON(http.StatusOK, out)
	})

	s.echo = e
}

type Config struct {
	HistorySize uint
	Address     string
}

func (c *Config) Hydrate(cfg service.Config) error {
	return cfg.Unmarshal(&c)
}

type rpcService struct {
	Service *Service
}

func (ps *rpcService) SendDebugInfo(input string, output *string) error {
	*output = "OK"
	v := map[string]interface{}{}
	json.Unmarshal([]byte(input), &v)
	ps.Service.Buffer.Value = v
	ps.Service.Buffer = ps.Service.Buffer.Prev()

	return nil
}
