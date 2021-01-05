<?php declare(strict_types=1);

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
