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
        rrdump([
            'request' => json_decode($in->serializeToJsonString())
        ]);
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
