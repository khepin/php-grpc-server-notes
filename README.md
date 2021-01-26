# Building a debugger Go plugin for Roadrunner

Roadrunner is a PHP application server written in Go. I'm principally interested in this technology for 2 main reasons:
- performance: since it keeps your PHP code running in a loop, you don't need to recreate the world on every request. This requires much more careful coding but can have a massive impact on performance.
- gRPC: it gives us the ability to create gRPC servers in PHP which isn't possible through the standard gRPC extension for PHP or any other commonly used way to run PHP applications.

In the last part, I covered how to get setup with roadrunner for gRPC. Previous article: https://github.com/khepin/php-grpc-server-notes/blob/main/README.md

Here we'll cover an interesting feature of roadrunner: the ability to write Go code and call it from our PHP application. In my tests (local machine with docker), the overhead of making such a call was around `0.2ms` which might be well worth it for many scenarios.

The go addon to roadrunner we'll be writing though has nothing to do with performance.

## Debugging on Roadrunner

I've found simple debugging on Roadrunner to be sub-par so far. I don't use a debugger. All my debugging is done by thinking where the problem could be, making an assumption / hypothesis and verifying it's validity via the almighty dump / print statement.

When using Roadrunner, printing / echo-ing to stdout is interpreted as PHP sending information back to the Roadrunner server and should follow a specific format, for that. Likely a serialized Response object. So we can't like with `mod-http` or `php-fpm` just echo things out as part of the response. This works "even less" in a way when using gRPC.

Roadrunner provides an ability to use `error_log` and have the results of that call printed as part of the standard error roadrunner logs. `error_log` kinda works, but it's nothing to be compared with symfony's `var_dumper` for example.

So here's what we're going to build: a debug server. Whenever we call the `rrdump($var)` function in our PHP code, it'll send a roadrunner RPC message to a Go service we built with a nice HTML representation of the data being dumped. For good measure, we'll throw in the stack trace, the file + line where this was called and the arguments of the function that was being called.

## The PHP Dumper

On the PHP side, we create an `RRDumper` class to hold the logic of dumping a variable. Since we'll want this to be globally available via the `rrdump` function for ease of use, we'll make sure this class has a singleton static instance.

To start, we'll have a `getDumpString` method on that class that will allow us to retrieve the HTML dumped value for a given variable. We're using the `symfony/var-dumper` package for this rendering. Our class looks like:

```php
class RRDumper
{
    protected static RRDumper $instance;

    protected VarCloner $cloner;

    protected HtmlDumper $dumper;

    public static function i()
    {
        return self::$instance;
    }

    public static function setupInstance()
    {
        self::$instance = new self;
        self::$instance->cloner = new VarCloner();
        self::$instance->dumper = new HtmlDumper();
    }

    public function getDumpString($variable) : string
    {
        $output = '';

        $this->dumper->dump(
            $this->cloner->cloneVar($variable),
            function ($line, $depth) use (&$output) {
                // A negative depth means "end of dump"
                if ($depth >= 0) {
                    // Adds a two spaces indentation to the line
                    $output .= str_repeat('  ', $depth).$line."\n";
                }
            }
        );

        return $output;
    }
}
```

The next step is to add a `dump()` function. This function does 2 things: gather the dumped data and send it to our yet to come Go debugging server. Every intermediate level / function you add will change the shape of your stacktrace and therefore how you're retrieving some of the information. So be careful if you're about to embark on refactoring this code.

```php
public function dump($variable) : string
{
    // Get the backtrace and the information we care about from it.
    $bt = debug_backtrace();
    // We expect not to be called directly but to have been called from the `rrdump` function
    // if we were called directly, this `1` would be `0` etc...
    $file = $bt[1]['file'];
    $line = $bt[1]['line'];
    $funcOrMethod = $bt[2]['function'];
    $args = $bt[2]['args'];

    // our response data containing all the elements we care about
    $result = json_encode([
        'stacktrace' => $this->getDumpString($bt),
        'file' => $file,
        'line' => $line,
        'func' => $funcOrMethod,
        'args' => $this->getDumpString($args),
        'dump' => $this->getDumpString($variable),
        'epochms' => (int) (microtime(true) *1000)
    ]);

    // Sending our info to the roadrunner service
    return $this->rpc->call("debugger.SendDebugInfo", $result);
}
```

So here our code relies on `$this->rpc` which we'll cover in just a bit and calls the `debugger` service's `SendDebugInfo` method our json encoded result. Let's tie things together: in the end our `RRDumper` class looks like this:

```php
class RRDumper
{
    protected static RRDumper $instance;

    protected RPC $rpc;

    protected VarCloner $cloner;

    protected HtmlDumper $dumper;

    public static function i()
    {
        return self::$instance;
    }

    public static function setupInstance(RPC $rpc)
    {
        self::$instance = new self;
        self::$instance->rpc = $rpc;
        self::$instance->cloner = new VarCloner();
        self::$instance->dumper = new HtmlDumper();
    }

    public function dump($variable) : string
    {
        // Get the backtrace and the information we care about from it.
        $bt = debug_backtrace();
        // We expect not to be called directly but to have been called from the `rrdump` function
        // if we were called directly, this `1` would be `0` etc...
        $file = $bt[1]['file'];
        $line = $bt[1]['line'];
        $funcOrMethod = $bt[2]['function'];
        $args = $bt[2]['args'];

        // our response data containing all the elements we care about
        $result = json_encode([
            'stacktrace' => $this->getDumpString($bt),
            'file' => $file,
            'line' => $line,
            'func' => $funcOrMethod,
            'args' => $this->getDumpString($args),
            'dump' => $this->getDumpString($variable),
            'epochms' => (int) (microtime(true) *1000)
        ]);

        // Sending our info to the roadrunner service
        return $this->rpc->call("debugger.SendDebugInfo", $result);
    }

    public function getDumpString($variable) : string
    {
        $output = '';

        $this->dumper->dump(
            $this->cloner->cloneVar($variable),
            function ($line, $depth) use (&$output) {
                // A negative depth means "end of dump"
                if ($depth >= 0) {
                    // Adds a two spaces indentation to the line
                    $output .= str_repeat('  ', $depth).$line."\n";
                }
            }
        );

        return $output;
    }
}
```

And we create the `rrdump` function with:
```php
$relay = new Spiral\Goridge\SocketRelay("127.0.0.1", 6001);
$rpc = new Spiral\Goridge\RPC($relay);

RRDumper::setupInstance($rpc);

function rrdump($variable) : string {
    return RRDumper::i()->dump($variable);
}
```

This means we'll be communicating our debug info over a localhost socket on port 6001.

With this done, we can now call `rrdump` in our code. For example in our cache service:

```php
public function Set(ContextInterface $ctx, SetRequest $in): SetResponse
{
    rrdump([
        'request' => json_decode($in->serializeToJsonString())
    ]);
    $this->storage[$in->getKey()] = $in->getValue();
    return new SetResponse(['OK' => true]);
}
```

The protobuf `SetRequest` class only has `private` properties which is why we're doing the encoding / decoding json here so we can actually have a dump result with visible information.

For now that code lives in my `worker.grpc.php`.

## The Go service

Our Go service will take 2 configuration values:
- The size of the history of `dump` values it should keep in memory
- The address on which it should server our debugger's UI

Those values will be added in our `.rr.yaml` config file as follows:

```yaml
debugger:
  HistorySize: 2000
  address: :8089
```
In this case we'll be serving on port 8089 and will keep a maximum of 2,000 debug messages.

### Getting the config

We'll start with just enough in the plugin to retrieve those config values. We'll create our plugin in `appserver/plugins/debugger`. There we create our `debugger.go`:

```go
package debugger

import (
	"github.com/davecgh/go-spew/spew"
	"github.com/spiral/roadrunner/service"
	"github.com/spiral/roadrunner/service/rpc"
)

const ID = "debugger"

type Service struct {
	Config *Config
}

func (s *Service) Init(r *rpc.Service, cfg *Config) (ok bool, err error) {
	s.Config = cfg
	spew.Dump(cfg)

	return true, nil
}

type Config struct {
	HistorySize uint
	Address     string
}

func (c *Config) Hydrate(cfg service.Config) error {
	return cfg.Unmarshal(&c)
}
```

We've created a `Service` type which takes the rpc service and the config as `Init` arguments. The rpc service will be used later. The config is the type we defined in this same package with the 2 `HistorySize` and `Address` fields defined in our config earlier.

We've also set an `ID` constant with the name `debugger`. This needs to match the top level name we used in our config.

With this we can register our service in our `appserver/main.go` file:

```go
package main

import (
	// ... previous imports
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
```

If we start our server now with docker-compose, we'll see the following output in the logs:

```
simplecache_1  | (*debugger.Config)(0xc000289580)({
simplecache_1  |  HistorySize: (uint) 2000,
simplecache_1  |  Address: (string) (len=5) ":8089"
simplecache_1  | })
```
Meaning our config has correctly been parsed and given to our service.

### Simple RPC

We'll start with an RPC method that just logs a message when it receives data from our PHP code to verify that the communication is working properly:

First make sure to have the `rpc` enabled in `.rr.yaml`:

```yaml
rpc:
  enable: true
  listen: tcp://127.0.0.1:6001
```

We'll now create the `rpcService` aspect of our `Service`. We're chosing to build all the RPC service related functionality on a separate type:

```go
type rpcService struct {}

func (ps *rpcService) SendDebugInfo(input string, output *string) error {
	*output = "OK"
	fmt.Println("received debug info")
	return nil
}
```
We can now register this `rpcService` on the `rpc` object provided in our `Init` method:

```go
func (s *Service) Init(r *rpc.Service, cfg *Config) (ok bool, err error) {
	s.Config = cfg

	r.Register("debugger", &rpcService{})

	return true, nil
}
```

If we restart our server, every time we send a `Set` request to our cache, in the log output of `docker-compose`, we'll see a line saying: `received debug info` corresponding to our call to `rrdump`.

### Storing debug logs

A great way to store a limited quantity of information (2000 items in our case) and override the oldest item with the newest one whenever we're already at capacity is the use of a Ring Buffer (https://en.wikipedia.org/wiki/Circular_buffer).

Go comes with a set of tools to make this relatively easy (see: https://golang.org/pkg/container/ring/).

So let's initialize our roadrunner service with a ring buffer sized accordingly with our configuration:

Our `Service` type is updating to store the ring buffer:

```go
type Service struct {
	Config *Config
	Buffer *ring.Ring
}
```

And we'll intialize it in our `Init()` method:

```go
func (s *Service) Init(r *rpc.Service, cfg *Config) (ok bool, err error) {
	s.Config = cfg
	s.Buffer = ring.New(int(cfg.HistorySize))

	r.Register("debugger", &rpcService{Service: s})

	return true, nil
}
```

Now when we receive a new call to `SendDebugInfo` we'll append the info to the buffer. Though in our case we'll prepend it so that when we output the entire ring, it's sorted newest to oldest. Our updated `rpcService` is as follows:

```go
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
```
We decode the received json in a generic map. Set it as the current value of our buffer then move the buffer to point to the previous element.

### Serving debug info over HTTP

Next we'll server our accumulated debug logs over HTTP so we can later build a web UI to use that API. We'll be using the `echo` web framework as it provides a convenient way to define our routes and handlers while staying fairly minimal.

Roadrunner can take special care of Services that will be creating their own servers like this and properly `Start` and `Stop` them at the appropriate time in its lifecycle. For this we'll provide the `Serve` and `Stop` methods on our service.

```go
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
```
We now configure our service with an instance of `echo.Echo`. Most of that setup is done in the `prepareHttp` method:

```go
func (s *Service) prepareHttp() {
	e := echo.New()

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
```
We will respond to the `http://localhost:8089/debuglogs` endpoint. And here we build our return value by walking over the ring buffer and only adding to our output elements of the ring buffer that were actually maps (our decoded debug information).

We've defined our routing here and now only need to let roadrunner properly start and stop the server:

```go
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
```
On `Serve` all we have to do is call `echo.Start` with the configured address. On `Stop`, we give echo up to 10 seconds to properly shutdown and also reset the ring buffer to a new, empty one.

With all this in place, if we restart everything and call our gRPC `Set` method, which in turn calls `rrdump`, we should be able to use our browser to go to `http://localhost:8089/debuglogs` and retrieve a list of debug objects.

## A UI for our debug logs

To tie everything together, we'll create a minimal `vue.js` app to display our logs. Our vue code will live in `appserver/plugins/debugger/frontend` and the built version will live in `appserver/plugins/debugger/assets`.

We'll also look into embedding those built JS files directly in our go binary so they can be served easily from there. Our main component, `App.vue` will have the title, make a request to our server to retrieve our debug information and create one `Dump` component per entry in our debug logs.

```vue
<template>
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>RoadRunner Debugger</title>
    </head>
    <body>
        <h1>RR gRPC Debugger</h1>
        <div v-for="(log, id) in debuglogs" :key=id>
            <Dump :value=log></Dump>
        </div>
    </body>
    </html>
</template>

<script>
import Dump from './Dump.vue';

export default {
    data() {
        return {
            "debuglogs": [],
        }
    },
	components: {
		Dump
    },
    created() {
        this.fetch()
    },
    methods: {
        fetch() {
            fetch("http://localhost:8089/debuglogs").then((v) => v.json().then((d) => this.debuglogs = d))
        },
    }
}
</script>
```

The `Dump.vue` component displays the information from a single dump and allows to toggle on / off the longer sections like the arguments and the stack trace:

```vue
<template>
    <div class="dump">
        <h2>{{value.file}}:{{value.line}}::{{value.func}}()</h2>
        <div v-html=value.dump></div>
        <h3 @click="displayArgs" class="arg-switch">args <small>({{this.display.args ? 'hide' : 'show'}})</small></h3>
        <div v-html=value.args v-if=display.args></div>
        <h3 @click="displayStacktrace" class="arg-switch">stacktrace <small>({{this.display.stacktrace ? 'hide' : 'show'}})</small></h3>
        <div v-html=value.stacktrace v-if=display.stacktrace></div>
    </div>
</template>

<script>
export default {
    data() {
        return {
            "display": {
                "args": false,
                "stacktrace": false,
            },
        }
    },
    props: ["value"],
    methods: {
        displayArgs() {
            this.display.args = !this.display.args;
        },
        displayStacktrace() {
            this.display.stacktrace = !this.display.stacktrace;
        }
    }
}
</script>

<style>
.dump {
    background-color: #D6EDFF;
    border-radius: 6px;
    border-color: #8B95C9;
    border-style: solid;
    border-width: 2px;
    padding: 15px;
    margin-bottom: 20px;
}

.arg-switch {
    cursor: pointer;
}

.arg-switch small {
    text-decoration: underline;
}
</style>
```

By calling `vue build`, we get a set of javascript, html and CSS files in a `dist` folder that are ready to be served. We simply move that content over to `assets` after the build is done.

### Embedding the built JS

We use `pkger` to embed the built frontend assets in our go binary. From within the `appserver` directory, run `pkger -include /plugins/debugger/assets`. This will create a `pkged.go` file next to `main.go`. That file contains the byte data for the files that were in the `assets` folder.

In `debugger.go`, we can serve those static files by updating our `prepareHttp` method with the following:

```go
func (s *Service) prepareHttp() {
	e := echo.New()

	// Static files
	e.GET("/", echo.WrapHandler(http.FileServer(pkger.Dir("/plugins/debugger/assets"))))
	e.GET("/index.html", echo.WrapHandler(http.FileServer(pkger.Dir("/plugins/debugger/assets"))))
	e.GET("/css/*", echo.WrapHandler(http.FileServer(pkger.Dir("/plugins/debugger/assets"))))
    e.GET("/js/*", echo.WrapHandler(http.FileServer(pkger.Dir("/plugins/debugger/assets"))))
```

Now if we build all our services, call the gRPC `Set` method of our cache which calls `rrdump`, we should be able to view our debug UI and open / close the args and stacktrace:

![debug-gif](https://raw.githubusercontent.com/khepin/php-grpc-server-notes/debugger/debugger.gif)

## Conclusion thingy

We've built a go plugin for roadrunner that can be called directly from PHP. We've also seen how to create a roadrunner plugin that's a server on its own.

Since last time I've also updated the tools I use to watch and rebuild things. I was having too many issues running multiple `watchexec` processes in parallel so I created https://github.com/khepin/watchspatch instead and that has been working great.
