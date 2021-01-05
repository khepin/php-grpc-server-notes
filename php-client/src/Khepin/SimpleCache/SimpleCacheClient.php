<?php
// GENERATED CODE -- DO NOT EDIT!

namespace Khepin\SimpleCache;

/**
 */
class SimpleCacheClient extends \Grpc\BaseStub {

    /**
     * @param string $hostname hostname
     * @param array $opts channel options
     * @param \Grpc\Channel $channel (optional) re-use channel object
     */
    public function __construct($hostname, $opts, $channel = null) {
        parent::__construct($hostname, $opts, $channel);
    }

    /**
     * @param \Khepin\SimpleCache\SetRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function Set(\Khepin\SimpleCache\SetRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/simplecache.SimpleCache/Set',
        $argument,
        ['\Khepin\SimpleCache\SetResponse', 'decode'],
        $metadata, $options);
    }

    /**
     * @param \Khepin\SimpleCache\DelRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function Del(\Khepin\SimpleCache\DelRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/simplecache.SimpleCache/Del',
        $argument,
        ['\Khepin\SimpleCache\DelResponse', 'decode'],
        $metadata, $options);
    }

    /**
     * @param \Khepin\SimpleCache\GetRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function Get(\Khepin\SimpleCache\GetRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/simplecache.SimpleCache/Get',
        $argument,
        ['\Khepin\SimpleCache\GetResponse', 'decode'],
        $metadata, $options);
    }

}
